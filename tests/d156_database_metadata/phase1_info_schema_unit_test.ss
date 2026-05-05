// D156 Phase 1 unit test — INFORMATION_SCHEMA per-call PreparedStatement
// helpers + 9 cross-module driver-static accessors. The 8 static-literal
// cases run offline (no docker dependency); the remaining 12 wire-end cases
// require 127.0.0.1:3307 reachable and skip cleanly when it is not (probe
// pattern shared with tests/d155_resultset_metadata/integration_test.ss).
//
// Validates D156 §核心目标 §4 (INFORMATION_SCHEMA per-call PreparedStatement
// path) + §6 (driver / database static metadata) + §7 (命名约定 method) and
// exercises §A.2 H1 (INFORMATION_SCHEMA per-call query feasible — byte-level
// + protocol round-trip) plus H6 (driver name / version hard-codes — SS
// project literals not parsed from any manifest). H2 (catalog vs schema
// single-tier) literal layer; H4 / H7 / H8 (ResultSet column structure +
// keys/indexes JDBC §11 spec alignment) wire end deferred to Phase 4
// integration_test e2e on docker.
//
// To run the full wire-end suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d156_database_metadata/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// See docs/3-decisions/D156-database-metadata.md §Phase 收关锚 §Phase 1.

import { test, assertEqual, assertTrue } from "@/lib/test"
import { SQLException } from "@/lib/java/sql"
import { MysqlConnection, getMysqlConnection, infoSchemaQuery, infoSchemaQueryString, infoSchemaQueryInt, getCatalogTermStatic, getSchemaTermStatic, getProcedureTermStatic, getCatalogSeparatorStatic, getDriverNameStatic, getDriverVersionStatic, getDriverMajorVersionStatic, getDriverMinorVersionStatic, getServerVersionStatic } from "@/lib/com/mysql/jdbc"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"

function main() {
    // ── 8 static accessor literal cases (offline, no docker) ──────────

    test("getCatalogTermStatic returns 'database' (JDBC §11 MySQL convention)", () => {
        assertEqual(getCatalogTermStatic(), "database")
    })

    test("getSchemaTermStatic returns '' (MySQL single-tier model H2)", () => {
        assertEqual(getSchemaTermStatic(), "")
    })

    test("getProcedureTermStatic returns 'procedure'", () => {
        assertEqual(getProcedureTermStatic(), "procedure")
    })

    test("getCatalogSeparatorStatic returns '.'", () => {
        assertEqual(getCatalogSeparatorStatic(), ".")
    })

    test("getDriverNameStatic returns 'MySQL Connector/SS' (H6 hard-code)", () => {
        assertEqual(getDriverNameStatic(), "MySQL Connector/SS")
    })

    test("getDriverVersionStatic returns '1.0' (H6 hard-code)", () => {
        assertEqual(getDriverVersionStatic(), "1.0")
    })

    test("getDriverMajorVersionStatic returns 1", () => {
        assertEqual(getDriverMajorVersionStatic(), 1)
    })

    test("getDriverMinorVersionStatic returns 0", () => {
        assertEqual(getDriverMinorVersionStatic(), 0)
    })

    // ── Probe — skip wire-end cases when 127.0.0.1:3307 is not reachable ──

    try {
        const probe = getMysqlConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D156 Phase 1: 127.0.0.1:3307 unreachable — skipping wire cases.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    const conn = getMysqlConnection(URL)

    // ── infoSchemaQueryString wire-end cases ──────────

    test("infoSchemaQueryString SELECT VERSION() AS v returns non-empty (H1 wire)", () => {
        const v = infoSchemaQueryString(conn, "SELECT VERSION() AS v")
        assertTrue(v.length() > 0)
    })

    test("infoSchemaQueryString SELECT VERSION() no-alias returns non-empty (col reflect)", () => {
        const v = infoSchemaQueryString(conn, "SELECT VERSION()")
        assertTrue(v.length() > 0)
    })

    test("infoSchemaQueryString empty result set returns '' (well-defined empty)", () => {
        const v = infoSchemaQueryString(conn, "SELECT VERSION() AS v WHERE 1 = 0")
        assertEqual(v, "")
    })

    // ── infoSchemaQueryInt wire-end cases ──────────

    test("infoSchemaQueryInt SELECT 1 AS n returns 1", () => {
        assertEqual(infoSchemaQueryInt(conn, "SELECT 1 AS n"), 1)
    })

    test("infoSchemaQueryInt SELECT 42 returns 42 (col reflect on no-alias)", () => {
        assertEqual(infoSchemaQueryInt(conn, "SELECT 42"), 42)
    })

    test("infoSchemaQueryInt empty result set returns 0 (well-defined empty)", () => {
        assertEqual(infoSchemaQueryInt(conn, "SELECT 1 AS n WHERE 1 = 0"), 0)
    })

    // ── infoSchemaQuery (returns ResultSet) wire-end cases ──────────

    test("infoSchemaQuery SHOW DATABASES returns ≥1 row (H2 wire — single-tier)", () => {
        const rs = infoSchemaQuery(conn, "SHOW DATABASES")
        let n = 0
        while (rs.next() == 1) {
            n = n + 1
        }
        assertTrue(n >= 1)
    })

    test("infoSchemaQuery INFORMATION_SCHEMA.SCHEMATA contains 'testdb'", () => {
        const rs = infoSchemaQuery(conn, "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA")
        let found = 0
        while (rs.next() == 1) {
            const name = rs.getString("SCHEMA_NAME")
            if (name == "testdb") { found = 1 }
        }
        assertEqual(found, 1)
    })

    test("infoSchemaQuery INFORMATION_SCHEMA.TABLES filtered by schema runs (H1 wire)", () => {
        const rs = infoSchemaQuery(conn, "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'information_schema'")
        let n = 0
        while (rs.next() == 1) {
            n = n + 1
        }
        assertTrue(n >= 1)
    })

    test("infoSchemaQuery returns ResultSet whose getMetaData() reflects col 1 name", () => {
        const rs = infoSchemaQuery(conn, "SELECT 1 AS only_col")
        assertTrue(rs.next() == 1)
        const md = rs.getMetaData()
        assertEqual(md.getColumnName(1), "only_col")
        rs.close()
    })

    // ── getServerVersionStatic wire-end cases ──────────

    test("getServerVersionStatic returns non-empty MySQL version (H6 + lazy SELECT VERSION())", () => {
        const v = getServerVersionStatic(conn)
        assertTrue(v.length() > 0)
    })

    test("getServerVersionStatic agrees with direct infoSchemaQueryString SELECT VERSION()", () => {
        const a = getServerVersionStatic(conn)
        const b = infoSchemaQueryString(conn, "SELECT VERSION() AS v")
        assertEqual(a, b)
    })

    // ── 1 error-path case (SQL syntax error throws SQLException) ──────────

    test("infoSchemaQuery SQL syntax error throws SQLException", () => {
        let caught = 0
        try {
            const rs = infoSchemaQuery(conn, "SELEC bogus FROM nonexistent_xyz")
            while (rs.next() == 1) {}
        } catch (e: SQLException) {
            caught = 1
        }
        assertEqual(caught, 1)
    })

    conn.close()
}
