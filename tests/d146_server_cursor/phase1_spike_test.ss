// D146 Phase 1 docker spike — server-side cursor protocol round-trip.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test
// returns 0 so `bin/ss test tests/` stays green when docker is unavailable
// (sane d134 / d136 / d138 / d139 fallback pattern). To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d146_server_cursor/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Wire flow exercised (10-row table, fetchSize 5, two fetches drain it):
//   1. JdbcTemplate setup    — DROP / CREATE / 10× INSERT (high-level path)
//   2. mysqlConnect          — raw fd for cursor protocol manipulation
//   3. COM_STMT_PREPARE      — "SELECT id FROM phase1_d146" (1 col, 0 params)
//   4. COM_STMT_EXECUTE      — flags = CURSOR_TYPE_READ_ONLY 0x01
//                              (custom 10-byte payload — no new_params_bound_flag
//                               for 0-param queries per MySQL spec; the project's
//                               sendComStmtExecute is param-bearing only and
//                               hardcodes CURSOR_TYPE_NO_CURSOR — Phase 3 wires
//                               cursor flag through the high-level path)
//      Server response       — col count + col def + EOF (with CURSOR_EXISTS;
//                               no rows yet — server holds the cursor)
//   5. COM_STMT_FETCH(5)     — writeStmtFetchPacket(fd, stmtId, 5)
//      Server response       — 5 binary rows + EOF (with CURSOR_EXISTS;
//                               5 more rows pending)
//   6. COM_STMT_FETCH(5)     — drains the cursor
//      Server response       — 5 binary rows + EOF (with LAST_ROW_SENT;
//                               cursor exhausted, server-side row buffer freed)
//   7. COM_STMT_CLOSE        — release the prepared statement
//   8. tcpClose              — release the connection
//
// What this validates (D146 §A.2 hidden assumption fanout):
//   H1  COM_STMT_FETCH packet encoding (0x1c + stmt_id u32 LE + num_rows u32 LE)
//   H2  CURSOR_TYPE_READ_ONLY 0x01 in COM_STMT_EXECUTE flags byte
//   H3  EOF status_flags i16 LE at offset 3 — both CURSOR_EXISTS / LAST_ROW_SENT
//
// What is deferred to Phase 3:
//   - Wiring useCursor / fetchSize / cursorExhausted / statementId fields onto
//     MysqlBinaryResultSet so MysqlPreparedStatement.executeQuery can drive
//     server cursors directly.
//   - Scrollable absolute / first / last / previous in-memory cache (D146 §A.2 H5
//     MySQL has no server scrollable cursor — fallback to MySQL Connector/J
//     in-memory cache idiom).

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, DriverManager_getConnection, SQLException } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"
import { mysqlConnect } from "@/lib/com/mysql/handshake"
import { readPacket, MysqlPacket } from "@/lib/com/mysql/wire"
import { COM_STMT_EXECUTE, sendComStmtPrepare, readPrepareOk, sendComStmtClose, readColumnDefList, writeByteToFd, writeIntLEToFd } from "@/lib/com/mysql/prepared"
import { COM_STMT_FETCH, CURSOR_TYPE_READ_ONLY, SERVER_STATUS_CURSOR_EXISTS, SERVER_STATUS_LAST_ROW_SENT, sendQuery, readUpdateResultPacket, isEofPacket, eofStatusFlags, writeStmtFetchPacket } from "@/lib/com/mysql/query"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS phase1_d146")
    tmpl.execute("CREATE TABLE phase1_d146 (id INT PRIMARY KEY, name VARCHAR(100)) ENGINE=InnoDB")
    let i = 1
    while (i <= 10) {
        const sql = "INSERT INTO phase1_d146 VALUES (" + i + ", 'name" + i + "')"
        tmpl.execute(sql)
        i = i + 1
    }
    return 0
}

function dropTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS phase1_d146")
    return 0
}

