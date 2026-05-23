// POW 二元 op 子文件(原 eval_expr.ss BINARY 迁出)
// 数值对称 op(int/double 双边求值);ct path(must-be-known)走 interpDoubleOp/interpIntOp
// 数值 fold;runtime path delegate genBinary 内 Pow case ss_pow 调用(libc pow)

function evalPow(astId: int): int {
    // 不 eager genVal 上移 — Pow 子函数 ct path 完后直接 fallthrough genBinary 不 forward,
    // 双 eval 由 caller eager + lPreReg/rPreReg forward 解决(留 1.5e+ 统一 eager 上移 +
    // sibling 完全一致 桥消除)。**1.5d 主轮第三子步 unify**:interpNumericBinop helper
    // 抽取 + 与 eval_expr.ss BINARY 通用 ct path numeric fold 共享(5 行 × 2 → 1 helper × 2)。
    if (comptimeMustBeKnown == 1) {
        const lv = genVal(nGetI1(astId))
        const rv = genVal(nGetI2(astId))
        if (isCt(lv) == 0 || isCt(rv) == 0) {
            return comptimeError(`binary 'Pow' operand is not compile-time known`, astId)
        }
        return ctVal(interpNumericBinop("Pow", valOf(lv), valOf(rv), valType(lv), valType(rv)))
    }
    return mvRuntime(constVal(genBinary(astId)))
}
