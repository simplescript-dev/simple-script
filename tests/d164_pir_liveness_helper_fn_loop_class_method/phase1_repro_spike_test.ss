// D164 Phase 1 PIR liveness helper fn + loop body + class.method bug 复现 spike
//
// 实测 RED-as-spike 范式:本 spike 现状 assertEqual 失败(运行时 mimalloc double free
// + 部分 case UAF 致 garbage / abort),Phase 2 编译器层 PIR liveness 修法落地后重跑全 GREEN。
// 起首:D163 §Phase 2 codegen MEMBER_ACCESS 类型解析修法 wire 落地(commit `ae16073`)后
// D160 §Phase 4 wire 真值反射重启实测 8 case 仍 segfault → /tmp/d160_t18.ss 17 行最小 repro
// 揭露独立 root cause #2 = PIR liveness 在 helper fn + while loop ≥ 2 次 + class.method 模式
// 下误标 last-use 在 while body 内,每次循环 ss_drop class instance,第 2 次循环 use-after-free
// (复杂 class)/ mimalloc double free(简单 class)。
//
// **Phase 1 LLVM IR inspect 实测真根因**(对比 helper fn 路径 vs main 路径同样代码 IR 差异):
// 最小 repro `/tmp/d164_min.ss`(13 行 helper fn + while loop + class.method):
//   - helper fn `loopHelper()` IR(d164_min.ll line 5182-5208):
//       while.body.154:
//         %6 = load ptr, ptr %box.79, align 8
//         %7 = call i32 @TestBoxD164_getVal(ptr %6)
//         %8 = load ptr, ptr %box.79, align 8
//         call void @ss_drop_TestBoxD164(ptr %8)   ← BUG: drop 在 while.body 内
//         %9 = load i32, ptr %i.80, align 8
//         ...
//         br label %while.cond.153
//       while.after.155:
//         call void @ss_println(ptr @.str.81)
//         ret void                                 ← while.after 块外没有 drop
// 实测运行 `bin/ss run /tmp/d164_min.ss` stderr 输出:
//   mimalloc: error: double free detected of block 0x... with size 32
//   mimalloc: error: double free detected of block 0x... with size 32
// (3 次循环,每次 drop 一次 box,第 1 次真 free + 第 2/3 次 double free 报错)
//
// **对比同样代码搬到 main() 体内(`/tmp/d164_main.ss`)**:
//   - main IR(d164_main.ll line 5181-5215):
//       while.body.154:
//         %10 = load ptr, ptr %box.79, align 8
//         %11 = call i32 @TestBoxD164_getVal(ptr %10)
//         %12 = load i32, ptr %i.80, align 8       ← while.body 内**没有** ss_drop
//         %13 = add i32 %12, 1
//         ...
//         br label %while.cond.153
//       while.after.155:
//         call void @ss_println(ptr @.str.81)
//         %14 = load ptr, ptr %box.79, align 8
//         call void @ss_rc_release(ptr %14)         ← 旧 RC release 在 while.after 之后,正确
//         ret i32 0
//   实测运行 `bin/ss run /tmp/d164_main.ss` 退出 exit=0 + stderr 无报错 — GREEN
//
// **真根因 file:line(对比 helper fn vs main 路径分流)**:
//   1. `bootstrap/gen/gen_decls.ss:125` `if (name != "main") { pirAnalyzeFunc(...) }`
//      → main 函数**不**走 PIR analysis,走旧 RC 系统 emitReleaseLocals (gen_decls.ss:134-136)
//      → main 内 class instance 在 ret 之前一次性 ss_rc_release(while.after 块外,正确)
//      → helper fn 走 PIR analysis(pir_lower.ss + pir_opt.ss),触发本 bug
//   2. `bootstrap/pir/pir_opt.ss:11-117` `pirLivenessPass` reverse scan 找 last-use
//      Step 2(line 58-83):反向扫描 PIR instr list,first-hit-from-back = last-use stmt
//      → loop body 内最后一条 USE(`box.getVal()` EXPR_STMT)被命中为 last-use
//      → schedule 设到 body 内 stmt id `pirSchedule[bodyStmtId] = "box:TestBoxD164"`
//   3. `bootstrap/gen/stmts/stmts_core.ss:86` `pirEmitScheduled(stmtId)`
//      → genBlock 在 while body 内每条 stmt codegen 完调用 → emit 落在 while.body 块内
//   4. **缺口**:`bootstrap/pir/pir_lower.ss` 处理 WHILE / FOR / FOR_IN / FOR_OF / DO_WHILE
//      时(line 43-59),lower body 后**漏 emit**一份 USE 在 loop 整体 stmt id 上
//      → reverse scan 在 PIR list 末尾向前扫,first-hit 是 body 内 USE 而非 loop 整体
//      → liveness 误标 last-use 在 body 内
//
// **Phase 2 修法 target file:line list**(LOC 估 +30~+50 行 单 file pir_lower.ss):
//   - PRIMARY: `bootstrap/pir/pir_lower.ss` 处理 WHILE/FOR/FOR_IN/FOR_OF/DO_WHILE 时
//     lower body 完毕 buf 之后,追加调用新增辅助 `pirEmitBlockUsesAtStmt(bodyId, loopStmtId, buf)`
//     emit 一份 body 内每条 stmt 的 expr USE,stmt id = loop 整体 stmt id。
//     reverse scan first-hit-from-back 命中 loop 整体 stmt USE(在 PIR list 更靠后位置)→
//     last-use 设为 loop 整体 stmt id → schedule 推到 loop 整体 stmt 后 → emit 落 while.after 块外
//   - 修改点:`pir_lower.ss:43-59`(FOR / FOR_IN / FOR_OF / WHILE / DO_WHILE 5 个分支对称改)
//   - 新增辅助:`pir_lower.ss` 末尾 ~25-35 LOC `pirEmitBlockUsesAtStmt(blockId, stmtIdOverride, buf): string`
//     递归处理 block 内每条 stmt 的 expr USE,nested loop / nested if / VAR_DECL/ASSIGN/EXPR_STMT 全覆盖
//   - 守护:`./build.sh bootstrap` 三阶段固定点 stage2==stage3 + 14 reflection 指标 no regression
//
// **H1 vs H2 isolate 结论**:
//   - 表层命中 H2(pir_opt 优化阶段 reverse scan 算 last-use 错)— 但 root cause 在 H1
//     (pir_lower lower 阶段漏 emit loop-after USE marker 致 reverse scan 信号不全)
//   - 真正修法在 pir_lower.ss(在 pir_opt 之前给 reverse scan 准备好正确的 USE 输入)
//   - pir_opt.ss reverse scan 算法本身不动(loop-aware liveness 留 §F3 远期),仅靠 lower
//     补一份 USE 在 loop 整体 stmt 即修正
//
// **bug A vs bug B 二根因 isolate**:
//   - **bug B**(ASSIGN LHS 非 class 早退漏扫 RHS USE,Case 1/2/3 触发 — drop 立即在 ALLOC 后):
//     `pirLowerAssign` line 140 `if (pirIsClass(ssType) == 0) { return buf }` 早退,RHS 表达式
//     如 `sum + box.getVal()` 中的 box METHOD_CALL USE 完全不收集 → reverse scan 找不到 box
//     任何 USE → Step 3 line 91-94 fallback `lastUseStmt.set(vn, defStmt.getString(vn))`
//     → schedule 设到 VAR_DECL stmt id → 第 1 次循环就 UAF(IR line 5365-5368 实证 entry 块 drop)
//   - **bug A**(EXPR_STMT in loop body 形态,Case 4 触发 — drop 在 while.body 块内):
//     `pirLowerExprStmt` 正确扫 USE 但 stmtId 是 body 内 stmt → reverse scan first-hit-from-back
//     是 body 内 stmt(因 PIR list 是线性序,body 内 USE 在末尾)→ schedule 设到 body 内 stmt
//     → drop emit 在 while.body 块内 → 第 2 次循环 UAF(d164_min.ll line 5197-5200 实证)
//     bug A 在 D160 wire 真值反射重启 t18.ss 17 行最小 repro 形态(`tmpl.execute(...)` EXPR_STMT)
//     触发,**Phase 2 必修以让 D163 §Phase 3 重启 + D160 §Phase 4 重启 8 case GREEN**
//
// **Phase 2 修法 target 双修(LOC 估 +30~+50 行 单 file pir_lower.ss)**:
//   - **bug B 修法**(LOC +1~+3):`bootstrap/pir/pir_lower.ss:137-159 pirLowerAssign`
//     在 line 140 早退**之前**加 `buf = pirEmitExprUses(nGetI1(id), id, buf)` 扫描 RHS,
//     LHS 非 class return buf(USE 已扫描),LHS class 走原 RC_DEC/RC_INC 流程
//     → ASSIGN RHS 内 class var USE 入 PIR list,reverse scan 找到 last-use,不再 fallback
//   - **bug A 修法**(LOC +25~+45):`bootstrap/pir/pir_lower.ss:43-59` 处理
//     WHILE/FOR/FOR_IN/FOR_OF/DO_WHILE 时,lower body 完毕后追加调用新增辅助
//     `pirEmitBlockUsesAtStmt(bodyId, loopStmtId, buf)`,递归扫 body 内每条 stmt 的 expr USE
//     但 stmtId 用 loop 整体 stmt id 而非 body 内 stmt id
//     → reverse scan first-hit-from-back 命中 loop 整体 stmt USE(在 PIR list 更靠后位置)
//     → last-use 设为 loop 整体 stmt id → schedule 推到 loop 整体 stmt 后 → emit 落 while.after 块外
//     新增辅助函数 ~35-45 LOC 处理 VAR_DECL/ASSIGN/MEMBER_ASSIGN/EXPR_STMT/RETURN/嵌套
//     WHILE/DO_WHILE/FOR/FOR_IN/FOR_OF/IF 全形态
//
// 4 case 覆盖:
//   Case 1 helper fn + while loop ≥ 2 次 + simple class.method(ASSIGN sum=sum+box.getVal())— bug B
//   Case 2 helper fn + C-style for loop + class.method(ASSIGN 同形)— bug B(FOR 节点对称)
//   Case 3 nested helper fn(fn1 calls fn2)+ nested loop + 多 class instance(2 个)— bug B(nested 守护)
//   Case 4 helper fn + while loop + EXPR_STMT class.method bump global — **bug A**(d164_min.ss / t18.ss 同形)

