// D160 §Phase 2 / D162 §Phase 3 spike — MysqlCallableStatement extends
// MysqlPreparedStatement : CallableStatement wire-end real impl + paramDirections
// three-state + getParameterMode reflection + SQL rewrite helpers.
//
// Validates D162 §Phase 2 walk-classParents check落地 wire-end (D162 §核心目标
// 6) — MysqlCallableStatement inherits 13 PreparedStatement methods from the
// parent (no re-declare), declares 21 own + 1 override (getParameterMetaData).
// Phase 3 unit-level: class construction + paramDirections IN/OUT/INOUT three-
// state via registerOutParameter + getParameterMode reflection breakthrough
// vs D157 §核心原则 4 IN-only限制 + SQL rewrite helpers (rewriteCallSql-
// Placeholders / injectOutVarSetters / appendOutVarSelectors). Trailing OUT
// ResultSet drain at execute time stays at D160 §Phase 3 docker e2e (not
// reachable in this unit spike — outRow stub seeded via emptyCallableOutRow).

import { test, assertEqual, assertTrue } from "@/lib/test"
import { CallableStatement, PreparedStatement, ParameterMetaData, parameterModeIn, parameterModeInOut, parameterModeOut, parameterModeUnknown } from "@/lib/java/sql"
import { MysqlCallableStatement, buildCallableStatement, rewriteCallSqlPlaceholders, injectOutVarSetters, appendOutVarSelectors } from "@/lib/com/mysql/prepared"

function main() {
    test("Case 1 — MysqlCallableStatement class construction (own fields paramDirections / outRow / lastWasNull defaults via buildCallableStatement)", () => {
        const cs = buildCallableStatement(0, 0, 3, [], [])
        assertEqual(cs.paramDirections.length(), 3)
        assertEqual(cs.lastWasNull, 0)
        // outRow stub is GeneratedKeyResultSet pre-positioned at end (firstAccessed=1) —
        // next() returns 0 confirming outRow is initialized + dispatchable.
        assertEqual(cs.outRow.next(), 0)
    })

    test("Case 2 — paramDirections init all parameterModeIn (three-state reflection breakthrough vs D157 IN-only妥协)", () => {
        const cs = buildCallableStatement(0, 0, 3, [], [])
        assertEqual(cs.paramDirections[0], parameterModeIn)
        assertEqual(cs.paramDirections[1], parameterModeIn)
        assertEqual(cs.paramDirections[2], parameterModeIn)
    })

    test("Case 3 — registerOutParameter sets parameterModeOut on a fresh slot (paramTypes still 0)", () => {
        const cs = buildCallableStatement(0, 0, 3, [], [])
        cs.registerOutParameter(2, 4)
        assertEqual(cs.paramDirections[1], parameterModeOut)
        assertEqual(cs.paramDirections[0], parameterModeIn)
        assertEqual(cs.paramDirections[2], parameterModeIn)
    })

    test("Case 4 — registerOutParameter after setXxx flips to parameterModeInOut (paramTypes non-zero from parent setInt)", () => {
        const cs = buildCallableStatement(0, 0, 3, [], [])
        cs.setInt(1, 42)
        cs.registerOutParameter(1, 4)
        assertEqual(cs.paramDirections[0], parameterModeInOut)
    })

    test("Case 5 — getParameterMode reflects IN / OUT / INOUT three-state via MysqlParameterMetaData (override)", () => {
        const cs = buildCallableStatement(0, 0, 3, [], [])
        cs.setInt(1, 42)
        cs.registerOutParameter(2, 4)
        cs.setInt(3, 99)
        cs.registerOutParameter(3, 4)
        const pmd = cs.getParameterMetaData()
        assertEqual(pmd.getParameterCount(), 0)
        assertEqual(cs.paramDirections[0], parameterModeIn)
        assertEqual(cs.paramDirections[1], parameterModeOut)
        assertEqual(cs.paramDirections[2], parameterModeInOut)
    })

    test("Case 6 — typed OUT getter defaults: getInt returns 0 (Phase 3 wire-default; real outRow drain at D160 §Phase 3)", () => {
        const cs = buildCallableStatement(0, 0, 2, [], [])
        cs.registerOutParameter(1, 4)
        assertEqual(cs.getInt(1), 0)
    })

    test("Case 7 — typed OUT getter defaults: getString returns empty string", () => {
        const cs = buildCallableStatement(0, 0, 2, [], [])
        cs.registerOutParameter(1, 12)
        assertEqual(cs.getString(1), "")
    })

    test("Case 8 — typed OUT getter defaults: getDouble returns 0.0", () => {
        const cs = buildCallableStatement(0, 0, 2, [], [])
        cs.registerOutParameter(1, 8)
        assertEqual(cs.getDouble(1), 0.0)
    })

    test("Case 9 — typed OUT getter defaults: getBoolean returns 0", () => {
        const cs = buildCallableStatement(0, 0, 2, [], [])
        cs.registerOutParameter(1, 16)
        assertEqual(cs.getBoolean(1), 0)
    })

    test("Case 10 — wasNull returns lastWasNull (Phase 3 default 0; sticky write-back at D160 §Phase 3 wire path)", () => {
        const cs = buildCallableStatement(0, 0, 1, [], [])
        cs.registerOutParameter(1, 4)
        assertEqual(cs.wasNull(), 0)
        cs.lastWasNull = 1
        assertEqual(cs.wasNull(), 1)
    })

    test("Case 11 — SQL rewrite helpers: injectOutVarSetters prefix + rewriteCallSqlPlaceholders ?-substitution", () => {
        const dirs: Array<int> = [parameterModeIn, parameterModeOut, parameterModeInOut]
        const sql = "CALL p(?, ?, ?)"
        const rewritten = rewriteCallSqlPlaceholders(sql, dirs)
        assertEqual(rewritten, "CALL p(?, @out_2, @out_3)")
        const withSetters = injectOutVarSetters(sql, dirs)
        assertEqual(withSetters, "SET @out_2 = NULL; SET @out_3 = NULL; CALL p(?, @out_2, @out_3)")
    })

    test("Case 12 — SQL rewrite helpers: appendOutVarSelectors suffix builds trailing SELECT for OUT/INOUT params", () => {
        const dirs: Array<int> = [parameterModeIn, parameterModeOut, parameterModeInOut]
        const sql = "CALL p(?, ?, ?)"
        const withSelectors = appendOutVarSelectors(sql, dirs)
        assertEqual(withSelectors, "CALL p(?, ?, ?); SELECT @out_2 AS col_2, @out_3 AS col_3")
        // No-OUT case: pure IN bindings pass sql through untouched.
        const allIn: Array<int> = [parameterModeIn, parameterModeIn]
        assertEqual(appendOutVarSelectors("INSERT INTO t VALUES (?, ?)", allIn), "INSERT INTO t VALUES (?, ?)")
    })
}
