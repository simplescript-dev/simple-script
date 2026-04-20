// D108 §步骤 1: TERNARY 迁出 eval_expr.ss 独立子目录文件
// 对称三段式:cond ct → 单边 evalExpr;cond runtime → alloca + br + load

function evalTernary(astId: int): int {
    const cv = genVal(nGetI1(astId))
    if (isCt(cv) == 1) {
        const pv = genVal(interpTruthy(payload(cv)) == 1 ? nGetI2(astId) : nGetI3(astId))
        return isCt(pv) == 1 ? pv : 0 - pv - 1
    }
    if (comptimeDepth > 0) { return ctVal(interpNewNull()) }
    const condStr = reg(cv)
    const llType = ssTypeToLLVM(inferType(nGetI2(astId)))
    const alloca = nextReg()
    emitIR(`  ${alloca} = alloca ${llType}, align 8`)
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
