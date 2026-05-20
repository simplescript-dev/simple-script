// D165 Phase 1 minimum repro 隔离 spike — root cause 3a INOUT IN-inject 缺失 +
// root cause 3b PMD paramDirections 反射 corruption 双根因 isolate.
//
// 实证策略(双根因切片 spike):
//   Case A — INOUT path docker probe-skip(同 d160 integration_test Case 3 同形)
//            docker 在线时 RED expected 15 got 0,docker 离线 skip GREEN
//            实证 root cause 3a:lib/com/mysql/prepared.ss MysqlCallableStatement.execute()
//            line 1659-1709 漏 inject INOUT IN value 至 server session var
//            (无 COM_QUERY `SET @out_<i> := <inValue>` 多语句 inject pre sendComStmtPrepare)
//   Case B — PMD reflection 真实形态本地 spike(无 docker)
//            buildCallableStatement(0, 0, 3, paramDefs, columnDefs, sql) +
//            setInt + registerOutParameter 三态 + getParameterMetaData →
//            pmd.getParameterMode 反射 真值 1, 4, 2 实测 GREEN
//            实证 H2 假设修正:corruption 不在简单 buildCallableStatement +
//            setInt/register 应用层路径触发,真实 d160 8 case Case 5 实测 corruption
//            262147 = 0x40003 = (parameterModeOut << 16) | numParams 触发条件依赖
//            conn.prepareCall wire 路径副作用 / wire 路径 ColumnDef RC retain
//            timing / wire 路径多 packet readParamDef 时序某 corner case → 留 §F2
//   Case C — 三态 mode 双 bug 联动 docker probe-skip(同 d160 integration_test
//            Case 5 同形)docker 在线时 RED pmd.getParameterMode(2) expected 4
//            got 262147(0x40003 — non-garbage structured corruption)
//            docker 离线 skip GREEN — 实证 root cause 3b 在 wire 路径触发
//   Case D — multi round register + 多次 reflect 本地 spike(无 docker)
//            尝试触发 alias-write + share-by-ref 多次 round 路径 corruption
//            若仍 GREEN — 实证 H2 完全破裂,corruption 触发条件极其特殊
//
// LLVM IR inspect 锚(Phase 1 实证锚 + Phase 2 修法 target 锁定):
//   ── root cause 3a (INOUT IN-inject 缺失) ──
//     `bin/ss build phase1_repro_spike_test.ss --emit-ir -o /tmp/d165_spike`
//     execute() generated IR 检查 — 无 emit COM_QUERY `SET @out_<i> := <IN value>`
//     pre sendComStmtPrepare,与 lib/com/mysql/prepared.ss:1659-1709 源码一致:
//       sendComStmtPrepare(this.fd, rewritten)  ← 直接 prepare,无 IN inject
//       readPrepareOk + readParamDef + readColumnDefList(server allocates)
//       sendComStmtExecute(filtered inTypes/Values, ...)  ← server stmt num_params=0
//       readUpdateResultPacket  ← server CALL p1=NULL*3=NULL → @out_<i>=NULL
//     Phase 2 修法 target = lib/com/mysql/prepared.ss:1659-1709 execute() 内
//       sendComStmtPrepare 之前(line 1692)加 INOUT IN-inject 多语句 SET @out_<i>:
//         扫 paramDirections,对每 INOUT idx 发 sendQuery `SET @out_<i> := <inValue>`
//         (单语句 simple,multi-statement multi-step 皆可,JDBC Connector/J 8.x 同形)
//       LOC 估 +5~+15
//   ── root cause 3b (PMD paramDirections corruption) ──
//     PMD constructor IR + getParameterMode IR 检查 — paramDirections share-by-ref
//     GEP offset / RC retain / deep_clone 路径在简单 spike 与真实 wire 路径差异
//     Phase 2 修法 target = 待 Phase 1 spike 完整 LLVM IR inspect + 真实 docker
//       8 case 在线侧 trace 比对后锁定;若是应用层 bug,target = lib/com/mysql/
//       prepared.ss MysqlParameterMetaData getParameterMode / MysqlCallableStatement
//       getParameterMetaData(LOC 估 +1~+10);若是编译器层 bug,target =
//       bootstrap/gen child class own Array<int> field codegen / RC 修法
//       与 D162 §F7 / D163 §Phase 2 / D164 §Phase 2 修法系列同源(LOC 估 +1~+30)
//
// 守护:Case B/D 在本地实测 GREEN — 验证不破 D162 §F7 / D163 §Phase 2 / D164
// §Phase 2 修法系列;Case A/C docker 在线侧验证不破 d160 §Phase 3 wire path 已
// GREEN 的 Case 1/2/4/6/7/8(6 case PASS 守护 — d160 integration_test 同 spike
// scope 但角度不同:integration_test 全 8 case 验证;本 spike 仅 Case 3+5 RED 路径
// 隔离)。
//
// 见 docs/3-decisions/D165-d160-callable-statement-inout-pmd-bug.md §Phase 收关锚 §Phase 1.

