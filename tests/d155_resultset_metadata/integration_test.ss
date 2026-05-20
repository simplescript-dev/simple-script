// D155 §Phase 4 收关 — wire-end e2e integration test (docker probe-skip).
//
// Verifies the MysqlResultSetMetaData class real-reflection behavior
// (lib/com/mysql/query.ss D155 §Phase 3) on an actual MySQL 8.0 docker
// instance — every JDBC §15.4 column attribute reflects through the
// ColumnDef41 packet returned by the wire end-to-end. Subsumes
// phase2_spike_test.ss (8 case stub stage) + phase3_spike_test.ss (13
// case pure-local reflection stage) — both removed in this Phase per
// D155 §Phase 4 absorb decision. phase1_columndef_unit_test.ss is kept
// because it exercises byte-level fixture pass-through which docker
// e2e cannot replicate (binary printf with embedded 0x00 survives only
// in pure-local mode).
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the
// test prints a hint and returns 0 so `bin/ss test tests/` stays green
// when docker is unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d155_resultset_metadata/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Uses table `integration_d155` to isolate from D134 (`users`) /
// D136 / D138 / D139 / D146 / D147 (`integration_d147`) /
// D151 / D154 under `bin/ss test tests/` parallel batch.
//
// Validates D155 §核心目标 §10 + §A.2 H1-H7 wire-end 实证 (10 cases):
//   Case 1 — getColumnCount real SELECT 5 col → 5 (H1 wire)
//   Case 2 — getColumnName/Label/Type/TypeName/DisplaySize/ClassName
//            6 method 复合 on BIGINT UNSIGNED + VARCHAR (H3 wire)
//   Case 3 — getCatalogName/SchemaName/TableName ("def" / "testdb" /
//            "integration_d155") (H1 wire)
//   Case 4 — isNullable: NOT_NULL → columnNoNulls; nullable →
//            columnNullable (H2 wire)
//   Case 5 — isAutoIncrement: AUTO_INCREMENT_FLAG bit on PK col
//            (H2 wire)
//   Case 6 — isSigned: UNSIGNED_FLAG bit on BIGINT UNSIGNED (H2 wire)
//   Case 7 — getPrecision + getScale on DECIMAL(10,2) (H1 wire)
//   Case 8 — ResultSet.close() 后 getMetaData() 仍可访问 (H7 wire 实证)
//   Case 9 — GeneratedKeyResultSet.getMetaData() synthetic 1-col after
//            real INSERT + getGeneratedKeys (H5 wire 实证)
//   Case 10 — text(MysqlResultSet) 与 binary(MysqlBinaryResultSet)
//            protocol metadata 同 SELECT 同字段 (H6 wire 实证)
//
// See docs/3-decisions/D155-resultset-metadata.md §Phase 收关锚 §Phase 4.

import { test, assertEqual, assertTrue } from "@/lib/test"
import { Connection, Statement, PreparedStatement, ResultSet, ResultSetMetaData, DriverManager_getConnection, SQLException, columnNoNulls, columnNullable, JDBC_TYPE_BIGINT, JDBC_TYPE_VARCHAR, JDBC_TYPE_DECIMAL } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"
import { dropAllTables } from "@/tests/jdbc/import/jdbc_test_helpers"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"
const SCHEMA = "testdb"
const TABLE = "integration_d155"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS integration_d155")
    tmpl.execute("CREATE TABLE integration_d155 (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(64) NOT NULL, price DECIMAL(10, 2) NOT NULL, qty INT, code BIGINT UNSIGNED NOT NULL) ENGINE=InnoDB")
    tmpl.execute("INSERT INTO integration_d155 (name, price, qty, code) VALUES ('row1', 19.99, 5, 100)")
    tmpl.execute("INSERT INTO integration_d155 (name, price, qty, code) VALUES ('row2', 29.99, NULL, 200)")
    return 0
}

