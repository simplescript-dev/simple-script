// D098 §决策 2 §新张力 2 / D110 §决策 2 — Phase A → B 接口边界
// Value 句柄访问器:屏蔽 Phase A tagged int(ctVal bit 30)vs Phase B
// InternPool index 的差异。调用方传 mv(MaybeVal.val 即 Value 句柄,
// 含 bit 30 编码),accessor 内部完成 strip + 取 payload/type。
// Phase B(D111+)只换函数体走 pool.load(valId).{payload,tag},
// 调用方代码不变 —— 这是 Phase B 启动的接口边界。

function valOf(valId: int): int {
    return payload(valId)
}

function valType(valId: int): string {
    return interpType(payload(valId))
}
