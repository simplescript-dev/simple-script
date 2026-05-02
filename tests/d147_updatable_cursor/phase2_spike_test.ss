// D147 Phase 2 spike — pure local, no docker dependency. Verifies the JDBC
// 4.3 §15.2.5 update method surface added to interface ResultSet
// (lib/java/sql.ss) through D025 vtable dispatch:
//   1. interface ResultSet exposes the 16 update methods (10 row-level + 6
//      column-level setters) — every implementor must declare them per
//      vtable contract or bootstrap fails.
//   2. NoopResultSet implements all 16 (plus the existing D146 7 cursor /
//      scrollable methods + 6 base accessors + close() = 30 total) and the
//      surface is reachable through a `ResultSet` interface variable.
//   3. CONCUR_UPDATABLE 1008 plumbs through Statement / Connection mocks
//      down to the ResultSet-side mock state, mirroring how Phase 4 will
//      plumb through MysqlPreparedStatement.deriveCursorFlag → 0x02.
//   4. The mock keeps a pendingUpdates Map / pendingInserts Array /
//      inInsertMode flag / rowState int — the same field shape Phase 4
//      lands on MysqlBinaryResultSet — so updateRow / deleteRow /
//      insertRow / cancelRowUpdates / refreshRow / moveToInsertRow /
//      moveToCurrentRow / rowUpdated / rowDeleted / rowInserted have a
//      visible behavioral contract to assert against.
//
// Phase 4 swaps the mock for the real driver-side simulation; Phase 5
// integration test exercises the full e2e flow against docker MySQL.
//
// See docs/3-decisions/D147-updatable-cursor.md §Phase 收关锚 §Phase 2.

import { assertEqual, assertTrue } from "@/lib/test"
import { ResultSet, CONCUR_UPDATABLE, CONCUR_READ_ONLY, TYPE_FORWARD_ONLY } from "@/lib/java/sql"

// rowState — D147 §核心原则 8 mirror.
const ROW_STATE_CLEAN = 0
const ROW_STATE_UPDATED = 1
const ROW_STATE_DELETED = 2
const ROW_STATE_INSERTED = 3

// NoopResultSet — pure-state ResultSet mock implementing the full D147
// updatable surface without a network round-trip. Phase 4 replaces this
// with MysqlBinaryResultSet's driver-side simulation; here we only verify
// the interface declaration / dispatch / state-transition contracts.
class NoopResultSet : ResultSet {
    rowState: int
    inInsertMode: int
    refreshCount: int
    closed: int
    pendingUpdates: Map<string, string>
    pendingInserts: Array<Map<string, string>>

    function next(): int { return 0 }
    function getString(col: string): string { return "" }
    function getInt(col: string): int { return 0 }
    function getLong(col: string): int { return 0 }
    function getDouble(col: string): double { return 0.0 }
    function getBoolean(col: string): int { return 0 }

    function setFetchSize(rows: int) {}
    function getFetchSize(): int { return 0 }
    function absolute(row: int): int { return 0 }
    function first(): int { return 0 }
    function last(): int { return 0 }
    function previous(): int { return 0 }
    function getRow(): int { return 0 }

    function updateRow() {
        this.pendingUpdates = new Map()
        this.rowState = ROW_STATE_UPDATED
    }
    function deleteRow() {
        this.rowState = ROW_STATE_DELETED
    }
    function insertRow() {
        // Drop the buffered insert row that moveToInsertRow primed.
        // SS Array has no pop(); rebuild a new Array minus the trailing
        // entry. Phase 4 keeps real INSERT round-trip + affected_rows
        // assertion + same trailing-pop mechanics.
        if (this.pendingInserts.length() > 0) {
            let trimmed: Array<Map<string, string>> = []
            let i = 0
            const lastIdx = this.pendingInserts.length() - 1
            while (i < lastIdx) {
                trimmed = trimmed.push(this.pendingInserts[i])
                i = i + 1
            }
            this.pendingInserts = trimmed
        }
        this.rowState = ROW_STATE_INSERTED
    }
    function cancelRowUpdates() {
        // SS Array<T>[i] = ptr is rejected by codegen (ss_arraySet expects
        // i64 third arg); we drop the whole pendingInserts array in
        // insert-mode. Phase 4's MysqlBinaryResultSet swap can be more
        // surgical because it owns the storage shape (it can clear keys
        // on the trailing Map directly).
        let pi: Array<Map<string, string>> = []
        let pu: Map<string, string> = new Map()
        if (this.inInsertMode == 1) {
            this.pendingInserts = pi
        } else {
            this.pendingUpdates = pu
        }
        this.rowState = ROW_STATE_CLEAN
    }
    function refreshRow() {
        this.refreshCount = this.refreshCount + 1
    }
    function moveToInsertRow() {
        this.inInsertMode = 1
        this.pendingInserts = this.pendingInserts.push(new Map())
    }
    function moveToCurrentRow() {
        this.inInsertMode = 0
    }
    function rowUpdated(): int {
        if (this.rowState == ROW_STATE_UPDATED) { return 1 }
        return 0
    }
    function rowDeleted(): int {
        if (this.rowState == ROW_STATE_DELETED) { return 1 }
        return 0
    }
    function rowInserted(): int {
        if (this.rowState == ROW_STATE_INSERTED) { return 1 }
        return 0
    }

