// D099 §步骤 1-2:evalExpr 吸收 BINARY(非 And/Or)+ UNARY。D098 §决策 1 Phase A mv 编码:
//   mv >= 0   → known,  val = mv        (ctVal tagged int,bit 30 set)
//   mv <= -2  → runtime,regId = -mv - 1  (regTable 1-based)
//   mv == -1  → error 哨兵
// 调用方 shim:genValBinary 过滤 kind==BINARY + op!=And/Or;genValUnary 过滤 kind==UNARY。
// UNARY 分支内联 evalExpr 体:步骤 2 不建 evalUnary 独立函数(M7b 余量 0),body 进 `if UNARY` 块
// depth +1,N3 成本 ~80(baseline 余量 889 充裕),抵消 genValUnary body 删除 → 净 N3 小幅下降。

function evalExpr(astId: int): int {
    if (nGetKind(astId) == "UNARY") {
        const uOp = nGetS1(astId)
        if (comptimeDepth > 0) {
            const ctUv = genVal(nGetI1(astId))
            if (isCt(ctUv) == 0) { return ctVal(interpNewNull()) }
            const ctUp = payload(ctUv)
            const ctUt = interpType(ctUp)
            if (uOp == "Neg") {
                if (ctUt == "double") { return ctVal(interpNewDouble(0.0 - parseDouble(interpAsStr(ctUp)))) }
                return ctVal(interpNewInt(0 - interpAsInt(ctUp)))
            }
            if (uOp == "Not") { return ctVal(interpNewBool(interpTruthy(ctUp) == 1 ? 0 : 1)) }
            if (uOp == "BitNot") { return ctVal(interpNewInt(~interpAsInt(ctUp))) }
            return ctVal(interpNewNull())
        }
        const uType = inferType(nGetI1(astId))
        if (uType != "int" && uType != "bool") {
            return 0 - constVal(genUnary(astId)) - 1
        }
        const ov = genVal(nGetI1(astId))
        if (isCt(ov) == 1) {
            const uVal = interpAsInt(payload(ov))
            if (uOp == "Neg") { return ctVal(interpNewInt(0 - uVal)) }
            if (uOp == "Not") { return ctVal(interpNewBool(uVal == 0 ? 1 : 0)) }
            if (uOp == "BitNot") { return ctVal(interpNewInt(~uVal)) }
        }
        const uValStr = reg(ov)
        const uR = nextReg()
        if (uOp == "Neg") {
            emitIR(`  ${uR} = sub i32 0, ${uValStr}`)
            return 0 - constVal(uR) - 1
        }
        if (uOp == "BitNot") {
            emitIR(`  ${uR} = xor i32 ${uValStr}, -1`)
            return 0 - constVal(uR) - 1
        }
        emitIR(`  ${uR} = icmp eq i32 ${uValStr}, 0`)
        const uR2 = nextReg()
        emitIR(`  ${uR2} = zext i1 ${uR} to i32`)
        return 0 - constVal(uR2) - 1
    }
    const op = nGetS1(astId)
    if (comptimeDepth > 0) {
        if (op == "NullCoalesce") {
            const ctNcL = genVal(nGetI1(astId))
            if (isCt(ctNcL) == 1 && interpType(payload(ctNcL)) != "null") { return ctNcL }
            return genVal(nGetI2(astId))
        }
        if (op == "Instanceof" || op == "As") {
            return comptimeError(`operator '${op}' not supported`, astId)
        }
        const ctBlv = genVal(nGetI1(astId))
        const ctBrv = genVal(nGetI2(astId))
        if (isCt(ctBlv) == 0 || isCt(ctBrv) == 0) {
            return comptimeError(`binary '${op}' operand is not compile-time known`, astId)
        }
        const ctBlp = payload(ctBlv)
        const ctBrp = payload(ctBrv)
        const ctBlt = interpType(ctBlp)
        const ctBrt = interpType(ctBrp)
        if (op == "Add" && (ctBlt == "string" || ctBrt == "string")) {
            return ctVal(interpNewString(`${interpToStr(ctBlp)}${interpToStr(ctBrp)}`))
        }
        if (ctBlt == "string" && ctBrt == "string") { return genValStringCompare(op, astId) }
        if (ctBlt == "double" || ctBrt == "double") {
            const ctLd = ctBlt == "double" ? parseDouble(interpAsStr(ctBlp)) : parseDouble(`${interpAsInt(ctBlp)}`)
            const ctRd = ctBrt == "double" ? parseDouble(interpAsStr(ctBrp)) : parseDouble(`${interpAsInt(ctBrp)}`)
            return ctVal(interpDoubleOp(op, ctLd, ctRd))
        }
        return ctVal(interpIntOp(op, interpAsInt(ctBlp), interpAsInt(ctBrp)))
    }
    if (op == "NullCoalesce" || op == "Instanceof" || op == "As" || op == "Pow") {
        return 0 - constVal(genBinary(astId)) - 1
    }
    const blt = inferType(nGetI1(astId))
    const brt = inferType(nGetI2(astId))
    if (blt == "string" && brt == "string" && (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge")) {
        const sc = genValStringCompare(op, astId)
        if (isCt(sc) == 1) { return sc }
        return 0 - sc - 1
    }
    if ((blt != "int" && blt != "bool") || (brt != "int" && brt != "bool")) {
        return 0 - constVal(genBinary(astId)) - 1
    }
    const lv = genVal(nGetI1(astId))
    const rv = genVal(nGetI2(astId))
    if (isCt(lv) == 1 && isCt(rv) == 1) {
        return ctVal(interpIntOp(op, interpAsInt(payload(lv)), interpAsInt(payload(rv))))
    }
    return 0 - constVal(genIntBinary(op, reg(lv), reg(rv))) - 1
}
