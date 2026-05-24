// gen/stmts_core.ss — 共享 helper:cond→i1、block driver、comptime body、break/continue。
// genBlock↔genStmt(dispatcher)是 mutual recursion,靠全局 scope 消解。

// ── Cond → i1 coercion ─────────────────────────────────────

function emitCondToI1(condId: int, condVal: string): string {
    const vType = inferType(condId)
    const llType = ssTypeToLLVM(vType)
    const r = nextReg()
    if (llType == "ptr") {
        emitIR(`  ${r} = icmp ne ptr ${condVal}, null`)
    } else if (llType == "i64") {
        emitIR(`  ${r} = icmp ne i64 ${condVal}, 0`)
    } else if (llType == "double") {
        emitIR(`  ${r} = fcmp one double ${condVal}, 0.0`)
    } else {
        emitIR(`  ${r} = icmp ne i32 ${condVal}, 0`)
    }
    return r
}

// ── break / continue(流控 flag) ──────────────────────────

function genBreak() {
    // D089 Phase 3: comptime break → set flag
    if (comptimeMustBeKnown == 1) { interpBreakFlag = 1; return }
    if (breakLabel != "") {
        emitReleaseBlockVarsSince(loopBlockStackSaved)
        emitIR(`  br label %${breakLabel}`)
        terminated = 1
    }
}

function genContinueStmt() {
    // D089 Phase 3: comptime continue → set flag
    if (comptimeMustBeKnown == 1) { interpContinueFlag = 1; return }
    if (continueLabel != "") {
        emitReleaseBlockVarsSince(loopBlockStackSaved)
        emitIR(`  br label %${continueLabel}`)
        terminated = 1
    }
}

// ── Block driver + comptime body ───────────────────────────

// Run a comptime block body via genBlock without flushing comptimeSS (caller decides).
// 返回 ct block 体内 RETURN 的 tvId(0 = 未 RETURN 或 RETURN null);出口 reset
// interpReturnFlag/Val/Break/Continue,防止 ct 求值的 RETURN flag leak 到下游 codegen
// (例如 for-in ct unroll 的 interpCheckLoopExit 误判提前 break,只 emit 第一次 iter 的 IR)。
function runComptimeBlockBody(bodyId: int): int {
    const savedFunc = currentFunc
    const savedTerminated = terminated
    currentFunc = "__comptime__"
    ctScopeStack = ctScopeStack.push("__comptime__")
    interpReturnFlag = 0
    interpReturnVal = 0
    interpBreakFlag = 0
    interpContinueFlag = 0
    terminated = 0
    interpEnsureComptimeRoot()
    enterComptimeBlock()
    genBlock(bodyId)
    exitComptimeBlock()
    terminated = savedTerminated
    ctPopScope()
    currentFunc = savedFunc
    const retVal = interpReturnFlag == 1 ? interpReturnVal : 0
    interpReturnFlag = 0
    interpReturnVal = 0
    interpBreakFlag = 0
    interpContinueFlag = 0
    return retVal
}

function genBlock(blockId: int) {
    if (blockId <= 0) { return }
    const stmtList = nGetList(blockId)
    if (stmtList == "") { return }
    const parts = stmtList.split(",")
    for (p in parts) {
        const stmtId = parseInt(p)
        if (stmtId > 0) {
            genStmt(stmtId)
            if (terminated == 1) { return }
            if (comptimeDepth > 0 && interpShouldStop() == 1) { return }
            pirEmitScheduled(stmtId)
        }
    }
}

// RC: nested block wrapper — tracks block-level ptr vars and releases them on exit
function genNestedBlock(blockId: int) {
    pushBlockScope()
    rcBlockDepth = rcBlockDepth + 1
    genBlock(blockId)
    // Release block vars on normal exit (skip if terminated by return/break/continue)
    if (terminated == 0) {
        emitReleaseCurrentBlockVars()
    }
    popBlockScope()
    rcBlockDepth = rcBlockDepth - 1
}