import { test, assertEqual } from "@/lib/test"

// ── 共享工具 class(无外部 lib 依赖) ──

class TestBoxD164 {
    val: int
    function getVal(): int { return this.val }
}

// ── Case 4 全局 counter:method 内修改全局触发 EXPR_STMT-only side effect 路径 ──

let countD164 = 0

class CounterD164 {
    val: int
    function bump() {
        countD164 = countD164 + this.val
    }
}

// ── Case 1: helper fn + while loop ≥ 2 次 + simple class.method ──

function loopHelperCase1(): int {
    let box = new TestBoxD164(42)
    let i = 0
    let sum = 0
    while (i < 3) {
        sum = sum + box.getVal()
        i = i + 1
    }
    return sum
}

// ── Case 2: helper fn + C-style for loop + class.method ──

function loopHelperCase2(): int {
    let box = new TestBoxD164(7)
    let sum = 0
    for (let i = 0; i < 5; i = i + 1) {
        sum = sum + box.getVal()
    }
    return sum
}

// ── Case 3: nested helper fn + nested loop body + 多 class instance ──

function loopHelperInner(): int {
    let box1 = new TestBoxD164(10)
    let box2 = new TestBoxD164(20)
    let i = 0
    let sum = 0
    while (i < 2) {
        sum = sum + box1.getVal() + box2.getVal()
        i = i + 1
    }
    return sum
}

