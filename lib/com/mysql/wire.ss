// MySQL wire protocol packet read/write — D134 §A.4
// Packet format: 3-byte LE payload length + 1-byte sequence id + payload bytes.
// Phase 2 covers payload ≤ 16MB; the 0xFFFFFF continuation rule (D134 §A.4) is
// out of scope (sub-D follow-up).
//
// API deviates from D134 §3 Phase 2 literal spec:
//   - readPacket returns class MysqlPacket (not string) so caller gets payloadLen
//     and seqId without relying on payload.length() — payload may have embedded
//     0x00 bytes that would lie to ss_stringLength (gen_rt_string.ss:6-12).
//   - writePacket takes explicit payloadLen (4 args, not 3) for the same reason
//     when caller passes a payload buffer with embedded NULLs.

import { byteToInt } from "@/lib/binary"

class MysqlPacket {
    let payload: string = ""
    let payloadLen: int = 0
    let seqId: int = 0
}

// Reads exactly `len` bytes from fd into a fresh buffer. Buffer is pre-allocated
// via " ".repeat(len) so it has `len` writable bytes (all 0x20). After the syscall
// the buffer holds raw bytes including any embedded 0x00 — caller must access via
// charCodeAt(buf, i) for i in [0, len), never via .length() (which uses strlen).
// Returns "" on EOF / partial read (signals protocol error to caller).
function readExactBytes(fd: int, len: int): string {
    if (len <= 0) { return "" }
    const buf = " ".repeat(len)
    const nread = tcpReadBytes(fd, buf, len)
    if (nread != len) { return "" }
    return buf
}

// Reads one MySQL packet. Returns MysqlPacket with payload, payloadLen, seqId.
// On EOF or short read returns a packet with payloadLen = -1 (caller checks).
function readPacket(fd: int): MysqlPacket {
    const pkt = new MysqlPacket
    const header = readExactBytes(fd, 4)
    if (header == "") {
        pkt.payloadLen = -1
        return pkt
    }
    pkt.payloadLen = byteToInt(header, 0, 3)
    pkt.seqId = charCodeAt(header, 3)
    if (pkt.payloadLen > 0) {
        pkt.payload = readExactBytes(fd, pkt.payloadLen)
        if (pkt.payload == "") {
            pkt.payloadLen = -1
        }
    }
    return pkt
}

// Writes a 4-byte header (payloadLen LE + seqId) followed by `payloadLen` payload
// bytes. Header is written byte-by-byte via tcpWriteBytes(fd, fromCharCode(b), 1)
// because header bytes 1..2 are typically 0x00 (payloadLen < 256 → middle bytes
// zero). fromCharCode(0) returns ptr to a 2-byte alloc with first byte 0; combined
// with explicit len=1, tcpWriteBytes writes exactly 1 byte ignoring strlen.
// Returns total bytes written (4 + payloadLen) on success.
function writePacket(fd: int, seqId: int, payload: string, payloadLen: int): int {
    tcpWriteBytes(fd, fromCharCode(payloadLen & 0xFF), 1)
    tcpWriteBytes(fd, fromCharCode((payloadLen >>> 8) & 0xFF), 1)
    tcpWriteBytes(fd, fromCharCode((payloadLen >>> 16) & 0xFF), 1)
    tcpWriteBytes(fd, fromCharCode(seqId & 0xFF), 1)
    if (payloadLen > 0) {
        tcpWriteBytes(fd, payload, payloadLen)
    }
    return 4 + payloadLen
}