function main() {
    // Probe — skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D155 integration: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    // ── Case 1 — getColumnCount real SELECT 5 col → 5 (H1 wire) ─
    test("Case 1 — getColumnCount real SELECT 多列 (H1 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.createStatement()
        const rs = stmt.executeQuery("SELECT id, name, price, qty, code FROM integration_d155 LIMIT 1")
        const md = rs.getMetaData()
        assertEqual(md.getColumnCount(), 5)
        rs.close()
        conn.close()
    })

    // ── Case 2 — 6 method 复合 (BIGINT UNSIGNED + VARCHAR) ───────
    test("Case 2 — getColumnName/Label/Type/TypeName/DisplaySize/ClassName (H3 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.createStatement()
        const rs = stmt.executeQuery("SELECT id, name FROM integration_d155 LIMIT 1")
        const md = rs.getMetaData()
        // col 1 — id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PK
        assertEqual(md.getColumnName(1), "id")
        assertEqual(md.getColumnLabel(1), "id")
        assertEqual(md.getColumnType(1), JDBC_TYPE_BIGINT)
        assertEqual(md.getColumnTypeName(1), "BIGINT")
        assertTrue(md.getColumnDisplaySize(1) > 0)
        assertEqual(md.getColumnClassName(1), "java.lang.Long")
        // col 2 — name VARCHAR(64) NOT NULL
        assertEqual(md.getColumnName(2), "name")
        assertEqual(md.getColumnType(2), JDBC_TYPE_VARCHAR)
        assertEqual(md.getColumnTypeName(2), "VARCHAR")
        assertEqual(md.getColumnClassName(2), "java.lang.String")
        rs.close()
        conn.close()
    })

    // ── Case 3 — catalog / schema / table 三态 ───────────────────
    test("Case 3 — getCatalogName='def' / getSchemaName='testdb' / getTableName='integration_d155' (H1 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.createStatement()
        const rs = stmt.executeQuery("SELECT id FROM integration_d155 LIMIT 1")
        const md = rs.getMetaData()
        // MySQL Native Protocol §6.6: catalog field hard-coded "def" by server.
        assertEqual(md.getCatalogName(1), "def")
        assertEqual(md.getSchemaName(1), SCHEMA)
        assertEqual(md.getTableName(1), TABLE)
        rs.close()
        conn.close()
    })

    // ── Case 4 — isNullable 三态 ─────────────────────────────────
    test("Case 4 — isNullable: NOT_NULL → columnNoNulls / nullable → columnNullable (H2 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.createStatement()
        const rs = stmt.executeQuery("SELECT id, qty FROM integration_d155 LIMIT 1")
        const md = rs.getMetaData()
        // col 1 — id BIGINT NOT NULL → NOT_NULL_FLAG bit set → columnNoNulls
        assertEqual(md.isNullable(1), columnNoNulls)
        // col 2 — qty INT (no NOT NULL clause) → NOT_NULL_FLAG unset → columnNullable
        assertEqual(md.isNullable(2), columnNullable)
        rs.close()
        conn.close()
    })

    // ── Case 5 — isAutoIncrement AUTO_INCREMENT_FLAG ─────────────
    test("Case 5 — isAutoIncrement: PK col=1 / 普通 col=0 (H2 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.createStatement()
        const rs = stmt.executeQuery("SELECT id, name FROM integration_d155 LIMIT 1")
        const md = rs.getMetaData()
        // col 1 — id AUTO_INCREMENT_FLAG bit set
        assertEqual(md.isAutoIncrement(1), 1)
        // col 2 — name AUTO_INCREMENT_FLAG bit unset
        assertEqual(md.isAutoIncrement(2), 0)
        rs.close()
        conn.close()
    })

    // ── Case 6 — isSigned UNSIGNED_FLAG ──────────────────────────
    test("Case 6 — isSigned: BIGINT UNSIGNED → 0 / VARCHAR (no UNSIGNED bit) → 1 (H2 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.createStatement()
        const rs = stmt.executeQuery("SELECT id, name FROM integration_d155 LIMIT 1")
        const md = rs.getMetaData()
        // col 1 — id BIGINT UNSIGNED → UNSIGNED_FLAG bit set → isSigned=0
        assertEqual(md.isSigned(1), 0)
        // col 2 — name VARCHAR (UNSIGNED_FLAG not applicable for strings, server emits 0)
        assertEqual(md.isSigned(2), 1)
        rs.close()
        conn.close()
    })

    // ── Case 7 — getPrecision + getScale on DECIMAL(10,2) ────────
    test("Case 7 — getPrecision >= 10 + getScale=2 + colType=DECIMAL on DECIMAL(10,2) (H1 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.createStatement()
        const rs = stmt.executeQuery("SELECT price FROM integration_d155 LIMIT 1")
        const md = rs.getMetaData()
        // MySQL emits column_length = M + 2 = 12 for signed DECIMAL(M, D) by
        // protocol convention. getPrecision returns column_length verbatim
        // (Connector/J 5.1+ same behavior — JDBC §15.4 spec semantics
        // "precision in column_length-equivalent units"). Loose >= 10 bound
        // accepts both signed (12) and unsigned (11) forms across MySQL
        // versions; getScale is exact.
        assertTrue(md.getPrecision(1) >= 10)
        assertEqual(md.getScale(1), 2)
        assertEqual(md.getColumnType(1), JDBC_TYPE_DECIMAL)
        assertEqual(md.getColumnTypeName(1), "DECIMAL")
        rs.close()
        conn.close()
    })

    // ── Case 8 — H7 wire 实证 — close 后 metadata 独立可访问 ──────
    test("Case 8 — ResultSet.close() 后 metadata 独立 ResultSet 生命周期 (H7 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.createStatement()
        const rs = stmt.executeQuery("SELECT id, name FROM integration_d155 LIMIT 1")
        // Cache the metadata reference before close.
        const md1 = rs.getMetaData()
        assertEqual(md1.getColumnCount(), 2)
        rs.close()
        // After close, both:
        //   (a) the cached md1 reference stays usable — metadata holds an
        //       Array<ColumnDef> reference that survives independent of
        //       socket fd (close() drains row packets but does not release
        //       colMetadata)
        //   (b) calling rs.getMetaData() again returns the same lazy-cached
        //       instance (metaDataInited stays 1)
        assertEqual(md1.getColumnName(1), "id")
        assertEqual(md1.getColumnName(2), "name")
        const md2 = rs.getMetaData()
        assertEqual(md2.getColumnCount(), 2)
        assertEqual(md2.getColumnName(1), "id")
        conn.close()
    })

    // ── Case 9 — GeneratedKeyResultSet synthetic 1-col after real INSERT ──
    test("Case 9 — INSERT + getGeneratedKeys + getMetaData synthetic GENERATED_KEY BIGINT (H5 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const stmt = conn.createStatement()
        // Real INSERT (server auto-generates BIGINT UNSIGNED id) +
        // getGeneratedKeys wraps lastInsertId into a single-row, single-column
        // synthetic ResultSet — metadata returned is the synthetic 1-col
        // GENERATED_KEY BIGINT shape hard-coded by Phase 3
        // (lib/com/mysql/query.ss GeneratedKeyResultSet.getMetaData()).
        stmt.executeUpdate("INSERT INTO integration_d155 (name, price, qty, code) VALUES ('rowH5', 39.99, 7, 300)")
        const ks = stmt.getGeneratedKeys()
        const md = ks.getMetaData()
        assertEqual(md.getColumnCount(), 1)
        assertEqual(md.getColumnName(1), "GENERATED_KEY")
        assertEqual(md.getColumnType(1), JDBC_TYPE_BIGINT)
        assertEqual(md.getColumnTypeName(1), "BIGINT")
        assertEqual(md.isAutoIncrement(1), 1)
        assertEqual(md.isNullable(1), columnNoNulls)
        // BIGINT UNSIGNED → UNSIGNED_FLAG set → isSigned=0
        assertEqual(md.isSigned(1), 0)
        ks.close()
        conn.close()
    })

    // ── Case 10 — text vs binary protocol same SELECT same metadata (H6) ──
    test("Case 10 — text(Statement) 与 binary(PreparedStatement)protocol metadata 同字段 (H6 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const sql = "SELECT id, name, price FROM integration_d155 LIMIT 1"

        // Path 1 — text protocol via Statement (COM_QUERY 0x03 → MysqlResultSet)
        const textStmt = conn.createStatement()
        const rsText = textStmt.executeQuery(sql)
        const mdText = rsText.getMetaData()
        const textColCount = mdText.getColumnCount()
        const textCol1Name = mdText.getColumnName(1)
        const textCol1Type = mdText.getColumnType(1)
        const textCol2Name = mdText.getColumnName(2)
        const textCol3TypeName = mdText.getColumnTypeName(3)
        rsText.close()

        // Path 2 — binary protocol via PreparedStatement
        // (COM_STMT_EXECUTE 0x17 → MysqlBinaryResultSet)
        const psBin = conn.prepareStatement(sql)
        const rsBin = psBin.executeQuery()
        const mdBin = rsBin.getMetaData()
        const binColCount = mdBin.getColumnCount()
        const binCol1Name = mdBin.getColumnName(1)
        const binCol1Type = mdBin.getColumnType(1)
        const binCol2Name = mdBin.getColumnName(2)
        const binCol3TypeName = mdBin.getColumnTypeName(3)
        rsBin.close()
        psBin.close()

        // Same SELECT same metadata across both protocols — H6 wire 实证.
        assertEqual(textColCount, binColCount)
        assertEqual(textCol1Name, binCol1Name)
        assertEqual(textCol1Type, binCol1Type)
        assertEqual(textCol2Name, binCol2Name)
        assertEqual(textCol3TypeName, binCol3TypeName)

        conn.close()
    })

    dropAllTables(URL, [TABLE])
    println("All D155 10-shape integration tests passed!")
}