// Sends a custom COM_STMT_EXECUTE for a 0-param prepared statement with
// CURSOR_TYPE_READ_ONLY (0x01) in the flags byte. Returns total bytes written
// (4 header + 10 payload = 14).
//
// Layout per MySQL Native Protocol §6.5 (num_params = 0 short form):
//   3 byte LE   payload_length = 10
//   1 byte      seqId = 0
//   1 byte      0x17 COM_STMT_EXECUTE
//   4 byte LE   statement_id
//   1 byte      flags = 0x01 (CURSOR_TYPE_READ_ONLY)
//   4 byte LE   iteration_count = 1
//
// new_params_bound_flag / param_types / NULL bitmap / param values are all
// omitted because num_params = 0 (MySQL spec). For non-zero params, the
// project-provided sendComStmtExecute in lib/com/mysql/prepared.ss is the
// single source of truth — but it hardcodes CURSOR_TYPE_NO_CURSOR. Phase 3
// will plumb the cursor flag through the high-level path.
function sendCursorExecuteZeroParam(fd: int, statementId: int): int {
    writeIntLEToFd(fd, 10, 3)
    writeByteToFd(fd, 0)
    writeByteToFd(fd, COM_STMT_EXECUTE)
    writeIntLEToFd(fd, statementId, 4)
    writeByteToFd(fd, CURSOR_TYPE_READ_ONLY)
    writeIntLEToFd(fd, 1, 4)
    return 4 + 10
}

// Two-field carrier for drainFetchResponse — SS classes are the project's
// idiomatic multi-return shape (compare MysqlPacket / OkPacket / ErrorPacket
// in lib/com/mysql/query.ss). Avoids Array<int> out-param tricks.
class FetchResult {
    rowCount: int
    statusFlags: int
}

// Drains the server's COM_STMT_EXECUTE-with-cursor response. Reads exactly
// numColumns col-def packets bracketed by a leading column-count packet
// and a trailing EOF packet. Returns the EOF's status_flags so the caller
// can assert CURSOR_EXISTS.
//
// Wire format (legacy EOF, 1 column, server holds cursor):
//   pkt 1 — column count (lenenc int = 1)
//   pkt 2 — column def for "id"
//   pkt 3 — EOF (with CURSOR_EXISTS in status_flags)
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
        println("D146 phase1 spike: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    test("server cursor full lifecycle — EXECUTE flags=0x01 + 2× FETCH(5) + LAST_ROW_SENT", () => {
        // Open a raw connection so we can manipulate the EXECUTE flags byte
        // directly (the high-level MysqlPreparedStatement defaults to
        // CURSOR_TYPE_NO_CURSOR — Phase 3 plumbs the cursor flag through).
        const fd = mysqlConnect("127.0.0.1", 3307, "root", "test", "testdb")

        // 1. PREPARE the SELECT (1 column "id", 0 params).
        sendComStmtPrepare(fd, "SELECT id FROM phase1_d146 ORDER BY id")
        const ok = readPrepareOk(fd)
        assertTrue(ok.statementId > 0)
        assertEqual(ok.numColumns, 1)
        assertEqual(ok.numParams, 0)

        // Drain the prepare response: 0 param defs + 0 EOF (server omits
        // for 0 params), 1 col def + 1 EOF.
        readColumnDefList(fd, ok.numColumns)

        // 2. EXECUTE with CURSOR_TYPE_READ_ONLY — server should reply with
        //    column metadata + EOF (CURSOR_EXISTS), no rows.
        sendCursorExecuteZeroParam(fd, ok.statementId)
        const executeFlags = drainExecuteResponse(fd, ok.numColumns)
        // Server still holds the cursor — CURSOR_EXISTS bit is set, the
        // LAST_ROW_SENT bit is not yet.
        assertTrue((executeFlags & SERVER_STATUS_CURSOR_EXISTS) != 0)
        assertEqual(executeFlags & SERVER_STATUS_LAST_ROW_SENT, 0)

        // 3. First FETCH(5) — server sends 5 rows + EOF (CURSOR_EXISTS,
        //    5 more pending).
        writeStmtFetchPacket(fd, ok.statementId, 5)
        const r1 = drainFetchResponse(fd)
        assertEqual(r1.rowCount, 5)
        assertTrue((r1.statusFlags & SERVER_STATUS_CURSOR_EXISTS) != 0)
        assertEqual(r1.statusFlags & SERVER_STATUS_LAST_ROW_SENT, 0)

        // 4. Second FETCH(5) — drains the cursor; EOF carries
        //    LAST_ROW_SENT, server frees its row buffer.
        writeStmtFetchPacket(fd, ok.statementId, 5)
        const r2 = drainFetchResponse(fd)
        assertEqual(r2.rowCount, 5)
        assertTrue((r2.statusFlags & SERVER_STATUS_LAST_ROW_SENT) != 0)
        assertEqual(r2.statusFlags & SERVER_STATUS_CURSOR_EXISTS, 0)

        // 5. CLOSE the statement so the server reclaims it.
        sendComStmtClose(fd, ok.statementId)
        tcpClose(fd)
    })

    dropTable()
}
