// NULL_COALESCE 二元 op 子文件(原 eval_expr.ss BINARY 迁出)
// 对称三段式:ct path(must-be-known)短路单边 lhs ct 非 null → 返 lhs,否则 rhs mv 透传;
// runtime path delegate genBinary 内 NullCoalesce case → genNullCoalesce alloca+br+load IR

function evalNullCoalesce(astId: int): int {
    // 不 eager 上移避 lhs runtime 时 genBinary→genNullCoalesce 内部 genExpr(leftId)
    // 再 eval 引入 double-eval bug(genNullCoalesce 接口扩 lPreReg/rPreReg 留独立轮)。
    // NEW rv 返值补 `isCt(rv) == 1 ? rv : 0 - rv - 1` mv 编码 — 顺手修 OLD
    // `return genVal(nGetI2(astId))` 在 lhs ct null + rhs runtime 时返 positive regId
    // 伪装 mv-known 的 silent encoding contract leak(baseline 334/3 持平实证未触发)
    if (comptimeMustBeKnown == 1) {
        const lv = genVal(nGetI1(astId))
        if (isCt(lv) == 1 && valType(lv) != "null") { return lv }
        const rv = genVal(nGetI2(astId))
        return isCt(rv) == 1 ? rv : 0 - rv - 1
    }
    return mvRuntime(constVal(genBinary(astId)))
}
