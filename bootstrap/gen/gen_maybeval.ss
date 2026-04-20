// D098 §决策 2 §新张力 2 / D110 §决策 2 / D111 §决策 2 — Phase B InternPool 实化
// Value 句柄访问器:屏蔽 Phase A tagged int(ctVal bit 30)vs Phase B
// InternPool index 的差异。调用方传 mv(MaybeVal.val 即 Value 句柄),
// accessor 内部完成 strip + 取 payload/type。
//
// Phase B 起步:valOf 物理等价 payload(valId) —— InternPool dedup 后
// pool index = backing tvId(stable dedup id),`payload(valId)` ≡
// `pool.load(tvId).payload`(invariant:interpNew* 5 入口全走 pool)。
// valType 经 internPoolKeyOf 反查 key,split "|" 取 tag,替代 D092
// tvKindOf 直读,建立 valType "走 pool 反查" 的物理不变。

function valOf(valId: int): int {
    return payload(valId)
}

function valType(valId: int): string {
    const tvId = payload(valId)
    if (internPoolKeyOf.has(`${tvId}`) == 1) {
        const key = internPoolKeyOf.getString(`${tvId}`)
        const barAt = key.indexOf("|")
        return key.substring(0, barAt)
    }
    return interpType(tvId)
}
