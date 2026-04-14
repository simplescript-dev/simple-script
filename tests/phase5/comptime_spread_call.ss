// Test: comptime spread in function call args (D088 Phase 8)
// Verifies that genValCtCall expands SPREAD_ELEM in argument list,
// closing one of the interpreter gaps in the Zig route.

import { assertEqual } from "@/lib/test"

// Test 1: full spread from array literal
comptime {
    function add3a(a: int, b: int, c: int): int { return a + b + c }
    const r1 = add3a(...[10, 20, 30])
    @comptimeEmit(`function ctAdd3Lit(): int { return ${r1} }\n`)
}

// Test 2: full spread from intermediate variable
comptime {
    function add3b(a: int, b: int, c: int): int { return a + b + c }
    const xs = [1, 2, 3]
    const r2 = add3b(...xs)
    @comptimeEmit(`function ctAdd3Var(): int { return ${r2} }\n`)
}

// Test 3: mixed — leading positional + spread for rest
comptime {
    function add3c(a: int, b: int, c: int): int { return a + b + c }
    const rest = [20, 30]
    const r3 = add3c(10, ...rest)
    @comptimeEmit(`function ctMix(): int { return ${r3} }\n`)
}

// Test 4: single-element spread (boundary)
comptime {
    function id1(a: int): int { return a }
    const one = [42]
    const r4 = id1(...one)
    @comptimeEmit(`function ctOne(): int { return ${r4} }\n`)
}

// Test 5: string array spread (type boundary)
comptime {
    function concat2(a: string, b: string): string { return a + "_" + b }
    const parts: Array<string> = ["hello", "world"]
    const r5 = concat2(...parts)
    @comptimeEmit(`function ctStr(): string { return "${r5}" }\n`)
}

// Test 6: empty array spread (zero-arg boundary)
comptime {
    function noArgs(): int { return 7 }
    const empty: Array<int> = []
    const r6 = noArgs(...empty)
    @comptimeEmit(`function ctEmpty(): int { return ${r6} }\n`)
}

// Test 7: trailing positional after spread (e.g. f(...head, last))
comptime {
    function add3d(a: int, b: int, c: int): int { return a + b + c }
    const head = [1, 2]
    const r7 = add3d(...head, 100)
    @comptimeEmit(`function ctTail(): int { return ${r7} }\n`)
}

function main() {
    test("comptime spread literal array", () => {
        assertEqual(ctAdd3Lit(), 60)
    })
    test("comptime spread variable array", () => {
        assertEqual(ctAdd3Var(), 6)
    })
    test("comptime spread leading positional", () => {
        assertEqual(ctMix(), 60)
    })
    test("comptime spread single element", () => {
        assertEqual(ctOne(), 42)
    })
    test("comptime spread string array", () => {
        assertEqual(ctStr(), "hello_world")
    })
    test("comptime spread empty array (zero args)", () => {
        assertEqual(ctEmpty(), 7)
    })
    test("comptime spread trailing positional", () => {
        assertEqual(ctTail(), 103)
    })
}
