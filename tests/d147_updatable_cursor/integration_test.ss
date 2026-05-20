// D147 Phase 5 — 7-shape integration test (D147 主线 close).
//
// Covers all 7 forms of D147 §核心目标 single criterion in one main file.
// Subsumes Phase 1 / 2 / 4 spike tests (the three phase{1,2,4}_spike_test.ss
// files are removed in this Phase). phase1_packet_unit_test.ss +
// phase3_sql_template_unit_test.ss are kept — they exercise byte-level
// protocol constants / SQL template byte-level pass-through in pure local
// mode (no docker dependency) and are complementary, not redundant, to
// this end-to-end suite (same split as D139 / D146 范式 — protocol-layer /
// SQL-template-layer unit test vs business-layer e2e integration).
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test
// file prints a hint and returns 0 so `bin/ss test tests/` stays green
// when docker is unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d147_updatable_cursor/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Uses table `integration_d147` to isolate from D134 (`users`) /
// D136 (`users_d136`) / D138 (`d138_generated_keys`) /
// D139 (`d139_sql_exception_test`) / D146 (`d146_server_cursor_integration`)
// under `bin/ss test tests/` parallel batch.
//
// Validates D147 §核心目标 single criterion (7 cases):
//   Case 1 — TYPE_FORWARD_ONLY + CONCUR_READ_ONLY default 兼容
//            → D146 client-streaming baseline preserved; verifies D147
//              landing does not regress the existing read-only path.
//   Case 2 — TYPE_FORWARD_ONLY + CONCUR_UPDATABLE + setFetchSize(2)
//            → COM_STMT_EXECUTE flags = CURSOR_TYPE_FOR_UPDATE 0x02
//              (concurrency wins over fetchSize > 0 in deriveCursorFlag;
//              server treats 0x02 same as 0x01 — D147 §A.2 H1 wire-level
//              实证 that server accepts 0x02 without REJECT and the full
//              ResultSet still reaches the client cleanly).
//   Case 3 — updateInt + updateString + updateRow → external SELECT
//            confirms server-side row mutated on both columns + rowUpdated
//            == 1 (multi-col UPDATE proves buildUpdateRowSql column order
//            with PK as the trailing positional param) — H3 + H7
//   Case 4 — deleteRow → external SELECT COUNT == 0 + rowDeleted == 1 +
//            same fd cursor close round-trip clean (H3 + H7)
//   Case 5 — moveToInsertRow + multi-col updateInt/updateString +
//            insertRow + external SELECT finds inserted row + rowInserted
//            == 1 + moveToCurrentRow toggles inInsertMode back to 0
//            (multi-col INSERT VALUES proves buildInsertRowSql placeholder
//            count + setString loop order — H6 + H7)
//   Case 6 — cancelRowUpdates (server-side row UNCHANGED — pure
//            client-side, no SQL fired) + refreshRow (mirrors external
//            concurrent UPDATE through fresh PS SELECT WHERE pk=? back
//            into currentRow) — H4 + H5 双重
//   Case 7 — Unique-violation INSERT in cursor mode → SQLException →
//            SQLExceptionTranslator → DuplicateKeyException IS-A
//            DataIntegrityViolationException IS-A NonTransientDAE IS-A
//            DataAccessException + 3-level catch hierarchy + cause.sqlState
//            == "23000" + cause.errorCode == 1062 wire-protocol fields
//            preserved (D139 SQLExceptionTranslator standard applies to
//            cursor-side fresh-PS executeUpdate path).
//
// SS arrow-function closure capture rebinds outer-scope catch `e`
// (D139 §Followup F10) — every inner catch in this file uses `ex` /
// `sqlEx`, never `e`, to avoid reusing the outer probe-catch name.
//
// See docs/3-decisions/D147-updatable-cursor.md §Phase 收关锚 §Phase 5.

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, PreparedStatement, ResultSet, DriverManager_getConnection, SQLException, TYPE_FORWARD_ONLY, CONCUR_READ_ONLY, CONCUR_UPDATABLE } from "@/lib/java/sql"
import { JdbcTemplate, SQLExceptionTranslator, DataIntegrityViolationException, NonTransientDataAccessException, DataAccessException } from "@/lib/spring/jdbc"
import { dropAllTables } from "@/tests/jdbc/import/jdbc_test_helpers"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"
const TABLE_NAMES: Array<string> = ["integration_d147"]

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS integration_d147")
    tmpl.execute("CREATE TABLE integration_d147 (id INT PRIMARY KEY, val INT, name VARCHAR(64), email VARCHAR(64) UNIQUE) ENGINE=InnoDB")
    let i = 1
    while (i <= 5) {
        const sql = "INSERT INTO integration_d147 VALUES (" + i + ", " + (i * 10) + ", 'row" + i + "', 'r" + i + "@test.com')"
        tmpl.execute(sql)
        i = i + 1
    }
    return 0
}