import { test, assertEqual, assertTrue } from "@/lib/test"
import { Connection, CallableStatement, ParameterMetaData, DriverManager_getConnection, SQLException, JDBC_TYPE_INTEGER, parameterModeIn, parameterModeOut, parameterModeInOut } from "@/lib/java/sql"
import { JdbcTemplate } from "@/lib/spring/jdbc"
import { ColumnDef } from "@/lib/com/mysql/query"
import { buildCallableStatement } from "@/lib/com/mysql/prepared"
import { dropAllProcs } from "@/tests/jdbc/import/jdbc_test_helpers"

const URL = "jdbc:mysql://root:test@127.0.0.1:3307/testdb"

const PROC_NAMES: Array<string> = ["proc_d165_inout", "proc_d165_three_modes"]

function recreateAllProcs() {
    const tmpl = new JdbcTemplate(URL)
    dropAllProcs(URL, PROC_NAMES)
    tmpl.execute("CREATE PROCEDURE proc_d165_inout(INOUT p1 INT) BEGIN SET p1 = p1 * 3; END")
    tmpl.execute("CREATE PROCEDURE proc_d165_three_modes(IN p1 INT, OUT p2 INT, INOUT p3 INT) BEGIN SET p2 = p1; SET p3 = p3 + p1; END")
}

function makeFakeParamDefs(n: int): Array<ColumnDef> {
    let defs: Array<ColumnDef> = []
    let i = 0
    while (i < n) {
        defs = defs.push(new ColumnDef("?", 8, 21, 63, "", 128, "def", "", "", "?", 0))
        i = i + 1
    }
    return defs
}

function probeDockerOnline(): int {
    try {
        const probe = DriverManager_getConnection(URL)
        probe.close()
        return 1
    } catch (e: SQLException) {
        return 0
    }
}

