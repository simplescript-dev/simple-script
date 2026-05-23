// NULL_COALESCE 二元 op 子文件(原 eval_expr.ss BINARY 迁出)
// 单边短路 op(`a ?? b`:lhs 非 null → 返 lhs lazy rhs;lhs null → eval rhs)。
// 1.5e+ ext 三段式 sibling 一致(对齐 ternary.ss:4-10 + short_circuit.ss:5-13 模式
// 但保 NullCoalesce 单边短路):eager lRaw 上移 → 段 1 ct 短路(lhs ct 非 null → 返
// lhs 不 eval rhs)→ 段 2 紧 loud(must-known + lhs/rhs 任一非 ct → loud error)→
// 段 3 runtime forward `reg(lRaw)`+ 空 rPreReg 哨兵保 rhs lazy 由 genNullCoalesce 内
// br then 块惰性 eval 消 caller→genBinary→genNullCoalesce→genExpr(leftId) 双 eval bug。

function evalNullCoalesce(astId: int): int {
    const lRaw = genVal(nGetI1(astId))
    if (isCt(lRaw) == 1 && valType(lRaw) != "null") { return lRaw }
    if (comptimeMustBeKnown == 1) {
        if (isCt(lRaw) == 0) {
            return comptimeError(`null-coalesce lhs is not compile-time known`, astId)
        }
        const rv = genVal(nGetI2(astId))
        if (isCt(rv) == 0) {
            return comptimeError(`null-coalesce rhs is not compile-time known`, astId)
        }
        return rv
    }
    // rPreReg "" 哨兵 PERMANENT:NullCoalesce 短路语义 rhs 仅在 lhs null br then 内 lazy eval,不可 eager forward
    return mvRuntime(constVal(genBinary(astId, reg(lRaw), "")))
}
