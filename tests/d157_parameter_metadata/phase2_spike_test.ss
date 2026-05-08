// D157 Phase 2 spike test — MysqlParameterMetaData class 真实现 + 7 method
// 反射派生 + 复用 D155 mysqlTypeToJdbcType / mysqlTypeName / mysqlTypeToJavaClassName
// + isSigned UNSIGNED_FLAG bit 5 反射 + ParameterMetaData interface vtable dispatch
// + 空 paramDefs num_params=0 边界. Pure-local (no docker), validates §A.2
// H1+H3+H4+H5 接口侧落地; wire 端 docker 实证留 Phase 3 integration_test e2e.
//
// Validates D157 §核心目标 §3 (class MysqlParameterMetaData 真实现) + §8
// (1 implementor 真返) + §核心原则 4-7 (静态 IN-only / 静态 Unknown /
// UNSIGNED_FLAG bit 5 反向 / value snapshot 不持 PreparedStatement ref).
//
// MYSQL_TYPE_xxx byte 码 (Connector/J `MysqlDefs`):
//   0x03 LONG (INT)         0x05 DOUBLE        0x08 LONGLONG (BIGINT)
//   0xF6 NEWDECIMAL         0xF9 TINY_BLOB     0xFD VAR_STRING (VARCHAR)
//
// See docs/3-decisions/D157-parameter-metadata.md §Phase 收关锚 §Phase 2.

import { test, assertEqual, assertTrue } from "@/lib/test"
import { ParameterMetaData, parameterModeIn, parameterNullableUnknown, JDBC_TYPE_INTEGER, JDBC_TYPE_BIGINT, JDBC_TYPE_VARCHAR, JDBC_TYPE_DECIMAL, JDBC_TYPE_DOUBLE } from "@/lib/java/sql"
import { ColumnDef, UNSIGNED_FLAG, NOT_NULL_FLAG } from "@/lib/com/mysql/query"
import { MysqlParameterMetaData } from "@/lib/com/mysql/prepared"

// ColumnDef field order: name, colType, columnLen, charset, orgTable, flags,
// catalog, schema, table, orgName, decimals. ParameterDef block has all string
// fields server-empty in COM_STMT_PREPARE_OK (D157 §A.2 H3 — only colType +
// flags + charset + decimals + columnLen meaningful in prepare phase).
function paramDef(colType: int, flags: int): ColumnDef {
    return new ColumnDef("", colType, 0, 0, "", flags, "", "", "", "", 0)
}

