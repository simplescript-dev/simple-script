// gen/exprs_str_conv.ss — 表达式到字符串的转换(println / 模板串拼接用)。
// 设置 lastExprStringOwned: 1 = 新分配的需 release,0 = 借用。

function genExprAsString(id: int, preReg: string = ""): string {
    const vType = inferType(id)
    const llType = ssTypeToLLVM(vType)
    // D168 §B.7: 严格 string 才直接借用;user class / array / map 等 ptr 类型走
    // ptrtoint → ss_i64_to_string 路径(打印整数地址),否则 ss_println GEP buffer 时
    // 会把 class 实例 offset 16 处的字段当 buffer ptr 读 → segfault。
    if (vType == "string") {
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
    // D168 §B.7: 凡 llType==ptr(user class / array / map / set / generic 等)走
    // ptrtoint → ss_i64_to_string,打印整数地址(替代旧 ABI 把 ptr 当 cstr 给 puts 的 hack)。
    if (vType == "ptr" || vType.contains("<") == 1 || llType == "ptr") {
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
