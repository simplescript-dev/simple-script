// D108 §步骤 1: INDEX_ACCESS 迁出 eval_expr.ss 独立子目录文件
// 对称三段式:obj+idx 全 ct → 直查 array/object/map/string;否则 runtime

function evalIndexAccess(astId: int): int {
    const obj = genVal(nGetI1(astId))
    const idx = genVal(nGetI2(astId))
    if (isCt(obj) == 1 && isCt(idx) == 1) {
        const objP = valOf(obj)
        const ot = valType(obj)
        if (ot == "array") { return ctVal(interpArrayGet(objP, interpAsInt(payload(idx)))) }
        if (ot == "object" || ot == "map") { return ctVal(interpGetField(objP, interpAsStr(payload(idx)))) }
        if (ot == "string") {
            const s = interpAsStr(objP)
            const i = interpAsInt(payload(idx))
            return ctVal(interpNewString(i >= 0 && i < s.length() ? s.charAt(i) : ""))
        }
    }
    if (comptimeDepth > 0) { return comptimeError("index access requires compile-time known operands", astId) }
    return 0 - constVal(genIndexAccess(astId, reg(obj), reg(idx))) - 1
}