function loopHelperCase3(): int {
    return loopHelperInner()
}

// ── Case 4: helper fn + while loop + EXPR_STMT class.method bump global(bug A 路径) ──

function loopHelperCase4(): int {
    let box = new CounterD164(7)
    let i = 0
    while (i < 5) {
        box.bump()
        i = i + 1
    }
    return countD164
}

function main() {
    test("D164 Case 1 — helper fn + while loop >= 2 + simple class.method", () => {
        const r = loopHelperCase1()
        // Phase 1 RED:mimalloc double free + (UAF 后)r 不定;Phase 2 修法后 GREEN:r=126(42*3)
        assertEqual(r, 126)
    })

    test("D164 Case 2 — helper fn + C-style for loop + class.method", () => {
        const r = loopHelperCase2()
        // Phase 1 RED:mimalloc double free;Phase 2 修法后 GREEN:r=35(7*5)
        assertEqual(r, 35)
    })

    test("D164 Case 3 — nested helper fn + nested loop + multi class instance", () => {
        const r = loopHelperCase3()
        // Phase 1 RED:多次 double free;Phase 2 修法后 GREEN:r=60((10+20)*2)
        assertEqual(r, 60)
    })

    test("D164 Case 4 — EXPR_STMT in loop body — bump global(bug A 路径,d164_min/t18 同形)", () => {
        countD164 = 0
        const r = loopHelperCase4()
        // Phase 1 RED:bug A — drop 在 while.body 内每次循环,第 2 次起 UAF,bump 用 garbage 修改全局
        //          实测 r != 35 (例:-1077952571 等 mimalloc poison 值 + double free 报错)
        // Phase 2 修法后 GREEN:r=35(7*5)
        assertEqual(r, 35)
    })
}
