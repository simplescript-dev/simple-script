// POW 二元 op 子文件(原 eval_expr.ss BINARY 迁出)
// 数值对称 op(int/double 双边求值);ct path(must-be-known)走 interpDoubleOp/interpIntOp
// 数值 fold;runtime path delegate genBinary 内 Pow case ss_pow 调用(libc pow)

function evalPow(astId: int): int {
    // 不 eager genVal 上移 — Pow 子函数 ct path 完后直接 fallthrough genBinary 不 forward,
    // 双 eval 由 caller eager + lPreReg/rPreReg forward 解决(留下轮统一 eager 上移 +
    // sibling 完全一致 + interp_op.ss interpNumericBinop helper 抽取与通用 ct path unify)
    if (comptimeMustBeKnown == 1) {
        const lv = genVal(nGetI1(astId))
        const rv = genVal(nGetI2(astId))
        if (isCt(lv) == 0 || isCt(rv) == 0) {
            return comptimeError(`binary 'Pow' operand is not compile-time known`, astId)
        }
        const lp = valOf(lv); const rp = valOf(rv)
        const lt = valType(lv); const rt = valType(rv)
        if (lt == "double" || rt == "double") {
            const ld = lt == "double" ? parseDouble(interpAsStr(lp)) : parseDouble(`${interpAsInt(lp)}`)
            const rd = rt == "double" ? parseDouble(interpAsStr(rp)) : parseDouble(`${interpAsInt(rp)}`)
            return ctVal(interpDoubleOp("Pow", ld, rd))
        }
        return ctVal(interpIntOp("Pow", interpAsInt(lp), interpAsInt(rp)))
    }
    return mvRuntime(constVal(genBinary(astId)))
}
