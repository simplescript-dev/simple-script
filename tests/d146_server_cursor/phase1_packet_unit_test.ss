// D146 Phase 1 unit test — pure local, no docker dependency.
// Verifies the protocol-layer building blocks added to lib/com/mysql/query.ss:
//   1. 4 cursor-flow constants match the MySQL Native Protocol §6.5 + EOF spec.
//   2. buildStmtFetchPayload produces the 9-byte payload in correct LE order.
//   3. eofStatusFlags reads the status_flags i16 LE at offset 3 and the
//      CURSOR_EXISTS / LAST_ROW_SENT bits can be detected via bit-AND.
//
// EOF synthesis caveat: SS string concat with fromCharCode(0) truncates via
// ss_string_concat strlen (lib/binary.ss header note). Test EOF payloads
// therefore use non-zero filler bytes 0x42 — bit-AND on the status_flags
// still isolates the CURSOR_EXISTS / LAST_ROW_SENT bits, which is the
// only thing callers care about. The exact strict-equality "status_flags
// == 0x0040" round-trip comes from real wire packets in the docker spike
// (phase1_spike_test.ss), where readPacket allocates a buffer + tcpReadBytes
// writes the bytes in directly bypassing string concat.
//
// See docs/3-decisions/D146-server-side-cursor.md §Phase 收关锚 §Phase 1.

import { assertEqual, assertTrue } from "@/lib/test"
import { COM_STMT_FETCH, CURSOR_TYPE_READ_ONLY, SERVER_STATUS_CURSOR_EXISTS, SERVER_STATUS_LAST_ROW_SENT, buildStmtFetchPayload, eofStatusFlags } from "@/lib/com/mysql/query"

