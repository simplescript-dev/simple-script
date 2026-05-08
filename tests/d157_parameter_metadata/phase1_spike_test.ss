// D157 Phase 1 spike test — interface ParameterMetaData ≥7 method +
// PreparedStatement.getParameterMetaData() 接口加 + NoopParameterMetaData
// stub class + 7 JDBC §10.2 静态常量. Pure-local (no docker), validates
// the接口层 trap landed before Phase 2 wires MysqlParameterMetaData真实现.
//
// Validates D157 §核心目标 §1-§3 + §6 (JDBC §10.2 接口与常量) + §核心原则
// 4-5 (ParameterMode 静态 IN-only / isNullable 静态 Unknown). Phase 2 spike
// covers MysqlParameterMetaData reflection (D157 §A.2 H1+H3+H4+H5), Phase 3
// integration_test e2e wires docker probe-skip H1-H5 wire end实证.
//
// See docs/3-decisions/D157-parameter-metadata.md §Phase 收关锚 §Phase 1.

import { test, assertEqual, assertTrue } from "@/lib/test"
import { ParameterMetaData, parameterModeIn, parameterModeInOut, parameterModeOut, parameterModeUnknown, parameterNullable, parameterNoNulls, parameterNullableUnknown } from "@/lib/java/sql"
import { NoopParameterMetaData } from "@/lib/com/mysql/prepared"

function main() {
    // ── 7 NoopParameterMetaData method dispatch ──────────

    test("Case 1 NoopParameterMetaData.getParameterCount() returns 0", () => {
        const pmd = new NoopParameterMetaData()
        assertEqual(pmd.getParameterCount(), 0)
    })

    test("Case 2 NoopParameterMetaData.getParameterType(idx) returns 0", () => {
        const pmd = new NoopParameterMetaData()
        assertEqual(pmd.getParameterType(1), 0)
    })

    test("Case 3 NoopParameterMetaData.getParameterTypeName(idx) returns \"\"", () => {
        const pmd = new NoopParameterMetaData()
        assertEqual(pmd.getParameterTypeName(1), "")
    })

    test("Case 4 NoopParameterMetaData.getParameterClassName(idx) returns \"\"", () => {
        const pmd = new NoopParameterMetaData()
        assertEqual(pmd.getParameterClassName(1), "")
    })

    test("Case 5 NoopParameterMetaData.getParameterMode(idx) returns parameterModeUnknown (0)", () => {
        const pmd = new NoopParameterMetaData()
        assertEqual(pmd.getParameterMode(1), parameterModeUnknown)
        assertEqual(pmd.getParameterMode(1), 0)
    })

    test("Case 6 NoopParameterMetaData.isNullable(idx) returns parameterNullableUnknown (2)", () => {
        const pmd = new NoopParameterMetaData()
        assertEqual(pmd.isNullable(1), parameterNullableUnknown)
        assertEqual(pmd.isNullable(1), 2)
    })

    test("Case 7 NoopParameterMetaData.isSigned(idx) returns 0 (unknown signedness)", () => {
        const pmd = new NoopParameterMetaData()
        assertEqual(pmd.isSigned(1), 0)
    })

    // ── 7 JDBC §10.2 静态常量 literal cases ──────────

    test("Case 8 parameterModeIn = 1 (JDBC §10.2 spec)", () => {
        assertEqual(parameterModeIn, 1)
    })

    test("Case 9 parameterModeInOut = 2 / parameterModeOut = 4 / parameterModeUnknown = 0", () => {
        assertEqual(parameterModeInOut, 2)
        assertEqual(parameterModeOut, 4)
        assertEqual(parameterModeUnknown, 0)
    })

    test("Case 10 parameterNullable = 1 / parameterNoNulls = 0 / parameterNullableUnknown = 2", () => {
        assertEqual(parameterNullable, 1)
        assertEqual(parameterNoNulls, 0)
        assertEqual(parameterNullableUnknown, 2)
    })

    // ── ParameterMetaData interface vtable dispatch ──────────

    test("Case 11 ParameterMetaData interface 变量绑 NoopParameterMetaData 后 vtable dispatch", () => {
        const pmd: ParameterMetaData = new NoopParameterMetaData()
        assertEqual(pmd.getParameterCount(), 0)
        assertEqual(pmd.getParameterType(1), 0)
        assertEqual(pmd.getParameterTypeName(1), "")
        assertEqual(pmd.getParameterClassName(1), "")
        assertEqual(pmd.getParameterMode(1), 0)
        assertEqual(pmd.isNullable(1), 2)
        assertEqual(pmd.isSigned(1), 0)
    })

    test("Case 12 NoopParameterMetaData stateless — multiple instances independent", () => {
        const a = new NoopParameterMetaData()
        const b = new NoopParameterMetaData()
        assertEqual(a.getParameterCount(), b.getParameterCount())
        assertEqual(a.getParameterMode(1), b.getParameterMode(2))
        assertTrue(a.getParameterCount() == 0)
        assertTrue(b.getParameterCount() == 0)
    })
}
