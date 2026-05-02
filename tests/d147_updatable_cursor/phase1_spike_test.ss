// D147 Phase 1 docker spike — Updatable cursor protocol round-trip.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test
// returns 0 so `bin/ss test tests/` stays green when docker is unavailable
// (sane d134 / d136 / d138 / d139 / d146 fallback pattern). To run the full
// suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d147_updatable_cursor/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Wire flow exercised (5-row table, single fetch drains it):
//   1. JdbcTemplate setup    — DROP / CREATE / 5× INSERT (high-level path)
//   2. mysqlConnect          — raw fd for cursor protocol manipulation
//   3. COM_STMT_PREPARE      — "SELECT id, val FROM phase1_d147 ORDER BY id"
//   4. COM_STMT_EXECUTE      — flags = CURSOR_TYPE_FOR_UPDATE 0x02
//                              (custom 10-byte 0-param payload — same shape
//                               as the D146 phase1_spike helper but with the
//                               FOR_UPDATE flag; high-level path lives at
//                               MysqlPreparedStatement.executeQuery + Phase 4
//                               driver-side updatable simulation)
//      Server response       — col count + 2 col defs + EOF
//                              (D147 §A.2 H1: server treats 0x02 same as
//                              0x01 — EOF carries CURSOR_EXISTS, no ERR
//                              packet 1064 / unsupported flag rejection)
//   5. COM_STMT_FETCH(5)     — drains the 5 rows + EOF (LAST_ROW_SENT)
//   6. COM_STMT_CLOSE        — release the prepared statement
//   7. tcpClose              — release the connection
//
// What this validates (D147 §A.2 H1 hidden assumption):
//   H1  CURSOR_TYPE_FOR_UPDATE 0x02 in COM_STMT_EXECUTE flags is accepted
//       by the server (no ERR packet) and triggers cursor behavior
//       identical to 0x01. Server-side updatable cursor is a no-op per
//       MySQL 5.7+ docs; driver-side simulation lives in
//       MysqlBinaryResultSet (Phase 4 — pendingUpdates / pendingInserts /
//       tableName / pkColumn / inInsertMode / rowState 6 fields).
//
// What is deferred to Phase 2-5:
//   - JDBC ResultSet update*/state 18 method on `interface ResultSet`
//   - MysqlBinaryResultSet 6 fields + driver-side updatable simulation
//   - SQL template generators (UPDATE / DELETE / INSERT / SELECT WHERE pk)
//   - 7-case integration test (CONCUR_UPDATABLE + updateRow / deleteRow /
//     insertRow / cancelRowUpdates + refreshRow / cursor lifecycle SQLException)

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, DriverManager_getConnection, SQLException } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"
import { mysqlConnect } from "@/lib/com/mysql/handshake"
import { readPacket, MysqlPacket } from "@/lib/com/mysql/wire"
import { COM_STMT_EXECUTE, sendComStmtPrepare, readPrepareOk, sendComStmtClose, readColumnDefList, writeByteToFd, writeIntLEToFd } from "@/lib/com/mysql/prepared"
import { COM_STMT_FETCH, CURSOR_TYPE_FOR_UPDATE, SERVER_STATUS_CURSOR_EXISTS, SERVER_STATUS_LAST_ROW_SENT, isEofPacket, eofStatusFlags, writeStmtFetchPacket } from "@/lib/com/mysql/query"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS phase1_d147")
    tmpl.execute("CREATE TABLE phase1_d147 (id INT PRIMARY KEY, val INT) ENGINE=InnoDB")
    let i = 1
    while (i <= 5) {
        const sql = "INSERT INTO phase1_d147 VALUES (" + i + ", " + (i * 10) + ")"
        tmpl.execute(sql)
        i = i + 1
    }
    return 0
}

function dropTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS phase1_d147")
    return 0
}

// Sends a custom COM_STMT_EXECUTE for a 0-param prepared statement with
// CURSOR_TYPE_FOR_UPDATE (0x02) in the flags byte. Returns total bytes
// written (4 header + 10 payload = 14). Same shape as the D146 phase1_spike
// helper sendCursorExecuteZeroParam, with the flag swapped to 0x02. For
// non-zero params the high-level MysqlPreparedStatement.executeQuery is
// the SSoT (deriveCursorFlag picks the flag from concurrency + rsType +
// fetchSize); Phase 4 wires that path end-to-end.
function sendCursorExecuteForUpdate(fd: int, statementId: int): int {
    writeIntLEToFd(fd, 10, 3)
    writeByteToFd(fd, 0)
    writeByteToFd(fd, COM_STMT_EXECUTE)
    writeIntLEToFd(fd, statementId, 4)
    writeByteToFd(fd, CURSOR_TYPE_FOR_UPDATE)
    writeIntLEToFd(fd, 1, 4)
    return 4 + 10
}

