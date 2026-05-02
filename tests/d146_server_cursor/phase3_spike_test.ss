// D146 Phase 3 docker spike — high-level cursor protocol + in-memory
// scrollable cache through MysqlBinaryResultSet (the upgrade Phase 1
// covered at the protocol-byte layer is now driven through the JDBC
// surface).
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test
// returns 0 so `bin/ss test tests/` stays green when docker is unavailable
// (sane d134 / d136 / d138 / d139 / d146-phase1 fallback pattern). Run the
// full suite with:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d146_server_cursor/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// What this validates (Phase 3 wire flow over high-level JDBC):
//   1. setFetchSize(10) + executeQuery(sql, TYPE_FORWARD_ONLY, CONCUR_READ_ONLY)
//      drives 100-row table via 10 × COM_STMT_FETCH(10) + LAST_ROW_SENT EOF
//      — the server holds the cursor and only releases its row buffer on the
//      final fetch. cursorExhausted flips to 1; the 101st next() returns 0.
//   2. TYPE_SCROLL_INSENSITIVE opens a server cursor + accumulates rows in the
//      in-memory cache so absolute(50) / previous() / first() / last() can
//      back-track without a re-fetch (MySQL 5.7+ has no server scrollable
//      cursor — D146 §A.2 H5 fallback to MySQL Connector/J idiom).
//   3. Client streaming default (no setFetchSize, TYPE_FORWARD_ONLY) keeps
//      useCursor=0 and drains rows via the legacy socket buffer path —
//      backwards-compatible with the pre-Phase-3 baseline.
//
// What is deferred to Phase 4:
//   - Spring JdbcTemplate.query(sql, RowCallbackHandler) flow + setFetchSize
//     dual semantics (Integer.MIN_VALUE = -2147483648 client-side row streaming
//     vs server-side cursor N rows).
//
// What is deferred to Phase 5:
//   - 7-shape integration_test.ss (Case 1 default / Case 2 cursor 10-fetch /
//     Case 3 scrollable / Case 4 close-mid-cursor / Case 5 MIN_VALUE streaming /
//     Case 6 RowCallbackHandler / Case 7 cursor lifecycle SQLException).

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, DriverManager_getConnection, SQLException, TYPE_FORWARD_ONLY, TYPE_SCROLL_INSENSITIVE, TYPE_SCROLL_SENSITIVE, CONCUR_READ_ONLY } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"
import { mysqlConnect } from "@/lib/com/mysql/handshake"
import { doPrepare, MysqlPreparedStatement, MysqlBinaryResultSet } from "@/lib/com/mysql/prepared"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"
const ROW_COUNT = 100
const FETCH_SIZE = 10

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS phase3_d146")
    tmpl.execute("CREATE TABLE phase3_d146 (id INT PRIMARY KEY) ENGINE=InnoDB")
    let i = 1
    while (i <= ROW_COUNT) {
        tmpl.execute("INSERT INTO phase3_d146 VALUES (" + i + ")")
        i = i + 1
    }
    return 0
}

function dropTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS phase3_d146")
    return 0
}

