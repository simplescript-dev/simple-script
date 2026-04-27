// D141 Phase 3 — H6 显式注解 > 推断
// ARROW_FUNC `(x: double) =>` PARAM s2="double" 已设 → 反推 skip(显式优先)
// 现有 D137 §F9 typed lambda 注解路径不破
import { assertEqual } from "@/lib/test"

function takesSetter(cb: fn(double):double): double {
    return cb(1.0)
}

function main() {
    const r = takesSetter((x: double) => x * 2.0)
    assertEqual(r, 2.0)
}