function main() {
    // ── 边界 + 基本反射 ──────────────────────────

    test("Case 1 空 paramDefs num_params=0 边界 — getParameterCount() = 0", () => {
        let empty: Array<ColumnDef> = []
        const pmd = new MysqlParameterMetaData(empty)
        assertEqual(pmd.getParameterCount(), 0)
    })

    test("Case 2 非空 paramDefs — getParameterCount() = paramMetadata.length()", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0x03, 0))
        defs = defs.push(paramDef(0xFD, 0))
        defs = defs.push(paramDef(0x08, 0))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.getParameterCount(), 3)
    })

    // ── getParameterType per type ≥5 byte (复用 D155 mysqlTypeToJdbcType) ──

    test("Case 3 getParameterType MYSQL_TYPE_LONG (0x03) → JDBC_TYPE_INTEGER (4)", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0x03, 0))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.getParameterType(1), JDBC_TYPE_INTEGER)
        assertEqual(pmd.getParameterType(1), 4)
    })

    test("Case 4 getParameterType MYSQL_TYPE_LONGLONG (0x08) → JDBC_TYPE_BIGINT (-5)", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0x08, 0))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.getParameterType(1), JDBC_TYPE_BIGINT)
        assertEqual(pmd.getParameterType(1), -5)
    })

    test("Case 5 getParameterType MYSQL_TYPE_VAR_STRING (0xFD) → JDBC_TYPE_VARCHAR (12)", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0xFD, 0))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.getParameterType(1), JDBC_TYPE_VARCHAR)
        assertEqual(pmd.getParameterType(1), 12)
    })

    test("Case 6 getParameterType MYSQL_TYPE_NEWDECIMAL (0xF6) → JDBC_TYPE_DECIMAL (3)", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0xF6, 0))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.getParameterType(1), JDBC_TYPE_DECIMAL)
        assertEqual(pmd.getParameterType(1), 3)
    })

    test("Case 7 getParameterType MYSQL_TYPE_DOUBLE (0x05) → JDBC_TYPE_DOUBLE (8)", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0x05, 0))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.getParameterType(1), JDBC_TYPE_DOUBLE)
        assertEqual(pmd.getParameterType(1), 8)
    })

    // ── getParameterTypeName ≥5 case (复用 D155 mysqlTypeName) ──

    test("Case 8 getParameterTypeName per byte ≥5 case — INT/BIGINT/VARCHAR/DECIMAL/DOUBLE", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0x03, 0))
        defs = defs.push(paramDef(0x08, 0))
        defs = defs.push(paramDef(0xFD, 0))
        defs = defs.push(paramDef(0xF6, 0))
        defs = defs.push(paramDef(0x05, 0))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.getParameterTypeName(1), "INT")
        assertEqual(pmd.getParameterTypeName(2), "BIGINT")
        assertEqual(pmd.getParameterTypeName(3), "VARCHAR")
        assertEqual(pmd.getParameterTypeName(4), "DECIMAL")
        assertEqual(pmd.getParameterTypeName(5), "DOUBLE")
    })

    // ── getParameterClassName binary vs text 区分 (D157 §A.2 H3 校准 — 单参) ──

    test("Case 9 getParameterClassName VARCHAR text → java.lang.String / TINY_BLOB binary → [B / INT → java.lang.Integer", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0xFD, 0))
        defs = defs.push(paramDef(0xF9, 0))
        defs = defs.push(paramDef(0x03, 0))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.getParameterClassName(1), "java.lang.String")
        assertEqual(pmd.getParameterClassName(2), "[B")
        assertEqual(pmd.getParameterClassName(3), "java.lang.Integer")
    })

    // ── 静态 IN-only / 静态 Unknown ──────────

    test("Case 10 getParameterMode 静态 parameterModeIn = 1 (MySQL prepare 不支持 OUT/INOUT)", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0x03, 0))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.getParameterMode(1), parameterModeIn)
        assertEqual(pmd.getParameterMode(1), 1)
    })

    test("Case 11 isNullable 静态 parameterNullableUnknown = 2 (prepare 阶段 server 不解析 SQL 上下文)", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0x03, 0))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.isNullable(1), parameterNullableUnknown)
        assertEqual(pmd.isNullable(1), 2)
    })

    // ── isSigned UNSIGNED_FLAG bit 5 反射 ≥3 case ──────────

    test("Case 12 isSigned signed (flags=0) → 1 (UNSIGNED bit 5 == 0)", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0x03, 0))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.isSigned(1), 1)
    })

    test("Case 13 isSigned UNSIGNED (flags=UNSIGNED_FLAG=0x0020) → 0", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0x08, UNSIGNED_FLAG))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.isSigned(1), 0)
    })

    test("Case 14 isSigned UNSIGNED + NOT_NULL (flags=0x0021) → 0 (UNSIGNED bit 单独反射,NOT_NULL bit 不影响)", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0x03, UNSIGNED_FLAG | NOT_NULL_FLAG))
        const pmd = new MysqlParameterMetaData(defs)
        assertEqual(pmd.isSigned(1), 0)
    })

    // ── ParameterMetaData interface vtable dispatch ──────────

    test("Case 15 ParameterMetaData interface 变量绑 MysqlParameterMetaData 后 vtable dispatch 全 7 method", () => {
        let defs: Array<ColumnDef> = []
        defs = defs.push(paramDef(0xFD, 0))
        const pmd: ParameterMetaData = new MysqlParameterMetaData(defs)
        assertEqual(pmd.getParameterCount(), 1)
        assertEqual(pmd.getParameterType(1), JDBC_TYPE_VARCHAR)
        assertEqual(pmd.getParameterTypeName(1), "VARCHAR")
        assertEqual(pmd.getParameterClassName(1), "java.lang.String")
        assertEqual(pmd.getParameterMode(1), parameterModeIn)
        assertEqual(pmd.isNullable(1), parameterNullableUnknown)
        assertEqual(pmd.isSigned(1), 1)
    })
}