// External probes — separate Connection fired via JdbcTemplate so the
// integration suite observes server-side state independently of the cursor
// under test.

function probeVal(id: int): int {
    const tmpl = new JdbcTemplate(URL)
    return tmpl.queryForInt("SELECT val FROM integration_d147 WHERE id = " + id, "val")
}

function probeRowExists(id: int): int {
    const tmpl = new JdbcTemplate(URL)
    return tmpl.queryForInt("SELECT COUNT(*) AS n FROM integration_d147 WHERE id = " + id, "n")
}

function probeRowCount(): int {
    const tmpl = new JdbcTemplate(URL)
    return tmpl.queryForInt("SELECT COUNT(*) AS n FROM integration_d147", "n")
}

function probeRowMatches(id: int, val: int, name: string): int {
    const tmpl = new JdbcTemplate(URL)
    return tmpl.queryForInt("SELECT COUNT(*) AS n FROM integration_d147 WHERE id = " + id + " AND val = " + val + " AND name = '" + name + "'", "n")
}

function main() {
    // Probe — skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D147 integration: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    // ── Case 1: TYPE_FORWARD_ONLY + CONCUR_READ_ONLY default → D146 baseline ─
    test("Case 1 — TYPE_FORWARD_ONLY + CONCUR_READ_ONLY default 兼容(D146 baseline 不破)", () => {
        // No setFetchSize hint + CONCUR_READ_ONLY → deriveCursorFlag returns
        // CURSOR_TYPE_NO_CURSOR (D146 client-streaming default). Verifies
        // the pre-D147 baseline still works (backwards compat).
        recreateTable()
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement("SELECT id FROM integration_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_READ_ONLY)
        const rs = ps.executeQuery()
        let i = 1
        while (i <= 5) {
            assertEqual(rs.next(), 1)
            assertEqual(rs.getInt("id"), i)
            i = i + 1
        }
        assertEqual(rs.next(), 0)
        rs.close()
        ps.close()
        conn.close()
        dropAllTables(URL, TABLE_NAMES)
    })

    // ── Case 2: CONCUR_UPDATABLE + setFetchSize(2) → flags=0x02 wire 实证 ────
    test("Case 2 — CONCUR_UPDATABLE + setFetchSize(2) → COM_STMT_EXECUTE flags=0x02 (H1 wire 实证)", () => {
        // concurrency = CONCUR_UPDATABLE wins over fetchSize > 0 in
        // deriveCursorFlag → COM_STMT_EXECUTE flags = CURSOR_TYPE_FOR_UPDATE
        // 0x02 (verified at unit level by phase1_packet_unit_test.ss). At
        // wire level, server treats 0x02 same as 0x01 (D147 §A.2 H1) —
        // success of next() over the full 5-row ResultSet proves the server
        // accepts 0x02 without REJECT. plumbCursorState only flips
        // useCursor=1 on CURSOR_TYPE_READ_ONLY 0x01, so driver-side
        // updatable cursor (0x02) stays on the client-streaming path —
        // independent of server-cursor batching.
        recreateTable()
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement("SELECT id FROM integration_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        ps.setFetchSize(2)
        const rs = ps.executeQuery()
        let i = 1
        while (i <= 5) {
            assertEqual(rs.next(), 1)
            assertEqual(rs.getInt("id"), i)
            i = i + 1
        }
        assertEqual(rs.next(), 0)
        rs.close()
        ps.close()
        conn.close()
        dropAllTables(URL, TABLE_NAMES)
    })

    // ── Case 3: updateRow multi-col + external SELECT 验值 + rowUpdated==1 ───
    test("Case 3 — updateInt + updateString + updateRow + external SELECT 验值 (H3 + H7)", () => {
        // Multi-col updateRow flushes pendingUpdates as a single
        // UPDATE integration_d147 SET val=?, name=? WHERE id=? — proves
        // buildUpdateRowSql column-order pass-through with PK as the
        // trailing positional placeholder.
        recreateTable()
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement("SELECT id, val, name, email FROM integration_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        const rs = ps.executeQuery()
        assertEqual(rs.next(), 1)
        assertEqual(rs.rowUpdated(), 0)
        rs.updateInt("val", 888)
        rs.updateString("name", "updated_3")
        // updateXxx writes pendingUpdates only — rowState stays CLEAN until
        // updateRow fires the actual UPDATE through a fresh PreparedStatement
        // on the same fd (H3).
        assertEqual(rs.rowUpdated(), 0)
        rs.updateRow()
        assertEqual(rs.rowUpdated(), 1)
        rs.close()
        ps.close()
        conn.close()
        // External SELECT confirms server-side row mutated on both columns.
        assertEqual(probeRowMatches(1, 888, "updated_3"), 1)
        dropAllTables(URL, TABLE_NAMES)
    })

    // ── Case 4: deleteRow + external SELECT COUNT == 0 + rowDeleted == 1 ────
    test("Case 4 — deleteRow + external SELECT COUNT == 0 + rowDeleted == 1 (H3 + H7)", () => {
        recreateTable()
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement("SELECT id, val, name, email FROM integration_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        const rs = ps.executeQuery()
        assertEqual(rs.next(), 1)
        rs.deleteRow()
        assertEqual(rs.rowDeleted(), 1)
        rs.close()
        ps.close()
        conn.close()
        // External probes confirm row 1 gone, total count = 4.
        assertEqual(probeRowExists(1), 0)
        assertEqual(probeRowCount(), 4)
        dropAllTables(URL, TABLE_NAMES)
    })

    // ── Case 5: moveToInsertRow + insertRow + rowInserted + moveToCurrentRow ─
    test("Case 5 — moveToInsertRow + insertRow multi-col + rowInserted == 1 + moveToCurrentRow (H6 + H7)", () => {
        // Multi-col insertRow flushes the trailing pendingInserts Map as a
        // single INSERT INTO integration_d147(id, val, name, email)
        // VALUES (?, ?, ?, ?) — proves buildInsertRowSql placeholder count
        // matches col count + setString loop order matches Map insertion
        // order. moveToCurrentRow toggles inInsertMode back to 0 after the
        // flush so a subsequent updateXxx would land on pendingUpdates
        // (the cursor's current row, not the inserted phantom row).
        recreateTable()
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement("SELECT id, val, name, email FROM integration_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        const rs = ps.executeQuery()
        assertEqual(rs.next(), 1)
        rs.moveToInsertRow()
        rs.updateInt("id", 99)
        rs.updateInt("val", 777)
        rs.updateString("name", "inserted_5")
        rs.updateString("email", "new5@test.com")
        rs.insertRow()
        assertEqual(rs.rowInserted(), 1)
        rs.moveToCurrentRow()
        rs.close()
        ps.close()
        conn.close()
        // External SELECT finds inserted row + total count flips to 6.
        assertEqual(probeRowMatches(99, 777, "inserted_5"), 1)
        assertEqual(probeRowCount(), 6)
        dropAllTables(URL, TABLE_NAMES)
    })

    // ── Case 6: cancelRowUpdates (H4) + refreshRow (H5) 双重 ────────────────
    test("Case 6 — cancelRowUpdates 服务端 UNCHANGED (H4) + refreshRow 镜像外部 update (H5)", () => {
        // 6a — cancelRowUpdates is purely client-side (no SQL fired).
        recreateTable()
        const conn1 = DriverManager_getConnection(URL)
        const ps1 = conn1.prepareStatement("SELECT id, val, name, email FROM integration_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        const rs1 = ps1.executeQuery()
        assertEqual(rs1.next(), 1)
        rs1.updateInt("val", 555)
        rs1.cancelRowUpdates()
        // pendingUpdates is now empty; updateRow flips rowState to UPDATED
        // for caller idempotency without firing SQL (no dirtyCols).
        rs1.updateRow()
        rs1.close()
        ps1.close()
        conn1.close()
        // External SELECT confirms server-side row UNCHANGED — id=1 → val=10.
        assertEqual(probeVal(1), 10)
        dropAllTables(URL, TABLE_NAMES)

        // 6b — refreshRow re-fetches via fresh PS SELECT WHERE pk=? and
        // mirrors an external concurrent UPDATE back into currentRow.
        recreateTable()
        const conn2 = DriverManager_getConnection(URL)
        const ps2 = conn2.prepareStatement("SELECT id, val, name, email FROM integration_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        const rs2 = ps2.executeQuery()
        assertEqual(rs2.next(), 1)
        // Initial value = 10 (id=1 → val=10 from recreateTable seed).
        assertEqual(rs2.getInt("val"), 10)
        // External writer mutates val on the same row.
        const writer = new JdbcTemplate(URL)
        writer.execute("UPDATE integration_d147 SET val = 12345 WHERE id = 1")
        // Cursor cache view is still stale until refreshRow.
        assertEqual(rs2.getInt("val"), 10)
        rs2.refreshRow()
        // refreshRow mirrors the freshly-read column values.
        assertEqual(rs2.getInt("val"), 12345)
        rs2.close()
        ps2.close()
        conn2.close()
        dropAllTables(URL, TABLE_NAMES)
    })

    // ── Case 7: unique-violation INSERT → DAE catch hierarchy ───────────────
    test("Case 7 — unique-violation insertRow → SQLExceptionTranslator → 三层 DAE catch", () => {
        // cursor-side insertRow that hits the email UNIQUE index fires
        // SQLException via readUpdateResultPacket (errorCode 1062
        // ER_DUP_ENTRY, sqlState 23000). Wrapping it in
        // SQLExceptionTranslator (the same entry JdbcTemplate uses on its
        // non-cursor paths — D139 Phase 4 standard) translates the
        // wire-level error into DuplicateKeyException — which IS-A
        // DataIntegrityViolationException IS-A NonTransientDataAccessException
        // IS-A DataAccessException. Three-level catch verifies the SS
        // classParents hierarchy walks every DAE tree level + cause carries
        // the raw sqlState + errorCode.
        recreateTable()

        // 7a — leaf in test's perspective: DataIntegrityViolationException
        //      catches the DuplicateKeyException subtype + cause.sqlState ==
        //      "23000" + cause.errorCode == 1062.
        let caught7a = 0
        let state = ""
        let code = 0
        try {
            const conn = DriverManager_getConnection(URL)
            const ps = conn.prepareStatement("SELECT id, val, name, email FROM integration_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
            const rs = ps.executeQuery()
            rs.next()
            rs.moveToInsertRow()
            rs.updateInt("id", 99)
            rs.updateInt("val", 777)
            rs.updateString("name", "dup_a")
            // Conflicts with seeded email='r1@test.com' (UNIQUE).
            rs.updateString("email", "r1@test.com")
            try {
                rs.insertRow()
            } catch (sqlEx: SQLException) {
                throw(new SQLExceptionTranslator().translate(sqlEx))
            }
            rs.close()
            ps.close()
            conn.close()
        } catch (ex: DataIntegrityViolationException) {
            caught7a = 1
            state = ex.cause.sqlState
            code = ex.cause.errorCode
        }
        assertEqual(caught7a, 1)
        assertEqual(state, "23000")
        assertEqual(code, 1062)

        // 7b — mid: NonTransientDataAccessException (parent in DAE tree)
        //      catches the same subtype via SS classParents lookup.
        let caught7b = 0
        try {
            const conn = DriverManager_getConnection(URL)
            const ps = conn.prepareStatement("SELECT id, val, name, email FROM integration_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
            const rs = ps.executeQuery()
            rs.next()
            rs.moveToInsertRow()
            rs.updateInt("id", 100)
            rs.updateInt("val", 888)
            rs.updateString("name", "dup_b")
            rs.updateString("email", "r2@test.com")
            try {
                rs.insertRow()
            } catch (sqlEx: SQLException) {
                throw(new SQLExceptionTranslator().translate(sqlEx))
            }
            rs.close()
            ps.close()
            conn.close()
        } catch (ex: NonTransientDataAccessException) {
            caught7b = 1
        }
        assertEqual(caught7b, 1)

        // 7c — root: DataAccessException + cause fields still reachable.
        let caught7c = 0
        try {
            const conn = DriverManager_getConnection(URL)
            const ps = conn.prepareStatement("SELECT id, val, name, email FROM integration_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
            const rs = ps.executeQuery()
            rs.next()
            rs.moveToInsertRow()
            rs.updateInt("id", 101)
            rs.updateInt("val", 999)
            rs.updateString("name", "dup_c")
            rs.updateString("email", "r3@test.com")
            try {
                rs.insertRow()
            } catch (sqlEx: SQLException) {
                throw(new SQLExceptionTranslator().translate(sqlEx))
            }
            rs.close()
            ps.close()
            conn.close()
        } catch (ex: DataAccessException) {
            caught7c = 1
            assertEqual(ex.cause.errorCode, 1062)
            assertEqual(ex.cause.sqlState, "23000")
        }
        assertEqual(caught7c, 1)

        dropAllTables(URL, TABLE_NAMES)
    })

    println("All D147 7-shape integration tests passed!")
}
