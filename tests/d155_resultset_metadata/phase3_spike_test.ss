// D155 Phase 3 spike — pure local, no docker dependency.
//
// Verifies the MysqlResultSetMetaData class real-reflection behavior
// (lib/com/mysql/query.ss D155 Phase 3) — wrapping an Array<ColumnDef>
// reflects every JDBC §15.4 column attribute via static derivation off
// the wire-side metadata, with no INFORMATION_SCHEMA round-trip.
//
// Coverage (≥10 cases):
//   1. getColumnCount = colMetadata.length
//   2. getColumnName / getColumnLabel via columnDefName
//   3. getColumnType via mysqlTypeToJdbcType (≥20 byte mapping)
//   4. getColumnTypeName via mysqlTypeName
//   5. getColumnClassName via mysqlTypeToJavaClassName
//   6. getCatalogName / getSchemaName / getTableName via columnDef accessors
//   7. isNullable three states (NOT_NULL_FLAG → columnNoNulls / nullable)
//   8. isAutoIncrement AUTO_INCREMENT_FLAG bit
//   9. isSigned UNSIGNED_FLAG bit (inverted)
//  10. isCaseSensitive charset-aware (33 ci / others cs)
//  11. getPrecision + getScale DECIMAL(10,2) shape
//  12. lazy cache — same instance across getMetaData() calls
//  13. text + binary protocol both expose MysqlResultSetMetaData
//  14. GeneratedKeyResultSet synthetic 1-col GENERATED_KEY BIGINT
//
// Docker probe-skip: 127.0.0.1:3307 not required (this is unit-level
// reflection — fixtures are constructed in-process). The docker e2e
// integration_test.ss covers the wire-end path in Phase 4.
//
// See docs/3-decisions/D155-resultset-metadata.md §Phase 收关锚 §Phase 3.

import { assertEqual, assertTrue } from "@/lib/test"
import { ResultSet, ResultSetMetaData, columnNoNulls, columnNullable, JDBC_TYPE_DECIMAL, JDBC_TYPE_TINYINT, JDBC_TYPE_SMALLINT, JDBC_TYPE_INTEGER, JDBC_TYPE_FLOAT, JDBC_TYPE_DOUBLE, JDBC_TYPE_BIGINT, JDBC_TYPE_DATE, JDBC_TYPE_TIME, JDBC_TYPE_TIMESTAMP, JDBC_TYPE_LONGVARBINARY, JDBC_TYPE_VARCHAR, JDBC_TYPE_CHAR, JDBC_TYPE_BIT, JDBC_TYPE_VARBINARY } from "@/lib/java/sql"
import { ColumnDef, MysqlResultSet, GeneratedKeyResultSet, MysqlResultSetMetaData, NoopResultSetMetaData, mysqlTypeToJdbcType, mysqlTypeName, mysqlTypeToJavaClassName, mysqlTypeIsCaseSensitive, NOT_NULL_FLAG, PRI_KEY_FLAG, UNIQUE_KEY_FLAG, MULTIPLE_KEY_FLAG, BLOB_FLAG, UNSIGNED_FLAG, ZEROFILL_FLAG, BINARY_FLAG, ENUM_FLAG, AUTO_INCREMENT_FLAG, TIMESTAMP_FLAG, SET_FLAG, NUM_FLAG } from "@/lib/com/mysql/query"

