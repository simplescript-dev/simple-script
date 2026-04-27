// D141 Phase 3 — H2 多参 untyped lambda 反推
// callee `takesBi(cb: fn(int,string):string):string` 结构化签名 →
// ARROW_FUNC `(n, s) =>` PARAM s2 反推回填 P0="int" + P1="string" →
// IR `define ptr @__arrow_1(i32 %n.arg, ptr %s.arg)` GREEN
import { assertEqual } from "@/lib/test"

function takesBi(cb: fn(int, string):string): string {
    return cb(7, "hi")
}

function main() {
    const r = takesBi((n, s) => `${s}${n}`)
    assertEqual(r, "hi7")
}
