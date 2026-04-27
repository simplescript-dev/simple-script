// D141 Phase 3 — H1 单参 untyped lambda 反推
// callee `takesSetter(setter: fn(int):int):int` 结构化签名 → ARROW_FUNC `(x) =>`
// PARAM s2="" 反推回填 "int" → IR `define i32 @__arrow_1(i32 %x.arg)` GREEN
import { assertEqual } from "@/lib/test"

function takesSetter(setter: fn(int):int): int {
    return setter(42)
}

function main() {
    const r = takesSetter((x) => x + 1)
    assertEqual(r, 43)
}