function main() {
    const dockerOnline = probeDockerOnline()

    if (dockerOnline == 0) {
        println("D165 Phase 1 spike: 127.0.0.1:3307 unreachable — Case A + Case C 跳过(docker probe-skip).")
        println("   start: docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait")
    } else {
        recreateAllProcs()
    }

    // ── Case A — INOUT path docker probe-skip(同 d160 integration_test Case 3 同形 — root cause 3a)──
    test("D165 Case A — INOUT setInt(1,5) + register(1,INT) + executeUpdate + getInt(1) expected 15 (root cause 3a INOUT IN-inject 缺失 — docker probe-skip)", () => {
        if (dockerOnline != 0) {
            const conn = DriverManager_getConnection(URL)
            const cs = conn.prepareCall("CALL proc_d165_inout(?)")
            cs.setInt(1, 5)
            cs.registerOutParameter(1, JDBC_TYPE_INTEGER)
            cs.executeUpdate()
            // RED: docker 在线 expected 15 got 0(server CALL p1 = NULL * 3 = NULL → @out_1 = NULL → drain getInt = 0)
            // Phase 2 修法 wire 落地后 GREEN(execute() 加 INOUT IN-inject SET @out_1 := 5 pre sendComStmtPrepare)
            assertEqual(cs.getInt(1), 15)
            cs.close()
            conn.close()
        }
    })

    // ── Case B — PMD reflection 真实形态本地 spike(无 docker — 验 H2 假设修正)──
    test("D165 Case B — buildCallableStatement(0,0,3,paramDefs,columnDefs,sql) + setInt + register 三态 + pmd.getParameterMode 真值 1/4/2(本地无 docker — 验 H2 corruption 不在简单应用层 path 触发)", () => {
        const paramDefs = makeFakeParamDefs(3)
        let columnDefs: Array<ColumnDef> = []
        const cs = buildCallableStatement(0, 0, 3, paramDefs, columnDefs, "CALL proc_d165_three_modes(?, ?, ?)")
        cs.setInt(1, 4)
        cs.registerOutParameter(2, JDBC_TYPE_INTEGER)
        cs.setInt(3, 100)
        cs.registerOutParameter(3, JDBC_TYPE_INTEGER)
        const pmd = cs.getParameterMetaData()
        // 期望:dirs = [parameterModeIn=1, parameterModeOut=4, parameterModeInOut=2]
        // 实测本地 GREEN — corruption 不在简单 buildCallableStatement + setInt/register 应用层路径触发
        assertEqual(pmd.getParameterMode(1), parameterModeIn)
        assertEqual(pmd.getParameterMode(2), parameterModeOut)
        assertEqual(pmd.getParameterMode(3), parameterModeInOut)
    })

    // ── Case C — 三态 mode 双 bug 联动 docker probe-skip(同 d160 integration_test Case 5 同形 — root cause 3b)──
    test("D165 Case C — setInt + register + setInt + register + pmd.getParameterMode(2) expected 4 (root cause 3b PMD paramDirections corruption — docker probe-skip)", () => {
        if (dockerOnline != 0) {
            const conn = DriverManager_getConnection(URL)
            const cs = conn.prepareCall("CALL proc_d165_three_modes(?, ?, ?)")
            cs.setInt(1, 4)
            cs.registerOutParameter(2, JDBC_TYPE_INTEGER)
            cs.setInt(3, 100)
            cs.registerOutParameter(3, JDBC_TYPE_INTEGER)
            const pmd = cs.getParameterMetaData()
            // RED: docker 在线 pmd.getParameterMode(2) expected 4 got 262147 (0x40003 — non-garbage structured corruption)
            // 0x40003 = (parameterModeOut << 16) | numParams
            // Phase 2 修法 wire 落地后 GREEN(应用层或编译器层修法待 Phase 1 LLVM IR inspect + 在线 trace 比对锁定)
            assertEqual(pmd.getParameterMode(1), parameterModeIn)
            assertEqual(pmd.getParameterMode(2), parameterModeOut)
            assertEqual(pmd.getParameterMode(3), parameterModeInOut)
            cs.close()
            conn.close()
        }
    })

    // ── Case D — multi round register/reflect 本地 spike(无 docker)──
    test("D165 Case D — buildCallableStatement + 多 round register + 多次 getParameterMetaData reflect (无 docker — 尝试触发 alias-write + share-by-ref corruption)", () => {
        const paramDefs = makeFakeParamDefs(3)
        let columnDefs: Array<ColumnDef> = []
        const cs = buildCallableStatement(0, 0, 3, paramDefs, columnDefs, "CALL proc_d165_three_modes(?, ?, ?)")
        cs.setInt(1, 4)
        cs.registerOutParameter(2, JDBC_TYPE_INTEGER)
        const pmd1 = cs.getParameterMetaData()
        cs.setInt(3, 100)
        cs.registerOutParameter(3, JDBC_TYPE_INTEGER)
        const pmd2 = cs.getParameterMetaData()
        // pmd1 reflects [1, 4, 1] state(仅 dirs[1]=OUT,dirs[2] 仍 IN)
        // pmd2 reflects [1, 4, 2] state(dirs[2]=INOUT 因 setInt(3) flipped paramTypes[2] 非 0)
        // share-by-ref 校验:pmd1.paramDirections 与 pmd2.paramDirections 同源 alias
        // 故 pmd1 reflect 也应等于 pmd2(reflect 时点不冻结状态)
        assertEqual(pmd1.getParameterMode(1), parameterModeIn)
        assertEqual(pmd1.getParameterMode(2), parameterModeOut)
        assertEqual(pmd1.getParameterMode(3), parameterModeInOut)
        assertEqual(pmd2.getParameterMode(1), parameterModeIn)
        assertEqual(pmd2.getParameterMode(2), parameterModeOut)
        assertEqual(pmd2.getParameterMode(3), parameterModeInOut)
    })

    if (dockerOnline != 0) {
        dropAllProcs(URL, PROC_NAMES)
    }
    println("D165 Phase 1 spike done.")
}
