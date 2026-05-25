// POW 二元 op 子文件(原 eval_expr.ss BINARY 迁出)
// 数值对称 op(int/double 双边求值);1.5e+ ext 三段式 sibling 一致(对齐 BINARY 主
// case eval_expr.ss:114-138 bb0f805 + ternary/short_circuit/index_access 模式):
// eager unify lRaw/rRaw 上移 → 段 1 ct fold(仅 integer 指数;fractional 指数 ct
// fold 不可达 ∵ interpDoubleOp Pow integer-loop 实现不支持 fractional)→ 段 2 紧
// loud → 段 3 runtime forward `reg(lRaw)/reg(rRaw)` 至 genBinary 消 caller→genExpr
// 双 eval bug(genBinary 内 Pow case 用 ss_pow libc 支持 fractional)。
// **fractional ct fold 根因**:SS bootstrap 无 ct-side libc pow / exp / log,扩
// interpDoubleOp Pow 支持 fractional 需 SS 实现 Newton iteration / Taylor 展开,
// scope 远超本轮 — 段 1 仅 integer 指数 ct fold + fractional fallback runtime 是
// sustainable 中间态(全 SS pow ct fold 实现留 D093 §1.5e+ later 同 valType 终态批次)。

function evalPow(astId: int): int {
    const lRaw = genVal(nGetI1(astId))
    const rRaw = genVal(nGetI2(astId))
    if (isCt(lRaw) == 1 && isCt(rRaw) == 1) {
        const rt = valType(rRaw)
        if (rt != "double") {
            return ctVal(interpNumericBinop("Pow", valOf(lRaw), valOf(rRaw), valType(lRaw), rt))
        }
    }
    if (comptimeMustBeKnown == 1) {
        return comptimeError(`binary 'Pow' operand is not compile-time known`, astId)
    }
    return mvRuntime(constVal(genBinary(astId, reg(lRaw), reg(rRaw))))
}
