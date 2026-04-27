// D141 Phase 3 — H13 非结构化 callee skip
// callee `takesFn(cb: fn):int` 单字符串 "fn" 无形参信息 → 反推 skip(非结构化不硬错)
// 用户必须显式注解 `(x: int) =>`,既有 typed lambda 路径不破
import { assertEqual } from "@/lib/test"

function takesFn(cb: fn): int {
    return 0
}

function main() {
    const r = takesFn((x: int) => x + 1)
    assertEqual(r, 0)
}