function main() {
    test("cursor-flow constants match MySQL Native Protocol §6.5 + EOF spec", () => {
        // COM_STMT_FETCH command byte — MySQL spec §6.5
        assertEqual(COM_STMT_FETCH, 0x1c)
        // CURSOR_TYPE_READ_ONLY — COM_STMT_EXECUTE flags bit 0
        assertEqual(CURSOR_TYPE_READ_ONLY, 0x01)
        // EOF status_flags bit 6 — server still holds rows
        assertEqual(SERVER_STATUS_CURSOR_EXISTS, 0x0040)
        // EOF status_flags bit 7 — cursor exhausted
        assertEqual(SERVER_STATUS_LAST_ROW_SENT, 0x0080)
        // The two status flags are independent bits
        assertEqual(SERVER_STATUS_CURSOR_EXISTS & SERVER_STATUS_LAST_ROW_SENT, 0)
    })

    test("buildStmtFetchPayload(1, 5) — small ids preserve LE high zeros", () => {
        // Realistic case: server-allocated statement_ids start at 1, fetch
        // size is typically 10-100. The LE encoding has zero high bytes
        // that would be lost in a string-based payload (lib/binary.ss
        // intToBytes truncation). Array<int> sidesteps the limitation.
        const bytes = buildStmtFetchPayload(1, 5)
        assertEqual(bytes.length(), 9)
        // [0] = 0x1c COM_STMT_FETCH
        assertEqual(bytes[0], 0x1c)
        // [1..4] = statement_id 1 LE
        assertEqual(bytes[1], 0x01)
        assertEqual(bytes[2], 0x00)
        assertEqual(bytes[3], 0x00)
        assertEqual(bytes[4], 0x00)
        // [5..8] = num_rows 5 LE
        assertEqual(bytes[5], 0x05)
        assertEqual(bytes[6], 0x00)
        assertEqual(bytes[7], 0x00)
        assertEqual(bytes[8], 0x00)
    })

    test("buildStmtFetchPayload(0x12345678, 0xABCDEF) — full 4-byte LE coverage", () => {
        // Large statement_id + num_rows: every byte position is non-zero
        // (for the first three bytes) so we can verify the byte ordering
        // matches MySQL LE convention without the SS string-concat caveat.
        const bytes = buildStmtFetchPayload(0x12345678, 0xABCDEF)
        assertEqual(bytes.length(), 9)
        assertEqual(bytes[0], 0x1c)
        // statement_id 0x12345678 → bytes [0x78, 0x56, 0x34, 0x12]
        assertEqual(bytes[1], 0x78)
        assertEqual(bytes[2], 0x56)
        assertEqual(bytes[3], 0x34)
        assertEqual(bytes[4], 0x12)
        // num_rows 0x00ABCDEF → bytes [0xEF, 0xCD, 0xAB, 0x00]
        assertEqual(bytes[5], 0xEF)
        assertEqual(bytes[6], 0xCD)
        assertEqual(bytes[7], 0xAB)
        assertEqual(bytes[8], 0x00)
    })

    test("eofStatusFlags decodes CURSOR_EXISTS bit (server still holds rows)", () => {
        // Legacy EOF layout: 0xFE + warnings i16 LE + status_flags i16 LE.
        // We synthesize a payload where every byte is non-zero so the
        // string concat path produces a 5-byte buffer (no strlen truncation
        // surprises). status_flags = 0x4240 → low byte 0x40 sets bit 6
        // (CURSOR_EXISTS), high byte 0x42 is filler.
        let payload = ""
        payload = payload + fromCharCode(0xFE)  // EOF header
        payload = payload + fromCharCode(0x42)  // warnings byte 0
        payload = payload + fromCharCode(0x42)  // warnings byte 1
        payload = payload + fromCharCode(0x40)  // status_flags byte 0 = 0x40 (CURSOR_EXISTS bit)
        payload = payload + fromCharCode(0x42)  // status_flags byte 1 = 0x42 filler
        const flags = eofStatusFlags(payload, 5)
        // Full status_flags = 0x4240 (low 0x40 + high 0x4200)
        assertEqual(flags, 0x4240)
        // CURSOR_EXISTS bit is set
        assertTrue((flags & SERVER_STATUS_CURSOR_EXISTS) != 0)
        // LAST_ROW_SENT bit is NOT set
        assertEqual(flags & SERVER_STATUS_LAST_ROW_SENT, 0)
    })

    test("eofStatusFlags decodes LAST_ROW_SENT bit (cursor exhausted)", () => {
        let payload = ""
        payload = payload + fromCharCode(0xFE)  // EOF header
        payload = payload + fromCharCode(0x42)  // warnings byte 0
        payload = payload + fromCharCode(0x42)  // warnings byte 1
        payload = payload + fromCharCode(0x80)  // status_flags byte 0 = 0x80 (LAST_ROW_SENT bit)
        payload = payload + fromCharCode(0x42)  // status_flags byte 1 = 0x42 filler
        const flags = eofStatusFlags(payload, 5)
        // Full status_flags = 0x4280
        assertEqual(flags, 0x4280)
        // LAST_ROW_SENT bit is set
        assertTrue((flags & SERVER_STATUS_LAST_ROW_SENT) != 0)
        // CURSOR_EXISTS bit is NOT set (cursor is gone, no more fetches)
        assertEqual(flags & SERVER_STATUS_CURSOR_EXISTS, 0)
    })

    test("eofStatusFlags defensive — short payload / wrong header returns 0", () => {
        // Defensive path 1: payload too short for legacy EOF (< 5 bytes).
        // Pre-4.1 servers without CLIENT_PROTOCOL_41 omit warnings + flags;
        // a 1-byte 0xFE EOF would be misread as flags = (garbage).
        let shortPayload = ""
        shortPayload = shortPayload + fromCharCode(0xFE)
        shortPayload = shortPayload + fromCharCode(0x42)
        assertEqual(eofStatusFlags(shortPayload, 2), 0)

        // Defensive path 2: wrong header (e.g. an OK packet bleed-through
        // from misaligned packet boundaries). 0x00 != EOF_HEADER 0xFE.
        let wrongPayload = ""
        wrongPayload = wrongPayload + fromCharCode(0x42)  // not 0xFE
        wrongPayload = wrongPayload + fromCharCode(0x42)
        wrongPayload = wrongPayload + fromCharCode(0x42)
        wrongPayload = wrongPayload + fromCharCode(0x40)
        wrongPayload = wrongPayload + fromCharCode(0x42)
        assertEqual(eofStatusFlags(wrongPayload, 5), 0)
    })
}
