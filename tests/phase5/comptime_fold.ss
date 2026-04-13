// Test: compile-time constant folding (D089 Phase 2)
// Binary and unary int/bool ops on literals are folded at compile time

import { assertEqual } from "@/lib/test"

function main() {
    // Basic arithmetic folding
    const a = 1 + 2
    assertEqual(a, 3)

    const b = 10 * 5 - 7
    assertEqual(b, 43)

    const c = 100 / 4
    assertEqual(c, 25)

    const d = 17 % 5
    assertEqual(d, 2)

    // Nested expression folding
    const e = (3 + 4) * (2 + 1)
    assertEqual(e, 21)

    // Bitwise folding
    const f = 1 << 10
    assertEqual(f, 1024)

    const g = 255 & 15
    assertEqual(g, 15)

    const h = 10 | 5
    assertEqual(h, 15)

    const i = 15 ^ 9
    assertEqual(i, 6)

    // Comparison folding
    const j = 3 > 2
    assertEqual(j, 1)

    const k = 1 == 2
    assertEqual(k, 0)

    // Unary folding
    const m = -42
    assertEqual(m, -42)

    const n = !0
    assertEqual(n, 1)

    const o = ~0
    assertEqual(o, -1)

    println("all comptime fold tests passed")
}
