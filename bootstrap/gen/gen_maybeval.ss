// D098 §决策 2 §新张力 2 — Phase B InternPool 实化
// Value 句柄访问器:屏蔽 Phase A tagged int(ctVal bit 30)vs Phase B
// InternPool index 的差异。调用方传 mv(MaybeVal.val 即 Value 句柄),
// accessor 内部完成 strip + 取 payload/type。
//
// Phase B 起步:valOf 物理等价 payload(valId) —— InternPool dedup 后
// pool index = backing tvId(stable dedup id),`payload(valId)` ≡
// `pool.load(tvId).payload`(invariant:interpNew* 5 入口全走 pool)。
// valType = interpType ∘ payload:strip Value 句柄后走 interpType 单一 kind 源
// (tvKindByPool 反查)。D093 §差距 #3 后 interpType 本身即 internPoolKeyOf 反查,valType
// 不再自带反查副本(与 interpType 合一,消除重复查表 — flip 前 interpType 走 tvKindOf 存储才需 pre-check)。

function valOf(valId: int): int {
    return payload(valId)
}

function valType(valId: int): string {
    return interpType(payload(valId))
}
