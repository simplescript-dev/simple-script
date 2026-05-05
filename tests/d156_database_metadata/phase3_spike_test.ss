// D156 Phase 3 spike — pure-local. 16 case verifies MysqlDatabaseMetaData
// real reflection (Driver / Database / JDBC / naming / supportsXxx /
// INFO_SCHEMA stub-empty) + lazy cache + interface vtable dispatch +
// catalog vs schema single-tier (§A.2 H2). Wire-end content goes Phase 4.
// See docs/3-decisions/D156-database-metadata.md §Phase 收关锚 §Phase 3.

import { test, assertEqual, assertTrue } from "@/lib/test"
import { ResultSet, DatabaseMetaData, JDBC_MAJOR_VERSION, JDBC_MINOR_VERSION, TRANSACTION_NONE, TRANSACTION_READ_UNCOMMITTED, TRANSACTION_READ_COMMITTED, TRANSACTION_REPEATABLE_READ, TRANSACTION_SERIALIZABLE, TYPE_FORWARD_ONLY, TYPE_SCROLL_INSENSITIVE, TYPE_SCROLL_SENSITIVE, CONCUR_READ_ONLY, CONCUR_UPDATABLE } from "@/lib/java/sql"
import { MysqlConnection, MysqlDatabaseMetaData, NoopDatabaseMetaData, getDriverNameStatic, getDriverVersionStatic, getDriverMajorVersionStatic, getDriverMinorVersionStatic, getCatalogTermStatic, getSchemaTermStatic, getProcedureTermStatic, getCatalogSeparatorStatic } from "@/lib/com/mysql/jdbc"

// Pure-local stand-in. fd = -1 → OS rejects any accidental socket call;
// metaDataCache seeded with NoopDatabaseMetaData sentinel.
function makeFakeConnection(): MysqlConnection {
    return new MysqlConnection(-1, 1, 0, "jdbc:mysql://localhost:3307/testdb", "testuser", new NoopDatabaseMetaData(), 0)
}

