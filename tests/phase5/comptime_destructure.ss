// Test: comptime array destructuring (D088 Phase 8)
// Verifies that genDestructureArray supports comptimeDepth > 0,
// closing one of the interpreter gaps in the Zig route.

import { assertEqual } from "@/lib/test"

// Test 1: literal array destructuring
comptime {
    const [a, b] = [10, 20]
    @comptimeEmit(`function ctSum2(): int { return ${a + b} }\n`)
}

// Test 2: three-element destructuring
comptime {
    const [x, y, z] = [100, 200, 300]
    @comptimeEmit(`function ctSum3(): int { return ${x + y + z} }\n`)
}

// Test 3: destructure from intermediate variable
comptime {
    const arr = [7, 14, 21]
    const [p, q, r] = arr
    @comptimeEmit(`function ctSumIndirect(): int { return ${p + q + r} }\n`)
}

// Test 4: single-element destructuring (boundary)
comptime {
    const [only] = [42]
    @comptimeEmit(`function ctOnly(): int { return ${only} }\n`)
}

// Test 5: destructure with string element type (type boundary)
comptime {
    const [s, t] = ["hello", "world"]
    @comptimeEmit(`function ctConcat(): string { return "${s}_${t}" }\n`)
}

function main() {
    test("comptime destructure 2 elements", () => {
        assertEqual(ctSum2(), 30)
    })
    test("comptime destructure 3 elements", () => {
        assertEqual(ctSum3(), 600)
    })
    test("comptime destructure from variable", () => {
        assertEqual(ctSumIndirect(), 42)
    })
    test("comptime destructure single element", () => {
        assertEqual(ctOnly(), 42)
    })
    test("comptime destructure string elements", () => {
        assertEqual(ctConcat(), "hello_world")
    })
}
