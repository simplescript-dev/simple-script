// D136 Phase 1 + Phase 2 — prepared statement wire-level unit tests.
//
// No socket — buildComStmtPreparePayload / parsePrepareOk / parseBinaryRow /
// binaryValueSize take payload buffers + arrays directly. Live sendComStmtPrepare
// / sendComStmtExecute / sendComStmtClose paths against real mysql:8 are
// exercised in Phase 3 d136_prepared_statement/integration_test.ss.
//
// PrepareOk + binary row fixtures use bash-printf + readFile — payloads contain
// multiple 0x00 bytes (PrepareOk filler/u32/u16 zero-valued fields; binary row
// NULL bitmap zero bits + integer zero high-bytes + IEEE 754 mantissa tails),
// so building a fixture via SS string concat (fromCharCode(0) + ...) would
// truncate via ss_string_concat strlen. readFile is binary-safe via charCodeAt
// direct GEP+load (see lib/binary.ss header note).
//
// Lives in tests/d134_mysql/ (alongside wire_test / query_test / handshake_test)
// per D136 §1 ContextManagement: prepared_test is a wire-level vec test that
// extends D134 Phase 4 query_test pattern. d136_prepared_statement/ is the
// e2e integration test directory (Phase 3, requires docker).

import { assertEqual, assertTrue } from "@/lib/test"
import { buildComStmtPreparePayload, parsePrepareOk, PrepareOk, MysqlPreparedStatement, parseBinaryRow, binaryValueSize } from "@/lib/com/mysql/prepared"
import { ColumnDef } from "@/lib/com/mysql/query"
import { hexByte } from "@/lib/sha256"

