// INSTANCEOF + AS 二元 op 子文件(原 eval_expr.ss BINARY 迁出)
// 单边 op(左 obj + 右 className 字符串 nGetS1(rightId),不 eval expr);ct path 反射
// 未支持 loud error;runtime path delegate genBinary(genBinary 内 isinstance + As 子路径
// 各自单边 genExpr(leftId),子函数不 eager 上移避 double-eval bug — 接口扩 lPreReg 留独立轮)

function evalInstanceofOrAs(op: string, astId: int): int {
    if (comptimeMustBeKnown == 1) {
        return comptimeError(`operator '${op}' not supported`, astId)
    }
    return mvRuntime(constVal(genBinary(astId)))
}
