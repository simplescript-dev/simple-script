// TERNARY 子目录文件(原 eval_expr.ss 迁出)
// 对称三段式:cond ct → 单边 evalExpr;cond runtime → alloca + br + load

function evalTernary(astId: int): int {
    const cv = genVal(nGetI1(astId))
    if (isCt(cv) == 1) {
        const pv = genVal(interpTruthy(payload(cv)) == 1 ? nGetI2(astId) : nGetI3(astId))
        return isCt(pv) == 1 ? pv : 0 - pv - 1
    }
    if (comptimeMustBeKnown == 1) { return comptimeError("ternary condition not compile-time known", astId) }
    const condStr = reg(cv)
    // D144 Phase 2: phi llType 优先读反推 branchType nSetS2(checker `checkerInferType`
    // TERNARY case + check_exprs.ss D144 两分支同类型回填),fallback 单 then 分支 inferType
    // (D141/D142/D143 G1 同模式 — null literal 在 callee `T?` 反推后 ssTypeToLLVM 自动返 ptr,
    // class instance ternary 在 IShape upcast 反推后 ptr 一致,X4-1 字段访问 inferType 链路用 nSetS2)
    const ternBranchTypeR = nGetS2(astId)
    const llType = ternBranchTypeR != "" ? ssTypeToLLVM(ternBranchTypeR) : ssTypeToLLVM(inferType(nGetI2(astId)))
    const alloca = emitEntryAlloca(nextReg(), llType, 8)
    const cmp = nextReg()
    emitIR(`  ${cmp} = icmp ne i32 ${condStr}, 0`)
    const thenL = nextLabel("tern.then")
    const elseL = nextLabel("tern.else")
    const mergeL = nextLabel("tern.merge")
    emitIR(`  br i1 ${cmp}, label %${thenL}, label %${elseL}`)
    emitIR(`${thenL}:`)
    const thenV = genExpr(nGetI2(astId))
    emitIR(`  store ${llType} ${thenV}, ptr ${alloca}, align 8`)
    emitIR(`  br label %${mergeL}`)
    emitIR(`${elseL}:`)
    const elseV = genExpr(nGetI3(astId))
    emitIR(`  store ${llType} ${elseV}, ptr ${alloca}, align 8`)
    emitIR(`  br label %${mergeL}`)
    emitIR(`${mergeL}:`)
    const r = nextReg()
    emitIR(`  ${r} = load ${llType}, ptr ${alloca}, align 8`)
    return 0 - constVal(r) - 1
}
