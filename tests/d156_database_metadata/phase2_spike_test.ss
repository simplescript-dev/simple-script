// D156 Phase 2 spike — pure-local. 12 case verifies NoopDatabaseMetaData
// stub vtable (≥33 method) + JDBC constants + interface-typed dispatch +
// empty ResultSet routing through D155 ResultSetMetaData (H4 partial).
// See docs/3-decisions/D156-database-metadata.md §Phase 收关锚 §Phase 2.

import { test, assertEqual, assertTrue } from "@/lib/test"
import { ResultSet, DatabaseMetaData, JDBC_MAJOR_VERSION, JDBC_MINOR_VERSION, TRANSACTION_NONE, TRANSACTION_READ_UNCOMMITTED, TRANSACTION_READ_COMMITTED, TRANSACTION_REPEATABLE_READ, TRANSACTION_SERIALIZABLE, TYPE_FORWARD_ONLY, CONCUR_READ_ONLY } from "@/lib/java/sql"
import { NoopDatabaseMetaData } from "@/lib/com/mysql/jdbc"

function main() {
    // ── Case 1: NoopDatabaseMetaData ≥10 string-returning method default "" ─

    test("Case 1: string accessors return empty string by default", () => {
        const md = new NoopDatabaseMetaData()
        assertEqual(md.getDriverName(), "")
        assertEqual(md.getDriverVersion(), "")
        assertEqual(md.getDatabaseProductName(), "")
        assertEqual(md.getDatabaseProductVersion(), "")
        assertEqual(md.getURL(), "")
        assertEqual(md.getUserName(), "")
        assertEqual(md.getCatalogTerm(), "")
        assertEqual(md.getSchemaTerm(), "")
        assertEqual(md.getProcedureTerm(), "")
        assertEqual(md.getCatalogSeparator(), "")
    })

    // ── Case 2: int-returning version method default 0 ─────────────────────

    test("Case 2: driver / JDBC version int methods return 0 by default", () => {
        const md = new NoopDatabaseMetaData()
        assertEqual(md.getDriverMajorVersion(), 0)
        assertEqual(md.getDriverMinorVersion(), 0)
        assertEqual(md.getJDBCMajorVersion(), 0)
        assertEqual(md.getJDBCMinorVersion(), 0)
    })

    // ── Case 3: 5 supportsXxx capability method default 0 ─────────────────

    test("Case 3: supportsXxx capability methods return 0 by default", () => {
        const md = new NoopDatabaseMetaData()
        assertEqual(md.supportsTransactions(), 0)
        assertEqual(md.supportsBatchUpdates(), 0)
        assertEqual(md.supportsTransactionIsolationLevel(TRANSACTION_READ_COMMITTED), 0)
        assertEqual(md.supportsResultSetType(TYPE_FORWARD_ONLY), 0)
        assertEqual(md.supportsResultSetConcurrency(TYPE_FORWARD_ONLY, CONCUR_READ_ONLY), 0)
    })

    // ── Case 4: 0-arg ResultSet-returning method routes through empty stub ─

    test("Case 4: getCatalogs / getSchemas (0-arg) return empty ResultSet (next() = 0)", () => {
        const md = new NoopDatabaseMetaData()
        const rsCat = md.getCatalogs()
        assertEqual(rsCat.next(), 0)
        rsCat.close()
        const rsSch = md.getSchemas()
        assertEqual(rsSch.next(), 0)
        rsSch.close()
    })

    // ── Case 5: 2-arg / 3-arg ResultSet-returning methods dispatch + empty ─

    test("Case 5: getSchemas(catalog, pat) / getPrimaryKeys / getImported/Exported/Functions return empty ResultSet", () => {
        const md = new NoopDatabaseMetaData()
        assertEqual(md.getSchemas("", "%").next(), 0)
        assertEqual(md.getPrimaryKeys("", "", "t").next(), 0)
        assertEqual(md.getImportedKeys("", "", "t").next(), 0)
        assertEqual(md.getExportedKeys("", "", "t").next(), 0)
        assertEqual(md.getFunctions("", "%", "%").next(), 0)
        assertEqual(md.getProcedures("", "%", "%").next(), 0)
    })

    // ── Case 6: 4-arg ResultSet-returning getTables / getColumns / *Columns ─

    test("Case 6: getTables / getColumns / getProcedureColumns / getFunctionColumns 4-arg dispatch return empty", () => {
        const md = new NoopDatabaseMetaData()
        assertEqual(md.getTables("", "%", "%", "TABLE").next(), 0)
        assertEqual(md.getColumns("", "%", "%", "%").next(), 0)
        assertEqual(md.getProcedureColumns("", "%", "%", "%").next(), 0)
        assertEqual(md.getFunctionColumns("", "%", "%", "%").next(), 0)
    })

    // ── Case 7: 5-arg int+int / 6-arg getCrossReference dispatch ──────────

    test("Case 7: getIndexInfo (int int) + getCrossReference (6-arg) dispatch return empty", () => {
        const md = new NoopDatabaseMetaData()
        assertEqual(md.getIndexInfo("", "", "t", 0, 0).next(), 0)
        assertEqual(md.getCrossReference("", "", "p", "", "", "f").next(), 0)
    })

    // ── Case 8: JDBC version constants exposed by sql.ss ──────────────────

    test("Case 8: JDBC_MAJOR_VERSION = 4 / JDBC_MINOR_VERSION = 3", () => {
        assertEqual(JDBC_MAJOR_VERSION, 4)
        assertEqual(JDBC_MINOR_VERSION, 3)
    })

    // ── Case 9: TRANSACTION isolation level constants (note 4 / 8 gap) ────

    test("Case 9: TRANSACTION_NONE 0 / READ_UNCOMMITTED 1 / READ_COMMITTED 2 / REPEATABLE_READ 4 / SERIALIZABLE 8", () => {
        assertEqual(TRANSACTION_NONE, 0)
        assertEqual(TRANSACTION_READ_UNCOMMITTED, 1)
        assertEqual(TRANSACTION_READ_COMMITTED, 2)
        assertEqual(TRANSACTION_REPEATABLE_READ, 4)
        assertEqual(TRANSACTION_SERIALIZABLE, 8)
    })

    // ── Case 10: DatabaseMetaData interface variable dispatch (vtable) ────

    test("Case 10: DatabaseMetaData interface-typed variable dispatches through vtable", () => {
        let md: DatabaseMetaData = new NoopDatabaseMetaData()
        assertEqual(md.getDriverName(), "")
        assertEqual(md.getDriverMajorVersion(), 0)
        assertEqual(md.supportsTransactions(), 0)
        assertEqual(md.getCatalogs().next(), 0)
    })

    // ── Case 11: ResultSet interface variable from getMetaData walks D155 ─

    test("Case 11: ResultSet interface variable from getCatalogs / getTables walks vtable cleanly", () => {
        const md = new NoopDatabaseMetaData()
        let rs: ResultSet = md.getCatalogs()
        assertEqual(rs.next(), 0)
        rs.close()
        let rs2: ResultSet = md.getTables("", "%", "%", "TABLE")
        assertEqual(rs2.next(), 0)
        rs2.close()
    })

    // ── Case 12: stub ResultSet exposes a live ResultSetMetaData (H4 partial) ─

    test("Case 12: stub ResultSet routes getMetaData() through D155 path (H4 partial)", () => {
        const md = new NoopDatabaseMetaData()
        const rs = md.getCatalogs()
        const rsmd = rs.getMetaData()
        // Reusing GeneratedKeyResultSet (1-col GENERATED_KEY metadata via
        // MysqlResultSetMetaData) over an EmptyResultSetMetaData walks the
        // D155 path end-to-end (H4 partial — Phase 3 wires INFO_SCHEMA cols).
        assertEqual(rsmd.getColumnCount(), 1)
        assertEqual(rsmd.getColumnName(1), "GENERATED_KEY")
        rs.close()
    })
}
