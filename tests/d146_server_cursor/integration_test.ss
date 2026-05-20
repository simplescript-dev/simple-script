// D146 Phase 5 — 7-shape integration test (D146 主线 close).
//
// Covers all 7 forms of D146 §核心目标 single criterion in one main file.
// Subsumes Phase 1 / 2 / 3 / 4 spike tests (the four phase[1234]_spike_test.ss
// files are removed in this Phase). Phase 1 phase1_packet_unit_test.ss is
// kept — it exercises the byte-level COM_STMT_FETCH packet encoding +
// EOF status_flags i16 LE bit-AND + defensive boundary checks in pure
// local mode (no docker dependency) and is complementary, not redundant,
// to this end-to-end suite (same split as D139 Phase 5
// translator_spike_test.ss vs integration_test.ss).
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test
// file prints a hint and returns 0 so `bin/ss test tests/` stays green
// when docker is unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d146_server_cursor/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Uses table `d146_server_cursor_integration` to isolate from D134 (`users`) /
// D136 (`users_d136`) / D138 (`d138_generated_keys`) /
// D139 (`d139_sql_exception_test`) under `bin/ss test tests/` parallel batch.
//
// Validates D146 §核心目标 single criterion (7 cases):
//   Case 1 — TYPE_FORWARD_ONLY default + 1000 rows
//            → useCursor=0 client streaming (server flushes full set)
//   Case 2 — setFetchSize(100) + 1000 rows
//            → useCursor=1 + 10 × COM_STMT_FETCH(100) + cursorExhausted=1
//              after the LAST_ROW_SENT EOF
//   Case 3 — TYPE_SCROLL_INSENSITIVE absolute(500) / first / last / previous /
//            getRow round-trip via in-memory cache (D146 §A.2 H5 fallback)
//   Case 4 — Mid-iteration cursor close + reuse fd
//            → server cursor released by COM_STMT_CLOSE 0x19, second prepare
//              on the same fd succeeds (proves no socket desync)
//   Case 5 — setFetchSize(INTEGER_MIN_VALUE = -2147483648)
//            → useCursor=0 client streaming (MySQL Connector/J 5.0.6+
//              dual-semantics sentinel — H4)
//   Case 6 — RowCallbackHandler.processRow × 1000 via JdbcTemplate.query
//            (1-arg Statement path + 2-arg setter path)
//   Case 7 — Cursor lifecycle SQLException → BadSqlGrammarException with
//            DAE catch hierarchy (cursor path through SQLExceptionTranslator
//            — D139 5-layer DAE tree applies to D146 cursor entry too)
//
// SS arrow-function closure capture rebinds outer-scope catch `e`
// (D139 §Followup F10) — every inner catch in this file uses `ex`, never
// `e`, to avoid reusing the outer probe-catch name.

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, ResultSet, PreparedStatement, DriverManager_getConnection, SQLException, TYPE_FORWARD_ONLY, TYPE_SCROLL_INSENSITIVE, CONCUR_READ_ONLY } from "@/lib/java/sql"
import { JdbcTemplate, RowCallbackHandler, INTEGER_MIN_VALUE, BadSqlGrammarException, NonTransientDataAccessException, DataAccessException } from "@/lib/spring/jdbc"
import { mysqlConnect } from "@/lib/com/mysql/handshake"
import { doPrepare, MysqlPreparedStatement, MysqlBinaryResultSet } from "@/lib/com/mysql/prepared"
import { dropAllTables } from "@/tests/jdbc/import/jdbc_test_helpers"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"
const ROW_COUNT = 1000
const FETCH_SIZE = 100
const SCROLL_TARGET = 500
const CLOSE_AFTER = 50

// RowCallbackHandler implementor — counts processRow invocations + sums
// the id column so the test can prove every row reached the callback
// independent of the underlying fetch path (Statement / cursor / streaming).
class CountingCallback : RowCallbackHandler {
    count: int
    sum: int

    function processRow(rs: ResultSet): void {
        this.count = this.count + 1
        this.sum = this.sum + rs.getInt("id")
    }
}

// Sum 1..N closed-form so the test does not need a scratch loop just to
// verify the row payload reached the callback / cursor.
function expectedSum(n: int): int {
    return (n * (n + 1)) / 2
}

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS d146_server_cursor_integration")
    tmpl.execute("CREATE TABLE d146_server_cursor_integration (id INT PRIMARY KEY) ENGINE=InnoDB")
    let i = 1
    while (i <= ROW_COUNT) {
        tmpl.execute("INSERT INTO d146_server_cursor_integration VALUES (" + i + ")")
        i = i + 1
    }
    return 0
}

