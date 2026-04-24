// SHORT_CIRCUIT (And/Or) 子目录文件(原 eval_expr.ss 迁出)
// 对称三段式:left ct → 短路;left runtime → alloca + br + load

function evalShortCircuit(op: string, astId: int): int {
    const lv = genVal(nGetI1(astId))
    if (isCt(lv) == 1) {
        const leftTruthy = interpTruthy(payload(lv))
        if (op == "And" && leftTruthy == 0) { return ctVal(interpNewBool(0)) }
        if (op == "Or" && leftTruthy == 1) { return lv }
        const rv = genVal(nGetI2(astId))
        return isCt(rv) == 1 ? rv : 0 - rv - 1
    }
    if (comptimeDepth > 0) { return ctVal(interpNewNull()) }
    const leftStr = reg(lv)
    const scResult = nextReg()
    emitIR(`  ${scResult} = alloca i32, align 4`)
    emitIR(`  store i32 ${leftStr}, ptr ${scResult}, align 4`)
    const scCmp = nextReg()
    emitIR(`  ${scCmp} = icmp ne i32 ${leftStr}, 0`)
    const scRhs = nextLabel("sc.rhs")
    const scEnd = nextLabel("sc.end")
    const brLabels = op == "And" ? `label %${scRhs}, label %${scEnd}` : `label %${scEnd}, label %${scRhs}`
    emitIR(`  br i1 ${scCmp}, ${brLabels}`)
    emitIR(`${scRhs}:`)
    const scRight = genExpr(nGetI2(astId))
    emitIR(`  store i32 ${scRight}, ptr ${scResult}, align 4`)
    emitIR(`  br label %${scEnd}`)
    emitIR(`${scEnd}:`)
    const scRes = nextReg()
    emitIR(`  ${scRes} = load i32, ptr ${scResult}, align 4`)
    return 0 - constVal(scRes) - 1
}
