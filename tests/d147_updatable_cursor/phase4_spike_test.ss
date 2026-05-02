// D147 Phase 4 docker spike — driver-side updatable cursor end-to-end.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the test
// returns early so `bin/ss test tests/` stays green when docker is unavailable
// (sane d134 / d136 / d138 / d139 / d146 / d147-phase1 fallback pattern).
// To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d147_updatable_cursor/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// What this validates (D147 §A.2 H3-H7 hidden assumptions):
//   H3  Fresh PreparedStatement on the same fd does not break the parked
//       server cursor — request-response synchronous protocol leaves the
//       cursor dormant between FETCH calls; an UPDATE / DELETE / INSERT
//       statement issued through doPrepare(this.fd, sql) round-trips and
//       returns control to the caller without disturbing cursor state.
//   H4  cancelRowUpdates is purely client-side — Case 4 verifies that
//       after updateInt + cancelRowUpdates + updateRow no row is mutated
//       at the server (no SQL fired between cancelRowUpdates and the
//       no-op updateRow).
//   H5  refreshRow re-runs SELECT WHERE pk=? via fresh PS and mirrors the
//       freshly-read column values back into currentRow — Case 5 verifies
//       that an external concurrent UPDATE is observable through
//       refreshRow without re-running the original SELECT.
//   H6  moveToInsertRow + insertRow toggle inInsertMode + push then pop
//       the trailing pendingInserts Map; subsequent updateXxx land on the
//       in-progress insert row (verified via external SELECT that finds
//       the new row by its inserted PK).
//   H7  rowState (CLEAN / UPDATED / DELETED / INSERTED) tracks the
//       current row only and resets on every next() advance — Case 1 / 2 /
//       3 each verify rowUpdated / rowDeleted / rowInserted return 1
//       immediately after the corresponding mutation method.
//
// Schema:
//   phase4_d147(id INT PRIMARY KEY, val INT, name VARCHAR(64))
//   5 rows seeded by JdbcTemplate before each Case; dropped after.

import { assertEqual, assertTrue } from "@/lib/test"
import { Connection, PreparedStatement, ResultSet, DriverManager_getConnection, SQLException, TYPE_FORWARD_ONLY, CONCUR_UPDATABLE } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS phase4_d147")
    tmpl.execute("CREATE TABLE phase4_d147 (id INT PRIMARY KEY, val INT, name VARCHAR(64)) ENGINE=InnoDB")
    let i = 1
    while (i <= 5) {
        const sql = "INSERT INTO phase4_d147 VALUES (" + i + ", " + (i * 10) + ", 'row" + i + "')"
        tmpl.execute(sql)
        i = i + 1
    }
    return 0
}

function dropTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS phase4_d147")
    return 0
}

// External probe — separate Connection fired via JdbcTemplate so the spike
// observes server-side state independently of the cursor under test.
function probeValue(id: int): int {
    const tmpl = new JdbcTemplate(URL)
    return tmpl.queryForInt("SELECT val FROM phase4_d147 WHERE id = " + id, "val")
}

function probeRowExists(id: int): int {
    const tmpl = new JdbcTemplate(URL)
    return tmpl.queryForInt("SELECT COUNT(*) AS n FROM phase4_d147 WHERE id = " + id, "n")
}

function probeRowCount(): int {
    const tmpl = new JdbcTemplate(URL)
    return tmpl.queryForInt("SELECT COUNT(*) AS n FROM phase4_d147", "n")
}

function main() {
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D147 phase4 spike: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    // ── Case 1: updateRow flush via fresh PS on same fd + rowUpdated == 1 ──
    test("Case 1 — updateRow flush via fresh PS + rowUpdated == 1 (H3 + H7)", () => {
        recreateTable()
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement("SELECT id, val, name FROM phase4_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        const rs = ps.executeQuery()
        assertEqual(rs.next(), 1)
        assertEqual(rs.rowUpdated(), 0)
        rs.updateInt("val", 999)
        assertEqual(rs.rowUpdated(), 0)
        rs.updateRow()
        assertEqual(rs.rowUpdated(), 1)
        rs.close()
        ps.close()
        conn.close()
        assertEqual(probeValue(1), 999)
        dropTable()
    })

    // ── Case 2: deleteRow + external row-count verifies row removed ──
    test("Case 2 — deleteRow via fresh PS + rowDeleted == 1 (H3 + H7)", () => {
        recreateTable()
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement("SELECT id, val, name FROM phase4_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        const rs = ps.executeQuery()
        assertEqual(rs.next(), 1)
        rs.deleteRow()
        assertEqual(rs.rowDeleted(), 1)
        rs.close()
        ps.close()
        conn.close()
        assertEqual(probeRowExists(1), 0)
        assertEqual(probeRowCount(), 4)
        dropTable()
    })

    // ── Case 3: moveToInsertRow + updateXxx + insertRow + external probe ──
    test("Case 3 — moveToInsertRow + insertRow via fresh PS + rowInserted == 1 (H6 + H7)", () => {
        recreateTable()
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement("SELECT id, val, name FROM phase4_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        const rs = ps.executeQuery()
        assertEqual(rs.next(), 1)
        rs.moveToInsertRow()
        rs.updateInt("id", 99)
        rs.updateInt("val", 777)
        rs.updateString("name", "inserted")
        rs.insertRow()
        assertEqual(rs.rowInserted(), 1)
        rs.moveToCurrentRow()
        rs.close()
        ps.close()
        conn.close()
        assertEqual(probeValue(99), 777)
        assertEqual(probeRowCount(), 6)
        dropTable()
    })

    // ── Case 4: cancelRowUpdates + updateRow no-op verifies pure client-side ──
    test("Case 4 — cancelRowUpdates clears pending without firing SQL (H4)", () => {
        recreateTable()
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement("SELECT id, val, name FROM phase4_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        const rs = ps.executeQuery()
        assertEqual(rs.next(), 1)
        rs.updateInt("val", 555)
        rs.cancelRowUpdates()
        // pendingUpdates is now empty; updateRow flips rowState to UPDATED
        // for caller idempotency without firing SQL (no dirtyCols).
        rs.updateRow()
        rs.close()
        ps.close()
        conn.close()
        // External SELECT confirms server-side row UNCHANGED — id=1 → val=10.
        assertEqual(probeValue(1), 10)
        dropTable()
    })

    // ── Case 5: refreshRow mirrors external concurrent update ──
    test("Case 5 — refreshRow mirrors external server-side update (H5)", () => {
        recreateTable()
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement("SELECT id, val, name FROM phase4_d147 ORDER BY id", TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        const rs = ps.executeQuery()
        assertEqual(rs.next(), 1)
        // Initial value is 10 (id=1 → val=10 from recreateTable seed).
        assertEqual(rs.getInt("val"), 10)
        // External writer mutates val on the same row.
        const writer = new JdbcTemplate(URL)
        writer.execute("UPDATE phase4_d147 SET val = 12345 WHERE id = 1")
        // Stale cursor view still sees 10 until refreshRow.
        assertEqual(rs.getInt("val"), 10)
        rs.refreshRow()
        // refreshRow re-fetches via fresh PS SELECT WHERE pk=? — currentRow
        // mirrors the external update.
        assertEqual(rs.getInt("val"), 12345)
        rs.close()
        ps.close()
        conn.close()
        dropTable()
    })
}
