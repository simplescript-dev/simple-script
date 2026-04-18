// D099 §步骤 0:evalExpr 最小骨架(D098 §决策 1 Phase A)
// 编码(Phase A 纯 int,不建 class):
//   mv >= 0   → known=true,  val = mv           (Value 句柄,通常是 ctVal tagged int)
//   mv <= -2  → known=false, regId = -mv - 1   (regTable 1-based 索引)
//   mv == -1  → error 哨兵,禁止 reg()
//
// 步骤 0 最小骨架:仅建 evalExpr 空壳返回 error 哨兵 -1。
// helpers(mvKnown/mvRuntime/mvError/mvKnownOf/mvValOf)挪到步骤 1
// 随 BINARY 合并期第一次使用时建,那时可用 genValBinary 删除抵消 M7b。

function evalExpr(astId: int): int {
    return 0 - 1
}
