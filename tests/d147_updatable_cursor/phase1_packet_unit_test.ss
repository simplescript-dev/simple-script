// D147 Phase 1 unit test — pure local, no docker dependency. Verifies the
// protocol-layer building blocks added to query.ss + sql.ss + prepared.ss
// for Updatable cursor:
//   1. CURSOR_TYPE_FOR_UPDATE 0x02 / CONCUR_UPDATABLE 1008 constant values.
//   2. Constants don't collide with D146 cursor / concurrency constants.
//   3. MysqlPreparedStatement.deriveCursorFlag dual-semantic dispatch:
//        concurrency=CONCUR_UPDATABLE → CURSOR_TYPE_FOR_UPDATE 0x02
//        concurrency=CONCUR_READ_ONLY + fetchSize>0 → CURSOR_TYPE_READ_ONLY
//          (D146 baseline preserved)
//        concurrency=CONCUR_READ_ONLY + fetchSize=0 → CURSOR_TYPE_NO_CURSOR
//          (D146 default client streaming)
//        concurrency=unknown (0) → falls through to D146 type+fetchSize path
//
// Server flags=0x02 round-trip is verified by the docker spike
// (phase1_spike_test.ss) — D147 §A.2 H1 实证 server treats 0x02 same as 0x01.
//
// See docs/3-decisions/D147-updatable-cursor.md §Phase 收关锚 §Phase 1.

import { assertEqual } from "@/lib/test"
import { ColumnDef, CURSOR_TYPE_FOR_UPDATE, CURSOR_TYPE_READ_ONLY } from "@/lib/com/mysql/query"
import { CONCUR_UPDATABLE, CONCUR_READ_ONLY, TYPE_FORWARD_ONLY, TYPE_SCROLL_INSENSITIVE } from "@/lib/java/sql"
import { MysqlPreparedStatement } from "@/lib/com/mysql/prepared"

const CURSOR_TYPE_NO_CURSOR = 0x00

// Constructs a MysqlPreparedStatement instance for unit-testing
// deriveCursorFlag without a COM_STMT_PREPARE round-trip. fd=-1 stays
// untouched — deriveCursorFlag is a pure function of (concurrency,
// rsType, fetchSize) reachable through public setters.
function makePs(): MysqlPreparedStatement {
    let pDefs: Array<ColumnDef> = []
    let cols: Array<ColumnDef> = []
    return new MysqlPreparedStatement(-1, 0, 0, pDefs, [], [], [], [], cols, 0, 0, 0, 0, 0)
}

function main() {
    test("Updatable cursor constants match MySQL protocol + JDBC spec", () => {
        // MySQL Native Protocol §6.5.1 — COM_STMT_EXECUTE flags bit 1
        assertEqual(CURSOR_TYPE_FOR_UPDATE, 0x02)
        // JDBC 4.3 §java.sql.ResultSet.CONCUR_UPDATABLE — standard value
        assertEqual(CONCUR_UPDATABLE, 1008)
    })

    test("constants don't collide with D146 cursor / concurrency", () => {
        // D146 cursor flags are at bit 0 / no bit set; new flag at bit 1
        assertEqual(CURSOR_TYPE_FOR_UPDATE & CURSOR_TYPE_READ_ONLY, 0)
        assertEqual(CURSOR_TYPE_FOR_UPDATE & CURSOR_TYPE_NO_CURSOR, 0)
        // CONCUR_READ_ONLY (1007) and CONCUR_UPDATABLE (1008) are adjacent
        // distinct integers per JDBC spec
        assertEqual(CONCUR_UPDATABLE - CONCUR_READ_ONLY, 1)
    })

    test("deriveCursorFlag CONCUR_UPDATABLE → CURSOR_TYPE_FOR_UPDATE 0x02", () => {
        const ps = makePs()
        // Plumb concurrency = CONCUR_UPDATABLE via setCursorMode (the same
        // entry MysqlConnection.prepareStatement(sql, type, conc) uses).
        ps.setCursorMode(TYPE_FORWARD_ONLY, CONCUR_UPDATABLE)
        assertEqual(ps.deriveCursorFlag(0), CURSOR_TYPE_FOR_UPDATE)
        // Updatable concurrency overrides type+fetchSize — even with
        // setFetchSize(100) the flag stays 0x02 (driver-side simulation
        // is independent of server-cursor batching).
        ps.setFetchSize(100)
        assertEqual(ps.deriveCursorFlag(0), CURSOR_TYPE_FOR_UPDATE)
    })

    test("deriveCursorFlag CONCUR_READ_ONLY + fetchSize>0 → CURSOR_TYPE_READ_ONLY (D146 path)", () => {
        const ps = makePs()
        ps.setCursorMode(TYPE_FORWARD_ONLY, CONCUR_READ_ONLY)
        ps.setFetchSize(100)
        assertEqual(ps.deriveCursorFlag(0), CURSOR_TYPE_READ_ONLY)
    })

    test("deriveCursorFlag CONCUR_READ_ONLY + fetchSize=0 → CURSOR_TYPE_NO_CURSOR (D146 default)", () => {
        const ps = makePs()
        ps.setCursorMode(TYPE_FORWARD_ONLY, CONCUR_READ_ONLY)
        // fetchSize defaults to 0 on a fresh ps — D146 client streaming.
        assertEqual(ps.deriveCursorFlag(0), CURSOR_TYPE_NO_CURSOR)
    })

    test("deriveCursorFlag unknown concurrency 0 falls through to D146 dispatch", () => {
        const ps = makePs()
        // concurrency = 0 (default ctor value) is neither CONCUR_READ_ONLY
        // 1007 nor CONCUR_UPDATABLE 1008; the predicate `== CONCUR_UPDATABLE`
        // misses, so D146 type/fetchSize logic decides.
        assertEqual(ps.deriveCursorFlag(0), CURSOR_TYPE_NO_CURSOR)
        ps.setFetchSize(100)
        assertEqual(ps.deriveCursorFlag(0), CURSOR_TYPE_READ_ONLY)
    })

    test("deriveCursorFlag scrollable + CONCUR_UPDATABLE — concurrency wins over type", () => {
        const ps = makePs()
        ps.setCursorMode(TYPE_SCROLL_INSENSITIVE, CONCUR_UPDATABLE)
        // CONCUR_UPDATABLE wins over TYPE_SCROLL_INSENSITIVE — Phase 4
        // driver-side simulation handles scrollable + updatable
        // independently (each end maintains its own state).
        assertEqual(ps.deriveCursorFlag(0), CURSOR_TYPE_FOR_UPDATE)
    })
}
