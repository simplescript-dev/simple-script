// Test: compile-time variable propagation (D089 Phase 4)
// const variables with comptime initializers propagate through expressions

import { assertEqual } from "@/lib/test"

function main() {
    // Basic const propagation
    const x = 1 + 2
    const y = x * 3
    assertEqual(y, 9)

    // Chain of const propagation
    const a = 10
    const b = a + 5
    const c = b * 2
    assertEqual(c, 30)

    // Const in ternary condition
    const flag = 1
    const r = flag > 0 ? 100 : 200
    assertEqual(r, 100)

    // Const in short-circuit
    const t = 1 && 42
    const u = t + 8
    assertEqual(u, 50)

    // Const with bitwise
    const bits = 0xFF
    const masked = bits & 0x0F
    assertEqual(masked, 15)

    println("all comptime vars tests passed")
}
