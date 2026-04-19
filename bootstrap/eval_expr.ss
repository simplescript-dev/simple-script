// D099 §步骤 1:evalExpr 吸收 BINARY(非 And/Or)。D098 §决策 1 Phase A mv 编码:
//   mv >= 0   → known,  val = mv        (ctVal tagged int,bit 30 set)
//   mv <= -2  → runtime,regId = -mv - 1  (regTable 1-based)
//   mv == -1  → error 哨兵
// 调用方 genValBinary shim 已过滤 kind==BINARY + op!=And/Or。

function evalExpr(astId: int): int {
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