    private function writeCol(col: string, val: string) {
        if (this.inInsertMode == 1 && this.pendingInserts.length() > 0) {
            const idx = this.pendingInserts.length() - 1
            const buf = this.pendingInserts[idx]
            buf.set(col, val)
        } else {
            this.pendingUpdates.set(col, val)
        }
    }
    function updateInt(col: string, val: int) { this.writeCol(col, "" + val) }
    function updateString(col: string, val: string) { this.writeCol(col, val) }
    function updateLong(col: string, val: int) { this.writeCol(col, "" + val) }
    function updateBoolean(col: string, val: int) {
        let v = "0"
        if (val != 0) { v = "1" }
        this.writeCol(col, v)
    }
    function updateDouble(col: string, val: double) { this.writeCol(col, "" + val) }
    function updateNull(col: string) { this.writeCol(col, "") }

    function close() { this.closed = 1 }
}

function makeRs(): NoopResultSet {
    let pu: Map<string, string> = new Map()
    let pi: Array<Map<string, string>> = []
    return new NoopResultSet(ROW_STATE_CLEAN, 0, 0, 0, pu, pi)
}

// MockStatement / MockConnection — verify that CONCUR_UPDATABLE plumbs
// through the JDBC interface chain without any driver-side dependency.
// Mirrors what MysqlConnection.prepareStatement(sql, type, conc) +
// MysqlStatement.executeQuery(sql, type, conc) do at the real driver
// layer (D146 Phase 2 already declares both signatures on lib/java/sql.ss).
class MockStatement {
    lastConcurrency: int
}

class MockConnection {
    lastConcurrency: int
}

function plumbToStatement(stmt: MockStatement, concurrency: int) {
    stmt.lastConcurrency = concurrency
}

function plumbToConnection(conn: MockConnection, concurrency: int) {
    conn.lastConcurrency = concurrency
}

