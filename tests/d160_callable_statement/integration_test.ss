// D160 Phase 3 — wire-end e2e integration test (docker probe-skip).
//
// Verifies the MysqlCallableStatement class real wire path
// (lib/com/mysql/prepared.ss D160 §Phase 3): JDBC §13.x
// `prepareCall(sql)` + registerOutParameter + binary execute + COM_QUERY
// trailing OUT drain + typed OUT getter reflection on an actual MySQL
// 8.0 docker instance. Subsumes phase1_spike_test.ss (12 case stub
// stage, NoopCallableStatement dispatch only) + phase2_spike_test.ss
// (12 case pure-local reflection, paramDirections + SQL rewrite
// helpers) — both removed in this Phase per D160 §Phase 3 absorb
// decision (D162 §Phase 3 already wires the rewrite helpers + class
// scaffolding; this Phase wires the execute drain + typed getter
// reflection).
//
// Probes 127.0.0.1:3307 first; if testss-mysql is not reachable the
// test prints a hint and returns 0 so `bin/ss test tests/` stays green
// when docker is unavailable. To run the full suite:
//   docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait
//   bin/ss test tests/d160_callable_statement/
//   docker compose -f tests/d134_mysql/docker-compose.yml down -v
//
// Uses procedure name prefix `proc_d160_*` to isolate from D134 / D147
// / D155 / D156 / D157 under the parallel `bin/ss test tests/` batch.
//
// Validates D160 §核心目标 §10 + §A.2 H1, H3, H4, H5 wire-end (8
// cases). H2 (multi-RS round-trip + SERVER_MORE_RESULTS_EXISTS bit 8
// for procedure body containing SELECT) is left to D160 §F8 sub-D —
// the Phase 3 wire path uses the binary execute + standalone COM_QUERY
// `SELECT @out_<i>` drain (Connector/J's no-multi-RS fallback) and
// procedures here have no body SELECT.
//   Case 1 — prepareCall + getParameterCount = 2 (H1 wire)
//   Case 2 — OUT INTEGER getInt 真值反射 = 20 (H4 wire)
//   Case 3 — INOUT setInt + registerOutParameter + getInt 真值反射 = 15 (H4 wire)
//   Case 4 — multi OUT 多参 reflect: getInt(2)=14 + getInt(3)=21 (H4 wire)
//   Case 5 — getParameterMode 三态 IN/OUT/INOUT 真值 (H3 wire)
//   Case 6 — getString OUT VARCHAR reflect = "hello" (H4 + multi-type)
//   Case 7 — getDouble OUT DOUBLE reflect ≈ 3.14 (H4 + multi-type)
//   Case 8 — wasNull SQL NULL: getInt=0 + wasNull()=1 (H4 + null sentinel)
//
// See docs/3-decisions/D160-callable-statement-out-inout.md §Phase 收关锚 §Phase 3.

import { test, assertEqual, assertTrue } from "@/lib/test"
import { Connection, CallableStatement, ParameterMetaData, DriverManager_getConnection, SQLException, JDBC_TYPE_INTEGER, JDBC_TYPE_VARCHAR, JDBC_TYPE_DOUBLE, parameterModeIn, parameterModeOut, parameterModeInOut } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"
import { dropAllProcs } from "@/tests/jdbc/import/jdbc_test_helpers"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"

// Procedure name registry — single source of truth for setup/teardown
// drops, recreate bodies stay inline since each procedure body differs.
const PROC_NAMES: Array<string> = ["proc_d160_double", "proc_d160_inout", "proc_d160_three_modes", "proc_d160_multi_out", "proc_d160_string_out", "proc_d160_double_out", "proc_d160_null_out"]

function recreateAllProcs() {
    const tmpl = new JdbcTemplate(URL)
    dropAllProcs(URL, PROC_NAMES)
    tmpl.execute("CREATE PROCEDURE proc_d160_double(IN p1 INT, OUT p2 INT) BEGIN SET p2 = p1 * 2; END")
    tmpl.execute("CREATE PROCEDURE proc_d160_inout(INOUT p1 INT) BEGIN SET p1 = p1 * 3; END")
    tmpl.execute("CREATE PROCEDURE proc_d160_three_modes(IN p1 INT, OUT p2 INT, INOUT p3 INT) BEGIN SET p2 = p1; SET p3 = p3 + p1; END")
    tmpl.execute("CREATE PROCEDURE proc_d160_multi_out(IN p1 INT, OUT p2 INT, OUT p3 INT) BEGIN SET p2 = p1 * 2; SET p3 = p1 * 3; END")
    tmpl.execute("CREATE PROCEDURE proc_d160_string_out(OUT p1 VARCHAR(64)) BEGIN SET p1 = 'hello'; END")
    tmpl.execute("CREATE PROCEDURE proc_d160_double_out(OUT p1 DOUBLE) BEGIN SET p1 = 3.14; END")
    tmpl.execute("CREATE PROCEDURE proc_d160_null_out(OUT p1 INT) BEGIN SET p1 = NULL; END")
}

