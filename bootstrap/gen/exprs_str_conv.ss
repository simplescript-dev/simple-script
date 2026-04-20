// gen/exprs_str_conv.ss — 表达式到字符串的转换(println / 模板串拼接用)。
// 设置 lastExprStringOwned: 1 = 新分配的需 release,0 = 借用。

function genExprAsString(id: int, preReg: string = ""): string {
    const vType = inferType(id)
    const llType = ssTypeToLLVM(vType)
    if (vType == "string" || (llType == "ptr" && vType != "ptr" && vType.contains("<") == 0)) {
        const sVal = preReg != "" ? preReg : genExpr(id)
        const sNodeKind = nGetKind(id)
        if (sNodeKind == "IDENT" && getVarType(nGetS1(id)) == "i64") {
            const castR = nextReg()
            emitIR(`  ${castR} = inttoptr i64 ${sVal} to ptr`)
            lastExprStringOwned = 0
            return castR
        }
        lastExprStringOwned = 0
        return sVal
    }
    const val = preReg != "" ? preReg : genExpr(id)
    if (vType == "double") {
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_double_to_string(double ${val})`)
        lastExprStringOwned = 1
        return r
    }
    if (vType == "i64") {
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_i64_to_string(i64 ${val})`)
        lastExprStringOwned = 1
        return r
    }
    if (vType == "ptr" || vType.contains("<") == 1) {
        const castR = nextReg()
        emitIR(`  ${castR} = ptrtoint ptr ${val} to i64`)
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_i64_to_string(i64 ${castR})`)
        lastExprStringOwned = 1
        return r
    }
    const r = nextReg(); emitIR(`  ${r} = call ptr @ss_int_to_string(i32 ${val})`)
    lastExprStringOwned = 1
    return r
}
