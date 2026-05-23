// gen/stmts_loop_classic.ss — 经典循环:for / while / do-while。

import { emitCondToI1, genBlock, genNestedBlock } from "./stmts_core"

function genFor(id: int) {
    const initId = nGetI1(id)
    const condId = nGetI2(id)
    const updateId = nGetI3(id)
    const bodyId = nGetI4(id)

    // D089 Phase 3: comptime for in comptime block
    // SUNSET(D093 §1.5d 主轮收口子步 sibling 子轮): for 入口 ct-depth 字面 → comptimeMustBeKnown == 1 + silent || 短路拆 loud,sibling do-while (ddd327c) 完全一致
    if (comptimeDepth > 0) {
        genStmt(initId)
        let ctForLimit = 10000
        while (ctForLimit > 0) {
            const fCondTagged = genVal(condId)
            if (isCt(fCondTagged) == 0 || interpTruthy(payload(fCondTagged)) == 0) { break }
            genBlock(bodyId)
            if (interpCheckLoopExit() == 1) { break }
            interpContinueFlag = 0
            genStmt(updateId)
            ctForLimit = ctForLimit - 1
        }
        interpBreakFlag = 0
        if (ctForLimit == 0) { println("[comptime] for loop exceeded 10000 iterations") }
        return
    }

    const condLabel = nextLabel("for.cond")
    const bodyLabel = nextLabel("for.body")
    const updateLabel = nextLabel("for.update")
    const afterLabel = nextLabel("for.after")

    const savedBreak = breakLabel
    const savedContinue = continueLabel
    const savedLoopStack = loopBlockStackSaved
    breakLabel = afterLabel
    continueLabel = updateLabel
    loopBlockStackSaved = blockPtrVarStack

    genStmt(initId)
    emitIR(`  br label %${condLabel}`)

    emitIR(`${condLabel}:`)
    const condVal = genExpr(condId)
    const r = emitCondToI1(condId, condVal)
    emitIR(`  br i1 ${r}, label %${bodyLabel}, label %${afterLabel}`)

    emitIR(`${bodyLabel}:`)
    terminated = 0
    genNestedBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${updateLabel}`) }

    emitIR(`${updateLabel}:`)
    terminated = 0
    genStmt(updateId)
    emitIR(`  br label %${condLabel}`)

    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak
    continueLabel = savedContinue
    loopBlockStackSaved = savedLoopStack
}

function genWhile(id: int) {
    const condId = nGetI1(id)
    const bodyId = nGetI2(id)

    // D089 Phase 3: comptime while in comptime block
    // SUNSET(D093 §1.5d 主轮收口子步 sibling 子轮): while 入口 ct-depth 字面 → comptimeMustBeKnown == 1 + silent || 短路拆 loud,sibling do-while (ddd327c) 完全一致
    if (comptimeDepth > 0) {
        let ctWhileLimit = 10000
        while (ctWhileLimit > 0) {
            const wCondTagged = genVal(condId)
            if (isCt(wCondTagged) == 0 || interpTruthy(payload(wCondTagged)) == 0) { break }
            genBlock(bodyId)
            if (interpCheckLoopExit() == 1) { break }
            interpContinueFlag = 0
            ctWhileLimit = ctWhileLimit - 1
        }
        interpBreakFlag = 0
        if (ctWhileLimit == 0) { println("[comptime] while loop exceeded 10000 iterations") }
        return
    }

    const condLabel = nextLabel("while.cond")
    const bodyLabel = nextLabel("while.body")
    const afterLabel = nextLabel("while.after")

    const savedBreak3 = breakLabel
    const savedContinue3 = continueLabel
    const savedLoopStack3 = loopBlockStackSaved
    breakLabel = afterLabel
    continueLabel = condLabel
    loopBlockStackSaved = blockPtrVarStack

    emitIR(`  br label %${condLabel}`)

    emitIR(`${condLabel}:`)
    const condVal = genExpr(condId)
    const r = emitCondToI1(condId, condVal)
    emitIR(`  br i1 ${r}, label %${bodyLabel}, label %${afterLabel}`)

    emitIR(`${bodyLabel}:`)
    terminated = 0
    genNestedBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${condLabel}`) }

    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak3
    continueLabel = savedContinue3
    loopBlockStackSaved = savedLoopStack3
}

function genDoWhile(id: int) {
    const bodyId = nGetI1(id)
    const condId = nGetI2(id)

    // D093/D169 1.5d 主轮收口子步起手 — Phase 1 类 A spike(原 5d36c8c §拒绝准则 #1/#3
    // Blocked,1.5a-d 协议接口就绪后落地首处 statement-level 类 A 消除):
    //   (a) ct-depth 字面 → `comptimeMustBeKnown == 1` rename(sibling 1.5c
    //        12 子轮同模式;ct_driver.ss:30-36 enter/exit lockstep + codegen.ss:281 reset 对称)
    //   (b) OLD silent `|| interpTruthy == 0` 短路拆 loud gate(sibling `ternary.ss:10`
    //        / `short_circuit.ss:13` / `eval_expr.ss:125` 完全一致;D093 §第一性需求
    //        "comptime 块内 evalExpr known=false 即 error")
    // statement 层无 mv 出口,真单 dispatch eager+无 gate 终态留 1.5e+;
    // line 12 for / line 71 while 同入口边界留**后续 sibling 子轮**迁。
    if (comptimeMustBeKnown == 1) {
        let ctDoLimit = 10000
        while (ctDoLimit > 0) {
            genBlock(bodyId)
            if (interpCheckLoopExit() == 1) { break }
            interpContinueFlag = 0
            const dwCondTagged = genVal(condId)
            if (isCt(dwCondTagged) == 0) {
                comptimeError("do-while condition not compile-time known", id)
                return
            }
            if (interpTruthy(payload(dwCondTagged)) == 0) { break }
            ctDoLimit = ctDoLimit - 1
        }
        interpBreakFlag = 0
        if (ctDoLimit == 0) { println("[comptime] do-while loop exceeded 10000 iterations") }
        return
    }

    const bodyLabel = nextLabel("dowhile.body")
    const condLabel = nextLabel("dowhile.cond")
    const afterLabel = nextLabel("dowhile.after")
    const savedBreak = breakLabel
    const savedContinue = continueLabel
    const savedLoopStack4 = loopBlockStackSaved
    breakLabel = afterLabel
    continueLabel = condLabel
    loopBlockStackSaved = blockPtrVarStack
    emitIR(`  br label %${bodyLabel}`)
    emitIR(`${bodyLabel}:`)
    terminated = 0
    genNestedBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${condLabel}`) }
    emitIR(`${condLabel}:`)
    const condVal = genExpr(condId)
    const r = emitCondToI1(condId, condVal)
    emitIR(`  br i1 ${r}, label %${bodyLabel}, label %${afterLabel}`)
    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak
    continueLabel = savedContinue
    loopBlockStackSaved = savedLoopStack4
}