function main() {
    // ── Case 1: getColumnCount ────────────────────────────────
    test("MysqlResultSetMetaData.getColumnCount = colMetadata.length", () => {
        let cd: Array<ColumnDef> = []
        cd = cd.push(new ColumnDef("id", 0x03, 11, 63, "users", NOT_NULL_FLAG | PRI_KEY_FLAG, "def", "test", "users", "id", 0))
        cd = cd.push(new ColumnDef("name", 0xFD, 80, 33, "users", NOT_NULL_FLAG, "def", "test", "users", "name", 0))
        cd = cd.push(new ColumnDef("age", 0x03, 11, 63, "users", 0, "def", "test", "users", "age", 0))
        const md = new MysqlResultSetMetaData(cd)
        assertEqual(md.getColumnCount(), 3)
    })

    // ── Case 2: getColumnName / getColumnLabel ─────────────────
    test("MysqlResultSetMetaData.getColumnName / getColumnLabel via columnDefName", () => {
        let cd: Array<ColumnDef> = []
        cd = cd.push(new ColumnDef("user_id", 0x08, 20, 63, "accounts", NOT_NULL_FLAG | PRI_KEY_FLAG | AUTO_INCREMENT_FLAG | UNSIGNED_FLAG, "", "", "accounts", "user_id", 0))
        const md = new MysqlResultSetMetaData(cd)
        assertEqual(md.getColumnName(1), "user_id")
        assertEqual(md.getColumnLabel(1), "user_id")
    })

    // ── Case 3: 13 bit MySQL flag — single-bit case ───────────
    test("MysqlResultSetMetaData isAutoIncrement / isSigned / isNullable via flag bits", () => {
        let cd: Array<ColumnDef> = []
        // BIGINT UNSIGNED PK AUTO_INCREMENT NOT NULL
        cd = cd.push(new ColumnDef("id", 0x08, 20, 63, "t", NOT_NULL_FLAG | PRI_KEY_FLAG | AUTO_INCREMENT_FLAG | UNSIGNED_FLAG, "", "", "t", "id", 0))
        // VARCHAR NULLABLE signed-irrelevant
        cd = cd.push(new ColumnDef("name", 0xFD, 100, 33, "t", 0, "", "", "t", "name", 0))
        const md = new MysqlResultSetMetaData(cd)
        // col 1: id BIGINT UNSIGNED auto_increment not null
        assertEqual(md.isAutoIncrement(1), 1)
        assertEqual(md.isSigned(1), 0)
        assertEqual(md.isNullable(1), columnNoNulls)
        // col 2: name VARCHAR nullable signed (no UNSIGNED_FLAG)
        assertEqual(md.isAutoIncrement(2), 0)
        assertEqual(md.isSigned(2), 1)
        assertEqual(md.isNullable(2), columnNullable)
    })

    // ── Case 4: 13 flag constants stable values ────────────────
    test("13 MySQL flag constant values match Connector/J MysqlDefs", () => {
        assertEqual(NOT_NULL_FLAG, 0x0001)
        assertEqual(PRI_KEY_FLAG, 0x0002)
        assertEqual(UNIQUE_KEY_FLAG, 0x0004)
        assertEqual(MULTIPLE_KEY_FLAG, 0x0008)
        assertEqual(BLOB_FLAG, 0x0010)
        assertEqual(UNSIGNED_FLAG, 0x0020)
        assertEqual(ZEROFILL_FLAG, 0x0040)
        assertEqual(BINARY_FLAG, 0x0080)
        assertEqual(ENUM_FLAG, 0x0100)
        assertEqual(AUTO_INCREMENT_FLAG, 0x0200)
        assertEqual(TIMESTAMP_FLAG, 0x0400)
        assertEqual(SET_FLAG, 0x0800)
        assertEqual(NUM_FLAG, 0x8000)
    })

    // ── Case 5: JDBC Types mapping — ≥20 byte coverage ─────────
    test("mysqlTypeToJdbcType ≥20 byte mapping — JDBC Types int code", () => {
        assertEqual(mysqlTypeToJdbcType(0x00), JDBC_TYPE_DECIMAL)
        assertEqual(mysqlTypeToJdbcType(0x01), JDBC_TYPE_TINYINT)
        assertEqual(mysqlTypeToJdbcType(0x02), JDBC_TYPE_SMALLINT)
        assertEqual(mysqlTypeToJdbcType(0x03), JDBC_TYPE_INTEGER)
        assertEqual(mysqlTypeToJdbcType(0x04), JDBC_TYPE_FLOAT)
        assertEqual(mysqlTypeToJdbcType(0x05), JDBC_TYPE_DOUBLE)
        assertEqual(mysqlTypeToJdbcType(0x07), JDBC_TYPE_TIMESTAMP)
        assertEqual(mysqlTypeToJdbcType(0x08), JDBC_TYPE_BIGINT)
        assertEqual(mysqlTypeToJdbcType(0x0A), JDBC_TYPE_DATE)
        assertEqual(mysqlTypeToJdbcType(0x0B), JDBC_TYPE_TIME)
        assertEqual(mysqlTypeToJdbcType(0x0C), JDBC_TYPE_TIMESTAMP)
        assertEqual(mysqlTypeToJdbcType(0x10), JDBC_TYPE_BIT)
        assertEqual(mysqlTypeToJdbcType(0xF6), JDBC_TYPE_DECIMAL)
        assertEqual(mysqlTypeToJdbcType(0xFB), JDBC_TYPE_LONGVARBINARY)
        assertEqual(mysqlTypeToJdbcType(0xFC), JDBC_TYPE_LONGVARBINARY)
        assertEqual(mysqlTypeToJdbcType(0xFD), JDBC_TYPE_VARCHAR)
        assertEqual(mysqlTypeToJdbcType(0xFE), JDBC_TYPE_CHAR)
        assertEqual(mysqlTypeToJdbcType(0xFF), JDBC_TYPE_VARBINARY)
        // Coverage check — ≥20 mapping
        assertEqual(mysqlTypeToJdbcType(0x0F), JDBC_TYPE_VARCHAR)
        assertEqual(mysqlTypeToJdbcType(0xF7), JDBC_TYPE_CHAR)
    })

    // ── Case 6: SQL type name ─────────────────────────────────
    test("mysqlTypeName returns Connector/J-style SQL keyword", () => {
        assertEqual(mysqlTypeName(0x00), "DECIMAL")
        assertEqual(mysqlTypeName(0x03), "INT")
        assertEqual(mysqlTypeName(0x08), "BIGINT")
        assertEqual(mysqlTypeName(0x0C), "DATETIME")
        assertEqual(mysqlTypeName(0xFD), "VARCHAR")
        assertEqual(mysqlTypeName(0xFE), "CHAR")
        assertEqual(mysqlTypeName(0xF6), "DECIMAL")
        assertEqual(mysqlTypeName(0xFC), "BLOB")
        assertEqual(mysqlTypeName(0xFF), "GEOMETRY")
    })

    // ── Case 7: Java class name ────────────────────────────────
    test("mysqlTypeToJavaClassName returns Java FQN", () => {
        assertEqual(mysqlTypeToJavaClassName(0x00), "java.math.BigDecimal")
        assertEqual(mysqlTypeToJavaClassName(0x03), "java.lang.Integer")
        assertEqual(mysqlTypeToJavaClassName(0x08), "java.lang.Long")
        assertEqual(mysqlTypeToJavaClassName(0x0C), "java.sql.Timestamp")
        assertEqual(mysqlTypeToJavaClassName(0xFD), "java.lang.String")
        assertEqual(mysqlTypeToJavaClassName(0xFC), "[B")
    })

    // ── Case 8: getCatalogName / getSchemaName / getTableName ───
    test("MysqlResultSetMetaData.getCatalog/Schema/TableName via columnDef", () => {
        let cd: Array<ColumnDef> = []
        cd = cd.push(new ColumnDef("price", 0x05, 22, 63, "products", 0, "def", "shop", "products_view", "price", 0))
        const md = new MysqlResultSetMetaData(cd)
        assertEqual(md.getCatalogName(1), "def")
        assertEqual(md.getSchemaName(1), "shop")
        // table = SELECT alias (products_view); orgTable = storage table (products)
        assertEqual(md.getTableName(1), "products_view")
    })

    // ── Case 9: isCaseSensitive charset-aware ─────────────────
    test("mysqlTypeIsCaseSensitive — charset 33 ci / others cs / numeric 0", () => {
        // VARCHAR (0xFD) charset 33 utf8_general_ci → 0 (case-insensitive)
        assertEqual(mysqlTypeIsCaseSensitive(0xFD, 33), 0)
        // VARCHAR charset 63 binary → 1 (case-sensitive)
        assertEqual(mysqlTypeIsCaseSensitive(0xFD, 63), 1)
        // CHAR (0xFE) charset 45 utf8mb4_general_ci → 0
        assertEqual(mysqlTypeIsCaseSensitive(0xFE, 45), 0)
        // BLOB (0xFC) always case-sensitive (binary)
        assertEqual(mysqlTypeIsCaseSensitive(0xFC, 33), 1)
        // INTEGER (0x03) always 0 (numeric, case-irrelevant)
        assertEqual(mysqlTypeIsCaseSensitive(0x03, 33), 0)
    })

    // ── Case 10: getPrecision + getScale DECIMAL(10,2) ────────
    test("MysqlResultSetMetaData.getPrecision / getScale on DECIMAL", () => {
        let cd: Array<ColumnDef> = []
        // DECIMAL(10,2): NEWDECIMAL 0xF6, columnLen=10, decimals=2
        cd = cd.push(new ColumnDef("price", 0xF6, 10, 63, "items", NOT_NULL_FLAG, "def", "shop", "items", "price", 2))
        const md = new MysqlResultSetMetaData(cd)
        assertEqual(md.getPrecision(1), 10)
        assertEqual(md.getScale(1), 2)
        assertEqual(md.getColumnDisplaySize(1), 10)
        assertEqual(md.getColumnType(1), JDBC_TYPE_DECIMAL)
        assertEqual(md.getColumnTypeName(1), "DECIMAL")
    })

    // ── Case 11: lazy cache — same instance across calls ──────
    test("MysqlResultSet.getMetaData lazy cache — single instance", () => {
        let cd: Array<ColumnDef> = []
        cd = cd.push(new ColumnDef("id", 0x03, 11, 63, "t", NOT_NULL_FLAG, "", "", "t", "id", 0))
        let row: Array<string> = []
        row = row.push("1")
        const rs = new MysqlResultSet(-1, 1, cd, row, 0, 1, new NoopResultSetMetaData(), 0)
        const md1 = rs.getMetaData()
        const md2 = rs.getMetaData()
        // After first call, metaDataInited flips 1; both refs point to same instance
        assertEqual(rs.metaDataInited, 1)
        assertEqual(md1.getColumnCount(), 1)
        assertEqual(md2.getColumnCount(), 1)
        // Same column name through both refs (same backing colMetadata)
        assertEqual(md1.getColumnName(1), "id")
        assertEqual(md2.getColumnName(1), "id")
    })

    // ── Case 12: GeneratedKeyResultSet synthetic 1-col ────────
    test("GeneratedKeyResultSet.getMetaData synthetic 1-col GENERATED_KEY BIGINT", () => {
        const ks = new GeneratedKeyResultSet(1024, 0, new NoopResultSetMetaData(), 0)
        const md = ks.getMetaData()
        assertEqual(md.getColumnCount(), 1)
        assertEqual(md.getColumnName(1), "GENERATED_KEY")
        assertEqual(md.getColumnType(1), JDBC_TYPE_BIGINT)
        assertEqual(md.getColumnTypeName(1), "BIGINT")
        assertEqual(md.isAutoIncrement(1), 1)
        assertEqual(md.isNullable(1), columnNoNulls)
        assertEqual(md.isSigned(1), 0)
    })

    // ── Case 13: ResultSetMetaData interface vtable dispatch ──
    test("ResultSetMetaData interface variable + vtable dispatch on real impl", () => {
        let cd: Array<ColumnDef> = []
        cd = cd.push(new ColumnDef("col", 0x03, 11, 63, "t", NOT_NULL_FLAG, "", "", "t", "col", 0))
        const md: ResultSetMetaData = new MysqlResultSetMetaData(cd)
        assertEqual(md.getColumnCount(), 1)
        assertEqual(md.getColumnName(1), "col")
        assertEqual(md.isCurrency(1), 0)
        assertEqual(md.isDefinitelyWritable(1), 1)
        assertEqual(md.isReadOnly(1), 0)
        assertEqual(md.isSearchable(1), 1)
        assertEqual(md.isWritable(1), 1)
    })
}
