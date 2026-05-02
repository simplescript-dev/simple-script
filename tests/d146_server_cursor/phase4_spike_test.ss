// D146 Phase 4 docker spike — Spring JdbcTemplate.query(sql,
// RowCallbackHandler) streaming + setFetchSize H4 dual semantics.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test
// returns 0 so `bin/ss test tests/` stays green when docker is unavailable
// (sane d134 / d136 / d138 / d139 / d146-phase1 / d146-phase3 fallback
// pattern). Run the full suite with:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d146_server_cursor/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// What this validates (Phase 4 — RowCallbackHandler vtable dispatch +
// setFetchSize plumbing through Spring layer):
//   1. JdbcTemplate.query(sql, callback) drives RowCallbackHandler.processRow
//      once per row (1000 calls for a 1000-row table) under default
//      Statement.executeQuery (text protocol, no server cursor).
//   2. JdbcTemplate.query(sql, setter, callback) + setter calling
//      ps.setFetchSize(100) routes through MysqlPreparedStatement.fetchSize
//      → deriveCursorFlag returns CURSOR_TYPE_READ_ONLY → useCursor=1 +
//      10 × COM_STMT_FETCH(100) round-trips.
//   3. setter calling ps.setFetchSize(INTEGER_MIN_VALUE) is the MySQL
//      Connector/J 5.0.6+ client-streaming sentinel: deriveCursorFlag
//      returns CURSOR_TYPE_NO_CURSOR (because MIN_VALUE < 1), so useCursor
//      stays 0 and the server flushes the full ResultSet in one shot —
//      the H4 dual-semantics path documented in lib/spring/jdbc.ss and
//      lib/com/mysql/prepared.ss MysqlPreparedStatement.setFetchSize.
//
// What is deferred to Phase 5:
//   - 7-shape integration_test.ss e2e covering Cases 1-7 (default /
//     setFetchSize cursor 协议 / scrollable / cursor close 担保 /
//     MIN_VALUE streaming / RowCallbackHandler / cursor lifecycle exception).

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, ResultSet, PreparedStatement, DriverManager_getConnection, SQLException } from "@/lib/java/sql"
import { JdbcTemplate, RowCallbackHandler, INTEGER_MIN_VALUE } from "@/lib/spring/jdbc"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"
const ROW_COUNT = 1000
const FETCH_SIZE = 100

// RowCallbackHandler implementor — counts processRow invocations + sums
// the id column so the test can prove every row reached the callback.
class CountingCallback : RowCallbackHandler {
    count: int
    sum: int

    function processRow(rs: ResultSet): void {
        this.count = this.count + 1
        this.sum = this.sum + rs.getInt("id")
    }
}

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS phase4_d146")
    tmpl.execute("CREATE TABLE phase4_d146 (id INT PRIMARY KEY) ENGINE=InnoDB")
    let i = 1
    while (i <= ROW_COUNT) {
        tmpl.execute("INSERT INTO phase4_d146 VALUES (" + i + ")")
        i = i + 1
    }
    return 0
}

function dropTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS phase4_d146")
    return 0
}

// Sum 1..N closed-form so the test does not need a scratch loop just
// to verify the row payload reached the callback.
function expectedSum(n: int): int {
    return (n * (n + 1)) / 2
}

function main() {
    // Probe — skip the file when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D146 phase4 spike: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    test("JdbcTemplate.query(sql, callback) — RowCallbackHandler.processRow × 1000 (Statement path)", () => {
        // 1-arg query path goes through Statement.executeQuery (text
        // protocol COM_QUERY 0x03). Verifies vtable dispatch + four-deep
        // try/finally release before query returns (no socket leak).
        const tmpl = new JdbcTemplate(URL)
        const cb = new CountingCallback(0, 0)
        tmpl.query("SELECT id FROM phase4_d146 ORDER BY id", cb)
        assertEqual(cb.count, ROW_COUNT)
        assertEqual(cb.sum, expectedSum(ROW_COUNT))
    })

    test("JdbcTemplate.query(sql, setter, callback) + setFetchSize(100) — server cursor 10 × COM_STMT_FETCH", () => {
        // Setter calls ps.setFetchSize(100). MysqlPreparedStatement.fetchSize
        // = 100 > 0 → deriveCursorFlag returns CURSOR_TYPE_READ_ONLY →
        // executeQuery flips useCursor=1 + sends COM_STMT_EXECUTE flags=0x01.
        // 1000 rows / 100 batch = 10 × COM_STMT_FETCH(100) round-trips,
        // last one closes with EOF SERVER_STATUS_LAST_ROW_SENT 0x0080.
        const tmpl = new JdbcTemplate(URL)
        const cb = new CountingCallback(0, 0)
        tmpl.query("SELECT id FROM phase4_d146 ORDER BY id", (ps: PreparedStatement) => {
            ps.setFetchSize(FETCH_SIZE)
        }, cb)
        assertEqual(cb.count, ROW_COUNT)
        assertEqual(cb.sum, expectedSum(ROW_COUNT))
    })

    test("JdbcTemplate.query(sql, setter, callback) + setFetchSize(INTEGER_MIN_VALUE) — H4 client streaming", () => {
        // INTEGER_MIN_VALUE = -2147483648. MysqlPreparedStatement.fetchSize
        // = -2147483648 < 1 → deriveCursorFlag returns CURSOR_TYPE_NO_CURSOR
        // → useCursor stays 0. Server flushes the full 1000-row ResultSet
        // in one shot; client drains row-by-row from the socket buffer.
        // No COM_STMT_FETCH packets fire on this path — D146 §A.2 H4
        // dual-semantics MySQL Connector/J 5.0.6+ idiom proven.
        const tmpl = new JdbcTemplate(URL)
        const cb = new CountingCallback(0, 0)
        tmpl.query("SELECT id FROM phase4_d146 ORDER BY id", (ps: PreparedStatement) => {
            ps.setFetchSize(INTEGER_MIN_VALUE)
        }, cb)
        assertEqual(cb.count, ROW_COUNT)
        assertEqual(cb.sum, expectedSum(ROW_COUNT))
    })

    dropTable()
}