function main() {
    // Probe — skip the file (return 0) when 127.0.0.1:3307 is not reachable.
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
    } catch (e: SQLException) {
        println("D160 integration: 127.0.0.1:3307 unreachable — skip.")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
        return
    }

    recreateAllProcs()

    // ── Case 1 — prepareCall + getParameterCount = 2 (H1 wire 实证) ──
    test("Case 1 — prepareCall(CALL proc_d160_double(?, ?)) + getParameterCount = 2 (H1 wire 实证)", () => {
        const conn = DriverManager_getConnection(URL)
        const cs = conn.prepareCall("CALL proc_d160_double(?, ?)")
        const pmd = cs.getParameterMetaData()
        assertEqual(pmd.getParameterCount(), 2)
        cs.close()
        conn.close()
    })

    // ── Case 2 — OUT INTEGER 真值反射 = 20 (H4 wire 实证) ──
    test("Case 2 — registerOutParameter + setInt + execute + getInt(2) = 20 (H4 OUT wire 真值反射)", () => {
        const conn = DriverManager_getConnection(URL)
        const cs = conn.prepareCall("CALL proc_d160_double(?, ?)")
        cs.setInt(1, 10)
        cs.registerOutParameter(2, JDBC_TYPE_INTEGER)
        cs.executeUpdate()
        assertEqual(cs.getInt(2), 20)
        cs.close()
        conn.close()
    })

    // ── Case 3 — INOUT setInt + register + getInt = 15 (H4 wire 实证) ──
    test("Case 3 — INOUT setInt(1,5) + registerOutParameter(1,INT) + execute + getInt(1) = 15 (H4 INOUT wire 真值反射)", () => {
        const conn = DriverManager_getConnection(URL)
        const cs = conn.prepareCall("CALL proc_d160_inout(?)")
        cs.setInt(1, 5)
        cs.registerOutParameter(1, JDBC_TYPE_INTEGER)
        cs.executeUpdate()
        assertEqual(cs.getInt(1), 15)
        cs.close()
        conn.close()
    })

    // ── Case 4 — multi OUT 多参 reflect (H4 wire 实证) ──
    test("Case 4 — multi OUT params: setInt(1,7) + register(2,3) + getInt(2)=14 + getInt(3)=21 (H4 multi-OUT wire 真值反射)", () => {
        const conn = DriverManager_getConnection(URL)
        const cs = conn.prepareCall("CALL proc_d160_multi_out(?, ?, ?)")
        cs.setInt(1, 7)
        cs.registerOutParameter(2, JDBC_TYPE_INTEGER)
        cs.registerOutParameter(3, JDBC_TYPE_INTEGER)
        cs.executeUpdate()
        assertEqual(cs.getInt(2), 14)
        assertEqual(cs.getInt(3), 21)
        cs.close()
        conn.close()
    })

    // ── Case 5 — getParameterMode 三态 (H3 wire 实证) ──
    // Order matters: setInt(3, 100) BEFORE registerOutParameter(3, INTEGER) flips
    // paramDirections[2] to INOUT (registerOutParameter sees paramTypes[2] != 0
    // from setInt's bind, so it picks parameterModeInOut over parameterModeOut).
    // idx=2 takes the OUT-only path (no setXxx beforehand); idx=1 stays IN.
    test("Case 5 — getParameterMode(1)=IN + (2)=OUT + (3)=INOUT 三态真值反射 (H3 wire 实证 — 突破 D157 静态 IN-only)", () => {
        const conn = DriverManager_getConnection(URL)
        const cs = conn.prepareCall("CALL proc_d160_three_modes(?, ?, ?)")
        cs.setInt(1, 4)
        cs.registerOutParameter(2, JDBC_TYPE_INTEGER)
        cs.setInt(3, 100)
        cs.registerOutParameter(3, JDBC_TYPE_INTEGER)
        const pmd = cs.getParameterMetaData()
        assertEqual(pmd.getParameterMode(1), parameterModeIn)
        assertEqual(pmd.getParameterMode(2), parameterModeOut)
        assertEqual(pmd.getParameterMode(3), parameterModeInOut)
        cs.executeUpdate()
        assertEqual(cs.getInt(2), 4)
        assertEqual(cs.getInt(3), 104)
        cs.close()
        conn.close()
    })

    // ── Case 6 — getString OUT VARCHAR (H4 + multi-type) ──
    test("Case 6 — getString(1) OUT VARCHAR reflect = 'hello' (H4 + multi-type OUT getter)", () => {
        const conn = DriverManager_getConnection(URL)
        const cs = conn.prepareCall("CALL proc_d160_string_out(?)")
        cs.registerOutParameter(1, JDBC_TYPE_VARCHAR)
        cs.executeUpdate()
        assertEqual(cs.getString(1), "hello")
        cs.close()
        conn.close()
    })

    // ── Case 7 — getDouble OUT DOUBLE (H4 + multi-type) ──
    test("Case 7 — getDouble(1) OUT DOUBLE reflect ≈ 3.14 (H4 + multi-type OUT getter)", () => {
        const conn = DriverManager_getConnection(URL)
        const cs = conn.prepareCall("CALL proc_d160_double_out(?)")
        cs.registerOutParameter(1, JDBC_TYPE_DOUBLE)
        cs.executeUpdate()
        const v = cs.getDouble(1)
        assertTrue(v > 3.13)
        assertTrue(v < 3.15)
        cs.close()
        conn.close()
    })

    // ── Case 8 — wasNull SQL NULL sentinel (H4 + null-aware) ──
    // Limitation: text-protocol getString returns "" for both SQL NULL
    // (server sends 0xFB length prefix) and an actual empty string —
    // so wasNull() conflates them. A real driver distinguishes via the
    // wire-level NULL marker; routing it through the typed getter is
    // left to D160 §F (future SQLException + NULL-marker passthrough).
    test("Case 8 — getInt(1) on SQL NULL OUT + wasNull()=1 (H4 + null sentinel)", () => {
        const conn = DriverManager_getConnection(URL)
        const cs = conn.prepareCall("CALL proc_d160_null_out(?)")
        cs.registerOutParameter(1, JDBC_TYPE_INTEGER)
        cs.executeUpdate()
        assertEqual(cs.getInt(1), 0)
        assertEqual(cs.wasNull(), 1)
        cs.close()
        conn.close()
    })

    dropAllProcs(URL, PROC_NAMES)
    println("All D160 Phase 3 8-shape integration tests passed!")
}