function main() {
    // ── buildComStmtPreparePayload: cmd byte + sql ASCII concat ──
    test("buildComStmtPreparePayload SELECT with placeholder", () => {
        const sql = "SELECT id FROM users WHERE id = ?"
        const payload = buildComStmtPreparePayload(sql)
        // Total length = 1 (cmd) + sql length
        assertEqual(payload.length(), sql.length() + 1)
        // First byte = COM_STMT_PREPARE = 0x16
        assertEqual(charCodeAt(payload, 0), 0x16)
        // Second byte = 'S' (0x53) — start of "SELECT"
        assertEqual(charCodeAt(payload, 1), 0x53)
        // Tail byte = '?' (0x3F) — last char of bound sql
        assertEqual(charCodeAt(payload, sql.length()), 0x3F)
    })

    test("buildComStmtPreparePayload empty sql", () => {
        const payload = buildComStmtPreparePayload("")
        // Bare cmd byte, no sql tail
        assertEqual(payload.length(), 1)
        assertEqual(charCodeAt(payload, 0), 0x16)
    })

    // ── parsePrepareOk: 12-byte payload reference vec ────────────
    // Layout (D136 §A.2):
    //   1   header 0x00
    //   4   statement_id u32 LE
    //   2   num_columns u16 LE
    //   2   num_params u16 LE
    //   1   filler 0x00
    //   2   warning_count u16 LE
    test("parsePrepareOk single-param single-column zero warnings", () => {
        // statement_id=1, num_columns=1, num_params=1, warning_count=0
        const cmd = "bash -c \"printf '\\x00\\x01\\x00\\x00\\x00\\x01\\x00\\x01\\x00\\x00\\x00\\x00' > /tmp/d136_prep_ok1.bin\""
        system(cmd)
        const buf = readFile("/tmp/d136_prep_ok1.bin")
        const ok = parsePrepareOk(buf, 12)
        assertEqual(ok.statementId, 1)
        assertEqual(ok.numColumns, 1)
        assertEqual(ok.numParams, 1)
        assertEqual(ok.warningCount, 0)
    })

    test("parsePrepareOk multi-column multi-param", () => {
        // statement_id=0x12345678, num_columns=3, num_params=2, warning_count=0
        const cmd = "bash -c \"printf '\\x00\\x78\\x56\\x34\\x12\\x03\\x00\\x02\\x00\\x00\\x00\\x00' > /tmp/d136_prep_ok2.bin\""
        system(cmd)
        const buf = readFile("/tmp/d136_prep_ok2.bin")
        const ok = parsePrepareOk(buf, 12)
        assertEqual(ok.statementId, 0x12345678)
        assertEqual(ok.numColumns, 3)
        assertEqual(ok.numParams, 2)
        assertEqual(ok.warningCount, 0)
    })

    test("parsePrepareOk with warning_count > 0", () => {
        // statement_id=42, num_columns=0 (DDL/UPDATE), num_params=4, warning_count=7
        const cmd = "bash -c \"printf '\\x00\\x2a\\x00\\x00\\x00\\x00\\x00\\x04\\x00\\x00\\x07\\x00' > /tmp/d136_prep_ok3.bin\""
        system(cmd)
        const buf = readFile("/tmp/d136_prep_ok3.bin")
        const ok = parsePrepareOk(buf, 12)
        assertEqual(ok.statementId, 42)
        assertEqual(ok.numColumns, 0)
        assertEqual(ok.numParams, 4)
        assertEqual(ok.warningCount, 7)
    })

    // ── parsePrepareOk: short payload safety ─────────────────────
    test("parsePrepareOk short payload returns zero PrepareOk", () => {
        // 11-byte payload — 1 byte short of the 12-byte spec; defensive return.
        const ok = parsePrepareOk(fromCharCode(0x00), 1)
        assertEqual(ok.statementId, 0)
        assertEqual(ok.numColumns, 0)
        assertEqual(ok.numParams, 0)
        assertEqual(ok.warningCount, 0)
    })

    test("parsePrepareOk wrong header returns zero PrepareOk", () => {
        // 12 bytes, but first byte is 0xFF (ERR header) instead of 0x00 — defensive.
        const cmd = "bash -c \"printf '\\xff\\x01\\x00\\x00\\x00\\x01\\x00\\x01\\x00\\x00\\x00\\x00' > /tmp/d136_prep_err.bin\""
        system(cmd)
        const buf = readFile("/tmp/d136_prep_err.bin")
        const ok = parsePrepareOk(buf, 12)
        assertEqual(ok.statementId, 0)
        assertEqual(ok.numColumns, 0)
        assertEqual(ok.numParams, 0)
        assertEqual(ok.warningCount, 0)
    })

    // ── PrepareOk positional constructor ─────────────────────────
    test("PrepareOk positional constructor", () => {
        const ok = new PrepareOk(99, 5, 3, 2)
        assertEqual(ok.statementId, 99)
        assertEqual(ok.numColumns, 5)
        assertEqual(ok.numParams, 3)
        assertEqual(ok.warningCount, 2)
    })

    // ── Phase 2 / setXxx ─ MysqlPreparedStatement bind state writes ────
    test("MysqlPreparedStatement positional ctor + setXxx state writes", () => {
        let pDefs: Array<ColumnDef> = []
        let cols: Array<ColumnDef> = []
        cols = cols.push(new ColumnDef("id", 3, 11, 33, "", 0, "", "", "", "", 0))
        const stmt = new MysqlPreparedStatement(-1, 7, 3, pDefs, [0, 0, 0], ["", "", ""], [0.0, 0.0, 0.0], [0, 0, 0], cols, 0, 0, 0, 0, 0)
        assertEqual(stmt.fd, -1)
        assertEqual(stmt.statementId, 7)
        assertEqual(stmt.numParams, 3)
        assertEqual(stmt.columnDefs.length(), 1)
        assertEqual(stmt.closed, 0)
        // setInt(1, 42) writes MYSQL_TYPE_LONG + decimal repr at idx-1=0.
        stmt.setInt(1, 42)
        assertEqual(stmt.paramTypes[0], 3)
        assertEqual(stmt.paramValues[0], "42")
        assertEqual(stmt.paramNullBits[0], 0)
        // setString(2, "Alice") at idx-1=1.
        stmt.setString(2, "Alice")
        assertEqual(stmt.paramTypes[1], 253)
        assertEqual(stmt.paramValues[1], "Alice")
        // setDouble(3, 3.14) writes MYSQL_TYPE_DOUBLE + parks bits in paramDoubles.
        stmt.setDouble(3, 3.14)
        assertEqual(stmt.paramTypes[2], 5)
        assertEqual(stmt.paramDoubles[2], 3.14)
        // setNull(2) overrides idx 2 — type=NULL, null bit=1.
        stmt.setNull(2)
        assertEqual(stmt.paramTypes[1], 6)
        assertEqual(stmt.paramNullBits[1], 1)
        // setLong(1, 999) re-binds idx 1 — null bit clears, type flips to LONGLONG.
        stmt.setLong(1, 999)
        assertEqual(stmt.paramTypes[0], 8)
        assertEqual(stmt.paramValues[0], "999")
        assertEqual(stmt.paramNullBits[0], 0)
        // setBoolean(3, 1) flips idx 3 from DOUBLE → LONG (TINYINT(1) widening).
        stmt.setBoolean(3, 1)
        assertEqual(stmt.paramTypes[2], 3)
        assertEqual(stmt.paramValues[2], "1")
        // setBoolean(3, 0) → "0".
        stmt.setBoolean(3, 0)
        assertEqual(stmt.paramValues[2], "0")
    })

    // ── Phase 2 / parseBinaryRow ─ 4 column INT/VARCHAR/DOUBLE/NULL ────
    // Row layout (D136 §A.4):
    //   1B 0x00 header
    //   1B NULL bitmap — (4+7+2)/8 = 1 byte; bit 5 set marks col 3 NULL (idx+2 = 3+2)
    //   4B u32 LE 42 — col 0 LONG
    //   1B 0x05 + 5B "Alice" — col 1 VAR_STRING
    //   8B IEEE 754 LE of 3.14 = 1f 85 eb 51 b8 1e 09 40 — col 2 DOUBLE
    //   (col 3 NULL — no value bytes)
    test("parseBinaryRow 4-column INT/VARCHAR/DOUBLE/NULL mix", () => {
        const cmd = "bash -c \"printf '\\x00\\x20\\x2a\\x00\\x00\\x00\\x05Alice\\x1f\\x85\\xeb\\x51\\xb8\\x1e\\x09\\x40' > /tmp/d136_binrow1.bin\""
        system(cmd)
        const buf = readFile("/tmp/d136_binrow1.bin")
        let cols: Array<ColumnDef> = []
        cols = cols.push(new ColumnDef("id", 3, 11, 33, "", 0, "", "", "", "", 0))
        cols = cols.push(new ColumnDef("name", 253, 64, 33, "", 0, "", "", "", "", 0))
        cols = cols.push(new ColumnDef("price", 5, 8, 63, "", 0, "", "", "", "", 0))
        cols = cols.push(new ColumnDef("notes", 253, 64, 33, "", 0, "", "", "", "", 0))
        const row = parseBinaryRow(buf, 20, cols)
        assertEqual(row.length(), 4)
        assertEqual(row[0], "42")
        assertEqual(row[1], "Alice")
        // Decimal repr of 3.14 from ss_double_to_string is platform-specific
        // (snprintf %g style). Round-trip parseDouble for a stable cross-check.
        assertTrue(parseDouble(row[2]) > 3.13)
        assertTrue(parseDouble(row[2]) < 3.15)
        assertEqual(row[3], "")
    })

    // ── Phase 2 / parseBinaryRow ─ NULL bitmap +2 offset 2-byte boundary ────
    // numColumns=14 → bitmap length = (14+7+2)/8 = 23/8 = 2 byte.
    // Mark col 0 as NULL → bit (0+2)=2 in byte 0 → byte 0 = 0x04, byte 1 = 0x00.
    // Cols 1..13 each LONG with value matching their idx (1..13).
    // Payload = 1 (header) + 2 (bitmap) + 13*4 (values) = 55 byte.
    test("parseBinaryRow NULL bitmap +2 offset 2-byte boundary numColumns=14", () => {
        // Build 13 little-endian u32 values for cols 1..13 — bash-printf concat.
        let cmd = "bash -c \"printf '\\x00\\x04\\x00"
        let i = 1
        while (i <= 13) {
            cmd = cmd + "\\x" + hexByte(i & 0xFF) + "\\x00\\x00\\x00"
            i = i + 1
        }
        cmd = cmd + "' > /tmp/d136_binrow2.bin\""
        system(cmd)
        const buf = readFile("/tmp/d136_binrow2.bin")
        let cols: Array<ColumnDef> = []
        let j = 0
        while (j < 14) {
            cols = cols.push(new ColumnDef("c", 3, 11, 33, "", 0, "", "", "", "", 0))
            j = j + 1
        }
        const row = parseBinaryRow(buf, 55, cols)
        assertEqual(row.length(), 14)
        assertEqual(row[0], "")
        assertEqual(row[1], "1")
        assertEqual(row[7], "7")
        assertEqual(row[13], "13")
    })

    // ── Phase 2 / binaryValueSize ─ 5 subset + VARCHAR length-encoded triplet ────
    // Length-encoded VARCHAR prefix sizing:
    //   len < 0xFB     →  1 + len  (single byte)
    //   len < 65536    →  3 + len  (0xFC + 2B LE)
    //   len < 16777216 →  4 + len  (0xFD + 3B LE)
    //   ≥ 16777216     →  9 + len  (0xFE + 8B LE)
    // We exercise the first three boundary transitions; the 16M threshold needs
    // a 16M-byte fixture and is left to e2e (Phase 3 will not exceed it either).
    test("binaryValueSize 5-subset + VARCHAR length-encoded boundaries", () => {
        // Fixed-width subset.
        assertEqual(binaryValueSize(3, ""), 4)        // MYSQL_TYPE_LONG
        assertEqual(binaryValueSize(8, ""), 8)        // MYSQL_TYPE_LONGLONG
        assertEqual(binaryValueSize(5, ""), 8)        // MYSQL_TYPE_DOUBLE
        assertEqual(binaryValueSize(6, ""), 0)        // MYSQL_TYPE_NULL
        // VARCHAR — first boundary (< 0xFB).
        assertEqual(binaryValueSize(253, "abc"), 4)
        assertEqual(binaryValueSize(253, "x".repeat(250)), 251)
        // VARCHAR — second boundary (251 .. 65535).
        assertEqual(binaryValueSize(253, "x".repeat(251)), 254)
        assertEqual(binaryValueSize(253, "x".repeat(1024)), 1027)
        // VARCHAR — third boundary (65536 .. 16M-1).
        assertEqual(binaryValueSize(253, "x".repeat(65536)), 65540)
    })

    println("All D136 prepared statement tests passed!")
}