function main() {
    // ── Case 1: MysqlDatabaseMetaData fields + construction ──────────────

    test("Case 1: MysqlDatabaseMetaData constructs with conn ref + lazy cache fields", () => {
        const conn = makeFakeConnection()
        const md = new MysqlDatabaseMetaData(conn, "", 0)
        // cachedVersionInited starts at 0 (no SELECT VERSION() round-trip yet)
        assertEqual(md.cachedVersionInited, 0)
        assertEqual(md.cachedDatabaseProductVersion, "")
    })

    // ── Case 2: Driver static 4 methods delegate to Phase 1 helpers ──────

    test("Case 2: Driver static 4 methods agree with Phase 1 helpers", () => {
        const md = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        assertEqual(md.getDriverName(), getDriverNameStatic())
        assertEqual(md.getDriverVersion(), getDriverVersionStatic())
        assertEqual(md.getDriverMajorVersion(), getDriverMajorVersionStatic())
        assertEqual(md.getDriverMinorVersion(), getDriverMinorVersionStatic())
    })

    // ── Case 3: Database identity — productName + URL/userName direct ────

    test("Case 3: getDatabaseProductName / getURL / getUserName return MySQL + conn fields", () => {
        const conn = makeFakeConnection()
        const md = new MysqlDatabaseMetaData(conn, "", 0)
        assertEqual(md.getDatabaseProductName(), "MySQL")
        assertEqual(md.getURL(), "jdbc:mysql://localhost:3307/testdb")
        assertEqual(md.getUserName(), "testuser")
    })

    // ── Case 4: JDBC version — 4.3 spec literals ─────────────────────────

    test("Case 4: getJDBCMajorVersion = 4 / getJDBCMinorVersion = 3", () => {
        const md = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        assertEqual(md.getJDBCMajorVersion(), JDBC_MAJOR_VERSION)
        assertEqual(md.getJDBCMinorVersion(), JDBC_MINOR_VERSION)
        assertEqual(md.getJDBCMajorVersion(), 4)
        assertEqual(md.getJDBCMinorVersion(), 3)
    })

    // ── Case 5: Naming convention — single-tier MySQL (§A.2 H2) ──────────

    test("Case 5: getCatalogTerm = 'database' / SchemaTerm = '' / Procedure = 'procedure' / Sep = '.'", () => {
        const md = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        assertEqual(md.getCatalogTerm(), "database")
        assertEqual(md.getSchemaTerm(), "")
        assertEqual(md.getProcedureTerm(), "procedure")
        assertEqual(md.getCatalogSeparator(), ".")
    })

    // ── Case 6: supportsTransactions / BatchUpdates = 1 (Phase 2 stub = 0) ─

    test("Case 6: supportsTransactions = 1 / supportsBatchUpdates = 1 (real values)", () => {
        const md = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        assertEqual(md.supportsTransactions(), 1)
        assertEqual(md.supportsBatchUpdates(), 1)
    })

    // ── Case 7: supportsTransactionIsolationLevel — 4 supported, NONE rejected ─

    test("Case 7: supportsTransactionIsolationLevel — 4 levels supported, NONE rejected", () => {
        const md = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        assertEqual(md.supportsTransactionIsolationLevel(TRANSACTION_NONE), 0)
        assertEqual(md.supportsTransactionIsolationLevel(TRANSACTION_READ_UNCOMMITTED), 1)
        assertEqual(md.supportsTransactionIsolationLevel(TRANSACTION_READ_COMMITTED), 1)
        assertEqual(md.supportsTransactionIsolationLevel(TRANSACTION_REPEATABLE_READ), 1)
        assertEqual(md.supportsTransactionIsolationLevel(TRANSACTION_SERIALIZABLE), 1)
    })

    // ── Case 8: supportsResultSetType — FORWARD/SCROLL_INSENSITIVE supported ─

    test("Case 8: supportsResultSetType — FORWARD_ONLY=1 / SCROLL_INSENSITIVE=1 / SCROLL_SENSITIVE=0", () => {
        const md = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        assertEqual(md.supportsResultSetType(TYPE_FORWARD_ONLY), 1)
        assertEqual(md.supportsResultSetType(TYPE_SCROLL_INSENSITIVE), 1)
        // MySQL 5.7+ has no server scrollable cursor — Connector/J 5.1+ documented
        assertEqual(md.supportsResultSetType(TYPE_SCROLL_SENSITIVE), 0)
    })

    // ── Case 9: supportsResultSetConcurrency — 2-arg capability matrix ───

    test("Case 9: supportsResultSetConcurrency 2-arg matrix (READ_ONLY/UPDATABLE × cursor types)", () => {
        const md = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        // READ_ONLY supported on FORWARD + SCROLL_INSENSITIVE
        assertEqual(md.supportsResultSetConcurrency(TYPE_FORWARD_ONLY, CONCUR_READ_ONLY), 1)
        assertEqual(md.supportsResultSetConcurrency(TYPE_SCROLL_INSENSITIVE, CONCUR_READ_ONLY), 1)
        assertEqual(md.supportsResultSetConcurrency(TYPE_SCROLL_SENSITIVE, CONCUR_READ_ONLY), 0)
        // UPDATABLE supported only on FORWARD (D147 simulated cursor)
        assertEqual(md.supportsResultSetConcurrency(TYPE_FORWARD_ONLY, CONCUR_UPDATABLE), 1)
        assertEqual(md.supportsResultSetConcurrency(TYPE_SCROLL_INSENSITIVE, CONCUR_UPDATABLE), 0)
    })

    // ── Case 10: getSchemas / getProcedureColumns / getFunctionColumns empty ─

    test("Case 10: getSchemas (0/2-arg) + getProcedureColumns + getFunctionColumns return empty ResultSet", () => {
        const md = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        assertEqual(md.getSchemas().next(), 0)
        assertEqual(md.getSchemas("", "%").next(), 0)
        assertEqual(md.getProcedureColumns("", "%", "%", "%").next(), 0)
        assertEqual(md.getFunctionColumns("", "%", "%", "%").next(), 0)
    })

    // ── Case 11: DatabaseMetaData interface vtable dispatch ──────────────

    test("Case 11: DatabaseMetaData interface variable dispatches MysqlDatabaseMetaData via vtable", () => {
        const md: DatabaseMetaData = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        assertEqual(md.getDriverName(), getDriverNameStatic())
        assertEqual(md.getJDBCMajorVersion(), 4)
        assertEqual(md.getCatalogTerm(), "database")
        assertEqual(md.supportsTransactions(), 1)
    })

    // ── Case 12: MysqlConnection.getMetaData lazy cache same reference ──

    test("Case 12: MysqlConnection.getMetaData() returns same instance on repeat call (lazy cache)", () => {
        const conn = makeFakeConnection()
        const md1 = conn.getMetaData()
        const md2 = conn.getMetaData()
        // After first call metaDataInited flips to 1 and cache is populated
        assertEqual(conn.metaDataInited, 1)
        // Verify the cached instance is real reflection (driver name non-empty)
        assertEqual(md1.getDriverName(), getDriverNameStatic())
        assertEqual(md2.getDriverName(), getDriverNameStatic())
        assertEqual(md1.getURL(), conn.url)
        assertEqual(md2.getURL(), conn.url)
    })

    // ── Case 13: catalog vs schema single-tier (§A.2 H2 static stub) ──────

    test("Case 13: catalog vs schema single-tier — getSchemaTerm '' + getSchemas empty", () => {
        const md = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        // Single-tier: catalog tier carries the database name, schema tier
        // collapses (schema term is empty + getSchemas returns empty RS)
        assertEqual(md.getSchemaTerm(), "")
        assertEqual(md.getCatalogTerm(), "database")
        const rs = md.getSchemas()
        assertEqual(rs.next(), 0)
        rs.close()
    })

    // ── Case 14: empty ResultSet routes through D155 ResultSetMetaData (H4) ─

    test("Case 14: getSchemas() empty RS exposes D155 ResultSetMetaData (column count + GENERATED_KEY)", () => {
        const md = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        const rs = md.getSchemas()
        const rsmd = rs.getMetaData()
        // Reusing GeneratedKeyResultSet metadata path (Phase 2 stub) — H4 partial
        assertEqual(rsmd.getColumnCount(), 1)
        assertEqual(rsmd.getColumnName(1), "GENERATED_KEY")
        rs.close()
    })

    // ── Case 15: lazy cache fields stay 0/'' when getDatabaseProductVersion not called ─

    test("Case 15: lazy cache untouched until getDatabaseProductVersion call", () => {
        const md = new MysqlDatabaseMetaData(makeFakeConnection(), "", 0)
        // Calling other methods does not flip the lazy version cache
        assertEqual(md.getDriverName(), getDriverNameStatic())
        assertEqual(md.getDatabaseProductName(), "MySQL")
        assertEqual(md.getCatalogTerm(), "database")
        assertEqual(md.cachedVersionInited, 0)
        assertEqual(md.cachedDatabaseProductVersion, "")
    })

    // ── Case 16: MysqlConnection.metaDataCache before getMetaData ─────────

    test("Case 16: MysqlConnection.metaDataInited 0 before getMetaData; cache is NoopDatabaseMetaData sentinel", () => {
        const conn = makeFakeConnection()
        // Before any getMetaData() call, sentinel is NoopDatabaseMetaData
        assertEqual(conn.metaDataInited, 0)
        // getDriverName on the sentinel returns "" (Phase 2 stub default).
        // Bind to local first — chained field-then-method on interface-typed
        // field needs an explicit step (codegen note in jdbc.ss).
        let sentinel: DatabaseMetaData = conn.metaDataCache
        assertEqual(sentinel.getDriverName(), "")
        // Trigger lazy install
        const md = conn.getMetaData()
        assertEqual(conn.metaDataInited, 1)
        assertEqual(md.getDriverName(), getDriverNameStatic())
        // Sentinel was overwritten — cache is now MysqlDatabaseMetaData
        let installed: DatabaseMetaData = conn.metaDataCache
        assertEqual(installed.getDriverName(), getDriverNameStatic())
    })
}
