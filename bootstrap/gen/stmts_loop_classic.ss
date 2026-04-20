// gen/stmts_loop_classic.ss — 经典循环:for / while / do-while。

import { emitCondToI1, genBlock, genNestedBlock } from "./stmts_core"

function genFor(id: int) {
    const initId = nGetI1(id)
    const condId = nGetI2(id)
    const updateId = nGetI3(id)
    const bodyId = nGetI4(id)

    // D089 Phase 3: comptime for in comptime block
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

    if (comptimeDepth > 0) {
        let ctDoLimit = 10000
        while (ctDoLimit > 0) {
            genBlock(bodyId)
            if (interpCheckLoopExit() == 1) { break }
            interpContinueFlag = 0
            const dwCondTagged = genVal(condId)
            if (isCt(dwCondTagged) == 0 || interpTruthy(payload(dwCondTagged)) == 0) { break }
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
