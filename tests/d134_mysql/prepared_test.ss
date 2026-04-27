// D136 Phase 1 — prepared statement wire-level unit tests.
//
// No socket — buildComStmtPreparePayload / parsePrepareOk take payload buffers
// directly. Live sendComStmtPrepare → readPrepareOk → readParamDef →
// readColumnDefList → MysqlConnection.prepareStatement flow against real
// mysql:8 is exercised in Phase 3 d136_prepared_statement/integration_test.ss.
//
// PrepareOk fixtures use bash-printf + readFile — the 12-byte payload contains
// multiple 0x00 bytes (filler + zero-valued u16/u32 fields), so buildling the
// fixture via SS string concat (fromCharCode(0) + ...) would truncate via
// ss_string_concat strlen. readFile is binary-safe via charCodeAt direct
// GEP+load (see lib/binary.ss header note).
//
// Lives in tests/d134_mysql/ (alongside wire_test / query_test / handshake_test)
// per D136 §1 ContextManagement: prepared_test is a wire-level vec test that
// extends D134 Phase 4 query_test pattern. d136_prepared_statement/ is the
// e2e integration test directory (Phase 3, requires docker).

import { assertEqual, assertTrue } from "@/lib/test"
import { buildComStmtPreparePayload, parsePrepareOk, PrepareOk, MysqlPreparedStatement } from "@/lib/com/mysql/prepared"
import { ColumnDef } from "@/lib/com/mysql/query"

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

    // ── MysqlPreparedStatement Phase 1 framework shape ───────────
    test("MysqlPreparedStatement positional ctor + Phase 1 stub behavior", () => {
        let pDefs: Array<ColumnDef> = []
        let pTypes: Array<int> = []
        let pVals: Array<string> = []
        let pNulls: Array<int> = []
        let cols: Array<ColumnDef> = []
        cols = cols.push(new ColumnDef("id", 3, 11, 33))
        const stmt = new MysqlPreparedStatement(-1, 7, 0, pDefs, pTypes, pVals, pNulls, cols, 0)
        assertEqual(stmt.fd, -1)
        assertEqual(stmt.statementId, 7)
        assertEqual(stmt.numParams, 0)
        assertEqual(stmt.columnDefs.length(), 1)
        assertEqual(stmt.closed, 0)
        // Phase 1 executeUpdate stub returns -1 sentinel.
        assertEqual(stmt.executeUpdate(), -1)
        // Phase 1 close flips closed=1 without server roundtrip.
        stmt.close()
        assertEqual(stmt.closed, 1)
        // Phase 1 executeQuery returns a closed MysqlResultSet — next() == 0.
        const rs = stmt.executeQuery()
        assertEqual(rs.next(), 0)
    })

    println("All D136 Phase 1 prepared statement tests passed!")
}