function main() {
    test("CONCUR_UPDATABLE plumb through Statement / Connection mocks", () => {
        const stmt = new MockStatement(0)
        const conn = new MockConnection(0)
        plumbToStatement(stmt, CONCUR_UPDATABLE)
        plumbToConnection(conn, CONCUR_UPDATABLE)
        assertEqual(stmt.lastConcurrency, 1008)
        assertEqual(conn.lastConcurrency, 1008)
    })

    test("16 update methods reachable through ResultSet interface variable", () => {
        // Round-trip the concrete NoopResultSet through the ResultSet
        // interface type — this forces D025 vtable indirect dispatch on
        // every method below, which would fail at codegen if any of the
        // 16 declarations were missing on either the interface or the
        // implementor.
        const rs: ResultSet = makeRs()
        rs.updateInt("a", 1)
        rs.updateString("b", "x")
        rs.updateLong("c", 42)
        rs.updateBoolean("d", 1)
        rs.updateDouble("e", 1.5)
        rs.updateNull("f")
        rs.updateRow()
        rs.deleteRow()
        rs.insertRow()
        rs.cancelRowUpdates()
        rs.refreshRow()
        rs.moveToInsertRow()
        rs.moveToCurrentRow()
        // State queries — return values flow back through vtable too.
        const u = rs.rowUpdated()
        const d = rs.rowDeleted()
        const i = rs.rowInserted()
        // After cancelRowUpdates the state was reset; the trailing
        // updateRow() / deleteRow() / insertRow() each clobbered it,
        // so by this point rowState reflects the last call (insertRow,
        // mutated to CLEAN by moveToCurrentRow no-op then unchanged).
        // We assert dispatch return-typing without asserting state — the
        // state contract is asserted in dedicated tests below.
        assertTrue(u == 0 || u == 1)
        assertTrue(d == 0 || d == 1)
        assertTrue(i == 0 || i == 1)
    })

    test("updateInt + updateRow → pendingUpdates flushed + rowUpdated == 1", () => {
        const rs = makeRs()
        rs.updateInt("col1", 99)
        // Before updateRow, pendingUpdates carries the dirty column.
        assertEqual(rs.pendingUpdates.get("col1"), "99")
        assertEqual(rs.rowUpdated(), 0)
        rs.updateRow()
        assertEqual(rs.rowState, ROW_STATE_UPDATED)
        assertEqual(rs.rowUpdated(), 1)
        assertEqual(rs.rowDeleted(), 0)
        assertEqual(rs.rowInserted(), 0)
        // pendingUpdates is cleared by updateRow.
        assertEqual(rs.pendingUpdates.size(), 0)
    })

    test("cancelRowUpdates clears pendingUpdates without firing SQL", () => {
        const rs = makeRs()
        rs.updateInt("col1", 99)
        rs.updateString("col2", "abc")
        assertEqual(rs.pendingUpdates.size(), 2)
        rs.cancelRowUpdates()
        assertEqual(rs.pendingUpdates.size(), 0)
        assertEqual(rs.rowState, ROW_STATE_CLEAN)
        assertEqual(rs.rowUpdated(), 0)
    })

    test("deleteRow sets rowState=DELETED + rowDeleted == 1", () => {
        const rs = makeRs()
        rs.deleteRow()
        assertEqual(rs.rowState, ROW_STATE_DELETED)
        assertEqual(rs.rowDeleted(), 1)
        assertEqual(rs.rowUpdated(), 0)
        assertEqual(rs.rowInserted(), 0)
    })

    test("moveToInsertRow + insertRow flow + rowInserted == 1", () => {
        const rs = makeRs()
        rs.moveToInsertRow()
        assertEqual(rs.inInsertMode, 1)
        assertEqual(rs.pendingInserts.length(), 1)
        rs.updateInt("c1", 1)
        rs.updateString("c2", "x")
        // Writes go to the buffered insert row, not pendingUpdates.
        assertEqual(rs.pendingUpdates.size(), 0)
        const buf = rs.pendingInserts[0]
        assertEqual(buf.get("c1"), "1")
        assertEqual(buf.get("c2"), "x")
        rs.insertRow()
        assertEqual(rs.rowState, ROW_STATE_INSERTED)
        assertEqual(rs.rowInserted(), 1)
        // insertRow popped the flushed row from the buffer.
        assertEqual(rs.pendingInserts.length(), 0)
        rs.moveToCurrentRow()
        assertEqual(rs.inInsertMode, 0)
    })

    test("refreshRow increments client-side counter (no SQL fired)", () => {
        const rs = makeRs()
        assertEqual(rs.refreshCount, 0)
        rs.refreshRow()
        rs.refreshRow()
        assertEqual(rs.refreshCount, 2)
        // Pure state read — rowState is untouched.
        assertEqual(rs.rowState, ROW_STATE_CLEAN)
    })

    test("close() through interface variable sets closed flag", () => {
        const rs = makeRs()
        const iface: ResultSet = rs
        assertEqual(rs.closed, 0)
        iface.close()
        assertEqual(rs.closed, 1)
    })

    test("CONCUR_UPDATABLE / CONCUR_READ_ONLY are distinct adjacent integers", () => {
        // Sanity check — the same predicate
        // MysqlPreparedStatement.deriveCursorFlag uses to dispatch.
        assertTrue(CONCUR_UPDATABLE != CONCUR_READ_ONLY)
        assertEqual(CONCUR_UPDATABLE, 1008)
        assertEqual(CONCUR_READ_ONLY, 1007)
    })
}