function main() {
    // Probe — skip the file when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D146 phase3 spike: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    test("forward-only server cursor — setFetchSize(10) + 100 rows + 10 × COM_STMT_FETCH + LAST_ROW_SENT", () => {
        // High-level JDBC path: prepareStatement → setFetchSize → executeQuery(
        // sql, TYPE_FORWARD_ONLY, CONCUR_READ_ONLY). Cursor flag = 0x01 because
        // fetchSize > 0; useCursor flips to 1, fetchSize plumbs into rs so
        // each fetchNextBatch sends COM_STMT_FETCH(stmtId, 10).
        const fd = mysqlConnect("127.0.0.1", 3307, "root", "test", "testdb")
        const ps = doPrepare(fd, "SELECT id FROM phase3_d146 ORDER BY id")
        ps.setFetchSize(FETCH_SIZE)
        const rs = ps.executeQuery("SELECT id FROM phase3_d146 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_READ_ONLY)

        // rs is MysqlBinaryResultSet — verify cursor state plumbed.
        assertEqual(rs.useCursor, 1)
        assertEqual(rs.fetchSize, FETCH_SIZE)
        assertTrue(rs.statementId > 0)
        assertEqual(rs.cursorExhausted, 0)
        assertEqual(rs.rsType, TYPE_FORWARD_ONLY)

        // Drive 100 next() calls; each row must carry the expected id.
        // The 11th, 21st ... 91st next() each trigger an internal COM_STMT_FETCH
        // (10 rows consumed → cache empty → fetchNextBatch). The 101st returns 0
        // and lights cursorExhausted.
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

    test("scrollable in-memory cache — TYPE_SCROLL_INSENSITIVE absolute / first / last / previous", () => {
        // Scrollable cursor opens server cursor (COM_STMT_EXECUTE flags = 0x01)
        // + accumulates every row into cachedRows so absolute(50) / previous()
        // can back-track without re-issuing the query. Default fetchSize falls
        // back to DEFAULT_CURSOR_FETCH_SIZE inside fetchNextBatch — for a 100-row
        // table that drains in a single COM_STMT_FETCH(100).
        const fd = mysqlConnect("127.0.0.1", 3307, "root", "test", "testdb")
        const ps = doPrepare(fd, "SELECT id FROM phase3_d146 ORDER BY id")
        const rs = ps.executeQuery("SELECT id FROM phase3_d146 ORDER BY id", TYPE_SCROLL_INSENSITIVE, CONCUR_READ_ONLY)

        assertEqual(rs.useCursor, 1)
        assertEqual(rs.rsType, TYPE_SCROLL_INSENSITIVE)
        assertEqual(rs.getRow(), 0)  // not positioned

        // first() via absolute(1) — pulls the cache up to row 1.
        assertEqual(rs.first(), 1)
        assertEqual(rs.getInt("id"), 1)
        assertEqual(rs.getRow(), 1)

        // absolute(50) — forward-fetch into cache (or hit cache if already
        // pulled) then jump.
        assertEqual(rs.absolute(50), 1)
        assertEqual(rs.getInt("id"), 50)
        assertEqual(rs.getRow(), 50)

        // previous() — strictly cache lookup, no socket round-trip.
        assertEqual(rs.previous(), 1)
        assertEqual(rs.getInt("id"), 49)
        assertEqual(rs.getRow(), 49)

        // last() — drains cursor + positions at row 100.
        assertEqual(rs.last(), 1)
        assertEqual(rs.getInt("id"), ROW_COUNT)
        assertEqual(rs.getRow(), ROW_COUNT)

        // absolute(101) → past end → 0.
        assertEqual(rs.absolute(ROW_COUNT + 1), 0)

        // previous() walks back from row 100.
        assertEqual(rs.previous(), 1)
        assertEqual(rs.getInt("id"), ROW_COUNT - 1)

        rs.close()
        ps.close()
        tcpClose(fd)
    })

    test("client streaming default — no setFetchSize, useCursor=0", () => {
        // No setFetchSize + TYPE_FORWARD_ONLY + CONCUR_READ_ONLY → cursor flag
        // stays 0x00, server pre-buffers + flushes the entire result set; the
        // legacy MysqlBinaryResultSet streaming path drains row-by-row. This
        // case proves backwards compatibility with pre-Phase-3 callers that
        // never touch setFetchSize / type / concurrency.
        const fd = mysqlConnect("127.0.0.1", 3307, "root", "test", "testdb")
        const ps = doPrepare(fd, "SELECT id FROM phase3_d146 ORDER BY id")
        const rs = ps.executeQuery("SELECT id FROM phase3_d146 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_READ_ONLY)

        assertEqual(rs.useCursor, 0)
        assertEqual(rs.fetchSize, 0)

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

    dropTable()
}
