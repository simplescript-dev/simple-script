// D157 Phase 3 — wire-end e2e integration test (docker probe-skip).
//
// Verifies the MysqlParameterMetaData class real reflection
// (lib/com/mysql/prepared.ss D157 §Phase 2) on an actual MySQL
// 8.0 docker instance — every JDBC §10.2 ParameterMetaData method
// returns spec-aligned values driven by the server's actual
// COM_STMT_PREPARE_OK ParameterDef block (§A.2 H1 wire). Subsumes
// phase1_spike_test.ss (12 case stub stage, NoopParameterMetaData
// dispatch only) + phase2_spike_test.ss (15 case pure-local
// reflection, hand-rolled paramDef bytes only) — both removed in
// this Phase per D157 §Phase 3 absorb decision. lib helper
// (mysqlTypeToJdbcType / mysqlTypeName / mysqlTypeToJavaClassName /
// columnDefColType / columnDefFlags / UNSIGNED_FLAG) preserved.
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the
// test prints a hint and returns 0 so `bin/ss test tests/` stays green
// when docker is unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d157_parameter_metadata/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Uses table `integration_d157` to isolate from D134 (`users`) /
// D147 (`integration_d147`) / D155 (`integration_d155`) / D156
// (`integration_d156_parent`/`_child`) under `bin/ss test tests/`
// parallel batch. Schema:
//   id BIGINT UNSIGNED NOT NULL PRIMARY KEY      (colType 0x08, UNSIGNED_FLAG)
//   name VARCHAR(64)                              (colType 0xFD, utf8mb4)
//   price DECIMAL(10,2)                           (colType 0xF6)
//   qty INT                                       (colType 0x03)
//   binary_col BLOB                               (colType 0xFC, charset 63)
//
// Schema note (root cause): D157 §A.2 H3 锁 single-arg
// `mysqlTypeToJavaClassName(int): string` form (D155 §F5) — colType
// byte alone discriminates binary (0xF9-0xFC/0xFF → "[B") vs text
// (0xFD/0xFE/0x0F → "java.lang.String"). MySQL VARBINARY(N) sends
// wire colType = 0xFD (VAR_STRING) + charset = 63 (binary), so the
// single-arg form returns "java.lang.String" — there is no way to
// distinguish VARBINARY from VARCHAR without a charset-aware
// 2-arg overload (left to a future sub-D, see D155 §F5 + D157
// §A.2 H3). Therefore the binary-path Case 4 here uses BLOB
// (wire colType 0xFC → "[B" via the single-arg form) instead of
// the original VARBINARY(64) sketch — semantic intent (binary →
// byte[]) preserved while staying within H3's locked single-arg
// scope.
//
// Validates D157 §核心目标 §10 + §A.2 H1-H5 wire-end 实证 (9 cases):
//   Case 1 — 3-placeholder INSERT prepare → getParameterCount = 3 (H1 wire)
//   Case 2 — 5-placeholder INSERT → getParameterType per byte 4 case
//            (BIGINT/VARCHAR/DECIMAL/INTEGER) (H1 wire)
//   Case 3 — 5-placeholder INSERT → getParameterTypeName 4 case
//            (BIGINT/VARCHAR/DECIMAL/INT 字面) (H1 wire)
//   Case 4 — 5-placeholder INSERT → getParameterClassName text vs binary
//            (VARCHAR → java.lang.String + BLOB → [B) (H3 wire 单参实证)
//   Case 5 — getParameterMode 全 IN (parameterModeIn=1) (H1 + 静态 IN-only)
//   Case 6 — isNullable 全 Unknown (parameterNullableUnknown=2)
//            (H5 prepare 阶段 server 不解析 SQL placeholder 上下文)
//   Case 7 — isSigned (BIGINT UNSIGNED→0 / INT→1) UNSIGNED_FLAG bit 5
//            反射 (H1 + flags wire)
//   Case 8 — num_params=0 SELECT 1 边界 → getParameterCount=0
//            (H5 边界 — server 不发送 ParameterDef packet)
//   Case 9 — close 后 ParameterMetaData snapshot 仍可访问 (H4 wire snapshot)
//
// See docs/3-decisions/D157-parameter-metadata.md §Phase 收关锚 §Phase 3.