class FetchResult {
    rowCount: int
    statusFlags: int
}

// Drains the COM_STMT_EXECUTE response — column count packet + N column
// defs + EOF (with CURSOR_EXISTS when the server holds a cursor). Returns
// the EOF status_flags so the caller can assert CURSOR_EXISTS / LAST_ROW_SENT.
function drainExecuteResponse(fd: int, numColumns: int): int {
    readPacket(fd)
    let i = 0
    while (i < numColumns) {
        readPacket(fd)
        i = i + 1
    }
    const eof = readPacket(fd)
    return eofStatusFlags(eof.payload, eof.payloadLen)
}

// Drains a COM_STMT_FETCH response — N binary row packets followed by an
// EOF whose status_flags says whether more rows remain. Stops on the first
// EOF packet; some MySQL versions may send fewer rows than requested when
// the cursor is about to exhaust.
function drainFetchResponse(fd: int): FetchResult {
    let count = 0
    let statusFlags = 0
    while (1 == 1) {
        const pkt = readPacket(fd)
        if (pkt.payloadLen <= 0) {
            break
        }
        if (isEofPacket(pkt.payload, pkt.payloadLen) == 1) {
            statusFlags = eofStatusFlags(pkt.payload, pkt.payloadLen)
            break
        }
        count = count + 1
    }
    return new FetchResult(count, statusFlags)
}

function main() {
    // Probe — skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D147 phase1 spike: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    test("Updatable cursor server round-trip — EXECUTE flags=0x02 + FETCH(5) + LAST_ROW_SENT", () => {
        const fd = mysqlConnect("127.0.0.1", 3307, "root", "test", "testdb")

        // 1. PREPARE the SELECT (2 columns, 0 params).
        sendComStmtPrepare(fd, "SELECT id, val FROM phase1_d147 ORDER BY id")
        const ok = readPrepareOk(fd)
        assertTrue(ok.statementId > 0)
        assertEqual(ok.numColumns, 2)
        assertEqual(ok.numParams, 0)

        // Drain the prepare response: 0 param defs (server omits for 0
        // params) + 2 col defs + 1 EOF.
        readColumnDefList(fd, ok.numColumns)

        // 2. EXECUTE with CURSOR_TYPE_FOR_UPDATE 0x02 — server should reply
        //    with column metadata + EOF carrying CURSOR_EXISTS, no rows
        //    yet. D147 §A.2 H1 实证: server treats 0x02 identically to
        //    0x01, no ERR packet 1064 (syntax error / unsupported flag) —
        //    driver-side updatable cursor is a free pass at the protocol
        //    level, the actual UPDATE / DELETE / INSERT lives in
        //    MysqlBinaryResultSet.updateRow / deleteRow / insertRow via
        //    fresh PreparedStatement (Phase 4).
        sendCursorExecuteForUpdate(fd, ok.statementId)
        const executeFlags = drainExecuteResponse(fd, ok.numColumns)
        // CURSOR_EXISTS bit set, LAST_ROW_SENT not yet — exactly the same
        // post-EXECUTE state as CURSOR_TYPE_READ_ONLY 0x01 (D146 phase1_spike
        // sees the same flags). H1 实证 — server behavior 0x02 ≡ 0x01.
        assertTrue((executeFlags & SERVER_STATUS_CURSOR_EXISTS) != 0)
        assertEqual(executeFlags & SERVER_STATUS_LAST_ROW_SENT, 0)

        // 3. Single FETCH(5) — drains the 5-row cursor in one batch; EOF
        //    carries LAST_ROW_SENT, server frees its row buffer.
        writeStmtFetchPacket(fd, ok.statementId, 5)
        const r = drainFetchResponse(fd)
        assertEqual(r.rowCount, 5)
        assertTrue((r.statusFlags & SERVER_STATUS_LAST_ROW_SENT) != 0)
        assertEqual(r.statusFlags & SERVER_STATUS_CURSOR_EXISTS, 0)

        // 4. CLOSE the statement so the server reclaims it.
        sendComStmtClose(fd, ok.statementId)
        tcpClose(fd)
    })

    dropTable()
}