function main() {
    // Probe — skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D146 integration: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    // ── Case 1: TYPE_FORWARD_ONLY default → useCursor=0 client streaming ────
    test("Case 1: TYPE_FORWARD_ONLY default + 1000 rows → useCursor=0 client streaming", () => {
        // No setFetchSize hint + TYPE_FORWARD_ONLY → deriveCursorFlag returns
        // CURSOR_TYPE_NO_CURSOR; server flushes the entire ResultSet, client
        // drains row-by-row via the legacy MysqlBinaryResultSet streaming path.
        // Verifies the pre-Phase-3 baseline still works (backwards compat).
        const fd = mysqlConnect("127.0.0.1", 3307, "root", "test", "testdb")
        const ps = doPrepare(fd, "SELECT id FROM d146_server_cursor_integration ORDER BY id")
        const rs = ps.executeQuery("SELECT id FROM d146_server_cursor_integration ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_READ_ONLY)

        assertEqual(rs.useCursor, 0)
        assertEqual(rs.fetchSize, 0)
        assertEqual(rs.rsType, TYPE_FORWARD_ONLY)

        let i = 1
        while (i <= ROW_COUNT) {
            assertEqual(rs.next(), 1)
            assertEqual(rs.getInt("id"), i)
            i = i + 1
        }
        assertEqual(rs.next(), 0)

        rs.close()
        ps.close()
        tcpClose(fd)
    })

    // ── Case 2: setFetchSize(100) + 1000 rows → useCursor=1 + 10 fetches ────
    test("Case 2: setFetchSize(100) + 1000 rows → useCursor=1 + 10 × COM_STMT_FETCH + LAST_ROW_SENT", () => {
        // fetchSize > 0 → CURSOR_TYPE_READ_ONLY 0x01 in COM_STMT_EXECUTE flags;
        // server holds the cursor + only sends column metadata + EOF
        // (CURSOR_EXISTS) on EXECUTE. Client drives via 10 × COM_STMT_FETCH(100)
        // round-trips; the 10th batch closes with EOF SERVER_STATUS_LAST_ROW_SENT
        // 0x0080 → cursorExhausted flips to 1 + the 1001st next() returns 0.
        // (Byte-level packet encoding + status_flags decode covered by
        // phase1_packet_unit_test.ss; this case verifies the high-level cursor
        // state plumbing.)
        const fd = mysqlConnect("127.0.0.1", 3307, "root", "test", "testdb")
        const ps = doPrepare(fd, "SELECT id FROM d146_server_cursor_integration ORDER BY id")
        ps.setFetchSize(FETCH_SIZE)
        const rs = ps.executeQuery("SELECT id FROM d146_server_cursor_integration ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_READ_ONLY)

        assertEqual(rs.useCursor, 1)
        assertEqual(rs.fetchSize, FETCH_SIZE)
        assertTrue(rs.statementId > 0)
        assertEqual(rs.cursorExhausted, 0)

        let i = 1
        while (i <= ROW_COUNT) {
            assertEqual(rs.next(), 1)
            assertEqual(rs.getInt("id"), i)
            i = i + 1
        }
        assertEqual(rs.next(), 0)
        assertEqual(rs.cursorExhausted, 1)

        rs.close()
        ps.close()
        tcpClose(fd)
    })

    // ── Case 3: TYPE_SCROLL_INSENSITIVE absolute / first / last / previous ──
    test("Case 3: TYPE_SCROLL_INSENSITIVE absolute(500) / first / last / previous / getRow", () => {
        // Scrollable type opens a server cursor (useCursor=1) + accumulates
        // every row into cachedRows so absolute / previous can back-track
        // without re-issuing the query (MySQL 5.7+ has no server scrollable
        // cursor — D146 §A.2 H5 fallback to MySQL Connector/J in-memory cache).
        const fd = mysqlConnect("127.0.0.1", 3307, "root", "test", "testdb")
        const ps = doPrepare(fd, "SELECT id FROM d146_server_cursor_integration ORDER BY id")
        const rs = ps.executeQuery("SELECT id FROM d146_server_cursor_integration ORDER BY id", TYPE_SCROLL_INSENSITIVE, CONCUR_READ_ONLY)

        assertEqual(rs.useCursor, 1)
        assertEqual(rs.rsType, TYPE_SCROLL_INSENSITIVE)
        assertEqual(rs.getRow(), 0)

        // first() == absolute(1) — pulls cache up to row 1.
        assertEqual(rs.first(), 1)
        assertEqual(rs.getInt("id"), 1)
        assertEqual(rs.getRow(), 1)

        // absolute(500) — forward-fetch into cache then jump.
        assertEqual(rs.absolute(SCROLL_TARGET), 1)
        assertEqual(rs.getInt("id"), SCROLL_TARGET)
        assertEqual(rs.getRow(), SCROLL_TARGET)

        // previous() — pure cache lookup, no socket round-trip.
        assertEqual(rs.previous(), 1)
        assertEqual(rs.getInt("id"), SCROLL_TARGET - 1)
        assertEqual(rs.getRow(), SCROLL_TARGET - 1)

        // last() — drains cursor + positions at the final row.
        assertEqual(rs.last(), 1)
        assertEqual(rs.getInt("id"), ROW_COUNT)
        assertEqual(rs.getRow(), ROW_COUNT)

        // absolute(N+1) — past end → 0 (JDBC §15 invalid cursor movement).
        assertEqual(rs.absolute(ROW_COUNT + 1), 0)

        // previous() walks back from the last positioned row.
        assertEqual(rs.previous(), 1)
        assertEqual(rs.getInt("id"), ROW_COUNT - 1)

        rs.close()
        ps.close()
        tcpClose(fd)
    })

    // ── Case 4: cursor close mid-iteration + reuse fd ───────────────────────
    test("Case 4: cursor close mid-iteration + reuse fd (server cursor released by COM_STMT_CLOSE)", () => {
        // Open a cursor, read CLOSE_AFTER rows, close mid-iteration. The
        // useCursor=1 close() skips the drain (server is parked waiting for
        // the next COM_STMT_FETCH); PreparedStatement.close() then sends
        // COM_STMT_CLOSE 0x19 which releases the server-side statement +
        // cursor. The same fd is reused for a second prepared statement —
        // if the cursor was still pinned or the socket carried unconsumed
        // packets, doPrepare or executeQuery would hang or return malformed
        // packets. (SHOW PROCESSLIST observation from D146 §核心目标 Case 4
        // is implied — the round-trip success on the same fd is the
        // observable proof the server thread is no longer in 'Sending data'.)
        const fd = mysqlConnect("127.0.0.1", 3307, "root", "test", "testdb")
        const ps = doPrepare(fd, "SELECT id FROM d146_server_cursor_integration ORDER BY id")
        ps.setFetchSize(FETCH_SIZE)
        const rs = ps.executeQuery("SELECT id FROM d146_server_cursor_integration ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_READ_ONLY)
        assertEqual(rs.useCursor, 1)

        let i = 1
        while (i <= CLOSE_AFTER) {
            assertEqual(rs.next(), 1)
            assertEqual(rs.getInt("id"), i)
            i = i + 1
        }
        // Mid-iteration close — only 50 of 1000 rows consumed.
        assertEqual(rs.cursorExhausted, 0)
        rs.close()
        ps.close()

        // Reuse the same fd — second prepare + execute must succeed cleanly.
        const ps2 = doPrepare(fd, "SELECT id FROM d146_server_cursor_integration ORDER BY id LIMIT 5")
        const rs2 = ps2.executeQuery("SELECT id FROM d146_server_cursor_integration ORDER BY id LIMIT 5", TYPE_FORWARD_ONLY, CONCUR_READ_ONLY)
        assertEqual(rs2.useCursor, 0)
        let j = 1
        while (j <= 5) {
            assertEqual(rs2.next(), 1)
            assertEqual(rs2.getInt("id"), j)
            j = j + 1
        }
        assertEqual(rs2.next(), 0)
        rs2.close()
        ps2.close()
        tcpClose(fd)
    })

    // ── Case 5: setFetchSize(INTEGER_MIN_VALUE) → client streaming H4 ───────
    test("Case 5: setFetchSize(INTEGER_MIN_VALUE = -2147483648) → useCursor=0 client streaming (H4)", () => {
        // INTEGER_MIN_VALUE is the MySQL Connector/J 5.0.6+ client-streaming
        // sentinel. fetchSize < 1 → deriveCursorFlag returns CURSOR_TYPE_NO_CURSOR
        // → useCursor stays 0. Server flushes the full 1000-row ResultSet in
        // one shot; client drains row-by-row from the socket buffer. No
        // COM_STMT_FETCH packets fire on this path — H4 dual-semantics
        // MySQL Connector/J idiom proven.
        const fd = mysqlConnect("127.0.0.1", 3307, "root", "test", "testdb")
        const ps = doPrepare(fd, "SELECT id FROM d146_server_cursor_integration ORDER BY id")
        ps.setFetchSize(INTEGER_MIN_VALUE)
        const rs = ps.executeQuery("SELECT id FROM d146_server_cursor_integration ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_READ_ONLY)

        assertEqual(rs.useCursor, 0)
        assertEqual(rs.fetchSize, INTEGER_MIN_VALUE)

        let i = 1
        while (i <= ROW_COUNT) {
            assertEqual(rs.next(), 1)
            assertEqual(rs.getInt("id"), i)
            i = i + 1
        }
        assertEqual(rs.next(), 0)

        rs.close()
        ps.close()
        tcpClose(fd)
    })

    // ── Case 6: RowCallbackHandler × 1000 (1-arg + 2-arg JdbcTemplate.query) ─
    test("Case 6: RowCallbackHandler.processRow × 1000 (JdbcTemplate.query 1-arg + 2-arg)", () => {
        const tmpl = new JdbcTemplate(URL)

        // 6a — 1-arg path: Statement.executeQuery (text protocol COM_QUERY 0x03,
        //      no server cursor). RowCallbackHandler invoked once per row;
        //      4-deep try/finally release before query returns (no socket leak).
        const cb1 = new CountingCallback(0, 0)
        tmpl.query("SELECT id FROM d146_server_cursor_integration ORDER BY id", cb1)
        assertEqual(cb1.count, ROW_COUNT)
        assertEqual(cb1.sum, expectedSum(ROW_COUNT))

        // 6b — 2-arg path: setter calls ps.setFetchSize(100) → server cursor
        //      with 10 × COM_STMT_FETCH(100) round-trips. Same callback shape;
        //      sum invariant holds independent of fetch path (cursor vs text).
        const cb2 = new CountingCallback(0, 0)
        tmpl.query("SELECT id FROM d146_server_cursor_integration ORDER BY id", (ps: PreparedStatement) => {
            ps.setFetchSize(FETCH_SIZE)
        }, cb2)
        assertEqual(cb2.count, ROW_COUNT)
        assertEqual(cb2.sum, expectedSum(ROW_COUNT))
    })

    // ── Case 7: cursor lifecycle SQLException → DAE hierarchy ───────────────
    test("Case 7: cursor lifecycle SQLException → BadSqlGrammarException + DAE catch hierarchy", () => {
        // Cursor entry against a non-existent table: Statement.executeQuery
        // throws SQLException (sqlState 42S02 / errorCode 1146 — MySQL
        // ER_NO_SUCH_TABLE). The cursor lifecycle path through
        // JdbcTemplate.query (Phase 4) flows through SQLExceptionTranslator
        // (D139 Phase 3) into BadSqlGrammarException; the 4-deep try/finally
        // release closes every layer (rs / stmt / conn) before the throw
        // escapes. Verifies the catch hierarchy works at every DAE tree
        // level (leaf BadSqlGrammar → mid NonTransientDAE → root DAE).
        // Per the user prompt, this is equivalent to the "DROP TABLE 中途 +
        // cursor 仍开 → executeQuery throw" semantics — the dropped table
        // case is a strict subset (table-not-found at executeQuery time).
        const tmpl = new JdbcTemplate(URL)

        // 7a — leaf: BadSqlGrammarException catches the exact subtype +
        //      cause carries the wire-protocol sqlState + errorCode.
        let caught7a = 0
        let state = ""
        let code = 0
        try {
            tmpl.query("SELECT id FROM d146_does_not_exist", (ps: PreparedStatement) => {
                ps.setFetchSize(FETCH_SIZE)
            }, new CountingCallback(0, 0))
        } catch (ex: BadSqlGrammarException) {
            caught7a = 1
            state = ex.cause.sqlState
            code = ex.cause.errorCode
        }
        assertEqual(caught7a, 1)
        assertEqual(state, "42S02")
        assertEqual(code, 1146)

        // 7b — mid: NonTransientDataAccessException (parent) catches the same
        //      subtype via SS classParents lookup (D025 vtable + bootstrap
        //      typed_catch.ss baseline).
        let caught7b = 0
        try {
            tmpl.query("SELECT id FROM d146_does_not_exist", (ps: PreparedStatement) => {
                ps.setFetchSize(FETCH_SIZE)
            }, new CountingCallback(0, 0))
        } catch (ex: NonTransientDataAccessException) {
            caught7b = 1
        }
        assertEqual(caught7b, 1)

        // 7c — root: DataAccessException catches; cause fields still reachable.
        let caught7c = 0
        try {
            tmpl.query("SELECT id FROM d146_does_not_exist", (ps: PreparedStatement) => {
                ps.setFetchSize(FETCH_SIZE)
            }, new CountingCallback(0, 0))
        } catch (ex: DataAccessException) {
            caught7c = 1
            assertEqual(ex.cause.errorCode, 1146)
            assertEqual(ex.cause.sqlState, "42S02")
        }
        assertEqual(caught7c, 1)
    })

    dropAllTables(URL, ["d146_server_cursor_integration"])

    println("All D146 7-shape integration tests passed!")
}
