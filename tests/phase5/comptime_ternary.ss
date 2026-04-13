// Test: compile-time ternary + short-circuit folding (D089 Phase 3)

import { assertEqual } from "@/lib/test"

function main() {
    // Ternary with comptime condition
    const a = 1 > 0 ? 10 : 20
    assertEqual(a, 10)

    const b = 0 > 1 ? 10 : 20
    assertEqual(b, 20)

    // Nested comptime ternary
    const c = 1 == 1 ? (2 > 3 ? 100 : 200) : 300
    assertEqual(c, 200)

    // Short-circuit And — comptime false left
    const d = 0 && 42
    assertEqual(d, 0)

    // Short-circuit And — comptime true left
    const e = 1 && 99
    assertEqual(e, 99)

    // Short-circuit Or — comptime true left
    const f = 1 || 42
    assertEqual(f, 1)

    // Short-circuit Or — comptime false left
    const g = 0 || 77
    assertEqual(g, 77)

    // Grouping preserves comptime
    const h = (3 + 4) * (2 + 1)
    assertEqual(h, 21)

    println("all comptime ternary tests passed")
}