import { test, assertEqual, assertTrue } from "@/lib/test"
import { Connection, PreparedStatement, ParameterMetaData, DriverManager_getConnection, SQLException, JDBC_TYPE_BIGINT, JDBC_TYPE_VARCHAR, JDBC_TYPE_DECIMAL, JDBC_TYPE_INTEGER, parameterModeIn, parameterNullableUnknown } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"
import { dropAllTables } from "@/tests/jdbc/import/jdbc_test_helpers"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"
const TABLE = "integration_d157"
const INSERT3 = "INSERT INTO integration_d157 (id, name, price) VALUES (?, ?, ?)"
const INSERT5 = "INSERT INTO integration_d157 VALUES (?, ?, ?, ?, ?)"
const SELECT0 = "SELECT 1"

function recreateTable(): int {
    const tmpl = new JdbcTemplate(URL)
    tmpl.execute("DROP TABLE IF EXISTS integration_d157")
    tmpl.execute("CREATE TABLE integration_d157 (id BIGINT UNSIGNED NOT NULL PRIMARY KEY, name VARCHAR(64), price DECIMAL(10,2), qty INT, binary_col BLOB) ENGINE=InnoDB")
    return 0
}

function main() {
    // Probe — skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D157 integration: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateTable()

    // ── Case 1 — 3-placeholder INSERT prepare → getParameterCount = 3 (H1 wire) ──
    test("Case 1 — 3-placeholder INSERT prepare → getParameterCount = 3 (H1 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement(INSERT3)
        const pmd = ps.getParameterMetaData()
        assertEqual(pmd.getParameterCount(), 3)
        ps.close()
        conn.close()
    })

    // ── Case 2 — 5-placeholder INSERT → getParameterType per byte (H1 wire) ──
    //
    // §A.2 H3 校准 (Phase 3 wire 实测):MySQL 8.0 server 在 COM_STMT_PREPARE
    // INSERT 阶段对**所有整数列 placeholder** 统一推断为 LONGLONG (0x08
    // BIGINT) — INT (qty) 的具体列宽信息在 ParameterDef colType 中**丢失**,
    // 与 ResultSetMetaData (SELECT ColumnDef 路径) 不同 (那里 colType 反映表
    // 真实定义)。这是 H3 "server 不解析 SQL placeholder 上下文" 的更深层
    // 体现 — 不仅 catalog/schema/table 字段空,colType 对整数族**也降级**为
    // server 默认推断类型;decimal / varchar / blob 不受影响。idx 4 = qty
    // INT 但 wire 返 BIGINT (0x08) 而非 INT (0x03) — 期望按 wire 真值。
    test("Case 2 — 5-placeholder INSERT → getParameterType per byte 4 case (H1 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement(INSERT5)
        const pmd = ps.getParameterMetaData()
        assertEqual(pmd.getParameterCount(), 5)
        // idx 1 = id BIGINT UNSIGNED       → JDBC_TYPE_BIGINT  (-5)  (server colType 0x08)
        // idx 2 = name VARCHAR(64)         → JDBC_TYPE_VARCHAR (12)  (server colType 0xFD)
        // idx 3 = price DECIMAL(10,2)      → JDBC_TYPE_DECIMAL (3)   (server colType 0xF6)
        // idx 4 = qty INT                  → JDBC_TYPE_BIGINT  (-5)  (server upcasts INT → LONGLONG, H3)
        assertEqual(pmd.getParameterType(1), JDBC_TYPE_BIGINT)
        assertEqual(pmd.getParameterType(1), -5)
        assertEqual(pmd.getParameterType(2), JDBC_TYPE_VARCHAR)
        assertEqual(pmd.getParameterType(2), 12)
        assertEqual(pmd.getParameterType(3), JDBC_TYPE_DECIMAL)
        assertEqual(pmd.getParameterType(3), 3)
        assertEqual(pmd.getParameterType(4), JDBC_TYPE_BIGINT)
        assertEqual(pmd.getParameterType(4), -5)
        ps.close()
        conn.close()
    })

    // ── Case 3 — 5-placeholder INSERT → getParameterTypeName 4 case 字面 (H1 wire) ──
    //
    // mysqlTypeName single-arg returns the SQL keyword without UNSIGNED
    // suffix — UNSIGNED is a flags-bit modifier, not a colType byte. idx 4
    // returns "BIGINT" (not "INT") for the same H3 reason as Case 2 — server
    // upcasts INT placeholder to LONGLONG (0x08 → mysqlTypeName "BIGINT").
    test("Case 3 — 5-placeholder INSERT → getParameterTypeName 4 case 字面 (H1 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement(INSERT5)
        const pmd = ps.getParameterMetaData()
        assertEqual(pmd.getParameterTypeName(1), "BIGINT")
        assertEqual(pmd.getParameterTypeName(2), "VARCHAR")
        assertEqual(pmd.getParameterTypeName(3), "DECIMAL")
        assertEqual(pmd.getParameterTypeName(4), "BIGINT")
        ps.close()
        conn.close()
    })

    // ── Case 4 — 5-placeholder INSERT → getParameterClassName text vs binary (H3 wire 单参实证) ──
    test("Case 4 — 5-placeholder INSERT → getParameterClassName text vs binary (H3 wire 单参实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement(INSERT5)
        const pmd = ps.getParameterMetaData()
        // idx 2 = VARCHAR (text colType 0xFD)  → "java.lang.String"
        // idx 5 = BLOB    (binary colType 0xFC) → "[B"
        assertEqual(pmd.getParameterClassName(2), "java.lang.String")
        assertEqual(pmd.getParameterClassName(5), "[B")
        ps.close()
        conn.close()
    })

    // ── Case 5 — getParameterMode 全 IN (parameterModeIn=1) ──
    test("Case 5 — 5-placeholder INSERT → getParameterMode 全 IN (parameterModeIn=1)", () => {
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement(INSERT5)
        const pmd = ps.getParameterMetaData()
        let i = 1
        while (i <= 5) {
            assertEqual(pmd.getParameterMode(i), parameterModeIn)
            assertEqual(pmd.getParameterMode(i), 1)
            i = i + 1
        }
        ps.close()
        conn.close()
    })

    // ── Case 6 — isNullable 全 Unknown (parameterNullableUnknown=2) (H5 静态 mapping) ──
    test("Case 6 — 5-placeholder INSERT → isNullable 全 Unknown (H5 静态 mapping — consumption-side dispatch over wire-instantiated PreparedStatement)", () => {
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement(INSERT5)
        const pmd = ps.getParameterMetaData()
        // server does not resolve SQL placeholder context in COM_STMT_PREPARE
        // — every parameter is parameterNullableUnknown (2). The actual
        // NOT NULL constraint on the `id` column is invisible to the
        // ParameterDef block (vs. the ColumnDef block returned for SELECT).
        let i = 1
        while (i <= 5) {
            assertEqual(pmd.isNullable(i), parameterNullableUnknown)
            assertEqual(pmd.isNullable(i), 2)
            i = i + 1
        }
        ps.close()
        conn.close()
    })

    // ── Case 7 — isSigned UNSIGNED_FLAG bit 5 反射 ──
    test("Case 7 — 5-placeholder INSERT → isSigned UNSIGNED_FLAG bit 5 反射 (H1 + flags wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement(INSERT5)
        const pmd = ps.getParameterMetaData()
        // UNSIGNED_FLAG bit is **preserved** through server's INT→LONGLONG
        // upcast (Case 2 H3 校准) — flags carry over verbatim from the bound
        // column definition even when colType is widened.
        // idx 1 = id BIGINT UNSIGNED → flags & UNSIGNED_FLAG != 0 → 0
        // idx 4 = qty INT (signed)   → flags & UNSIGNED_FLAG == 0 → 1
        assertEqual(pmd.isSigned(1), 0)
        assertEqual(pmd.isSigned(4), 1)
        ps.close()
        conn.close()
    })

    // ── Case 8 — num_params=0 边界 (H5 wire) ──
    test("Case 8 — num_params=0 SELECT 1 边界 → getParameterCount=0 (H5 边界 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement(SELECT0)
        const pmd = ps.getParameterMetaData()
        // server short-circuits: no ParameterDef packets, no EOF, paramDefs=[]
        assertEqual(pmd.getParameterCount(), 0)
        ps.close()
        conn.close()
    })

    // ── Case 9 — close 后 ParameterMetaData snapshot 仍可访问 (H4 wire 实证) ──
    test("Case 9 — close 后 ParameterMetaData snapshot 仍可访问 (H4 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const ps = conn.prepareStatement(INSERT5)
        const pmd = ps.getParameterMetaData()
        // Capture pre-close to make the snapshot intent explicit.
        const preCount = pmd.getParameterCount()
        const preType1 = pmd.getParameterType(1)
        ps.close()
        // Snapshot is value-typed (Array<ColumnDef> ref), no PreparedStatement
        // ref held — every getter still returns the cached real values.
        assertEqual(pmd.getParameterCount(), preCount)
        assertEqual(pmd.getParameterCount(), 5)
        assertEqual(pmd.getParameterType(1), preType1)
        assertEqual(pmd.getParameterType(1), JDBC_TYPE_BIGINT)
        assertEqual(pmd.getParameterClassName(5), "[B")
        conn.close()
    })

    dropAllTables(URL, [TABLE])
    println("All D157 Phase 3 9-shape integration tests passed!")
}
