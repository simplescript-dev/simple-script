// Test: @comptimeEmit — compile SS source strings at comptime (D087 Phase 3c)
// Unlike emit() which injects raw LLVM IR, @comptimeEmit takes SimpleScript source
// code and compiles it, enabling high-level code generation from @typeInfo reflection.

import { assertEqual } from "@/lib/test"

// ── Test 1: Simple function generation ──────────────────────

comptime {
    @comptimeEmit("function getFortyTwo(): int { return 42 }\n")
}

// ── Test 2: Generate from @typeInfo reflection ──────────────

class Point {
    x: int
    y: int
}

comptime {
    const info = @typeInfo(Point)
    const fields = info.fields
    let code = ""
    let i = 0
    while (i < fields.length()) {
        const f = fields[i]
        const fname = f.name
        const ftype = f.type
        code = code + `function getPoint_${fname}(p: Point): ${ftype} { return p.${fname} }\n`
        i = i + 1
    }
    @comptimeEmit(code)
}

// ── Test 3: Multiple @comptimeEmit in one block ─────────────

comptime {
    @comptimeEmit("function addInts(a: int, b: int): int { return a + b }\n")
    @comptimeEmit("function mulInts(a: int, b: int): int { return a * b }\n")
}

// ── Test 4: Template-built function body ────────────────────

comptime {
    const n = 100
    @comptimeEmit(`function getConst(): int { return ${n} }\n`)
}

function main() {
    test("comptimeEmit simple function", () => {
        assertEqual(getFortyTwo(), 42)
    })
    test("comptimeEmit from @typeInfo", () => {
        const p = new Point(x: 10, y: 20)
        assertEqual(getPoint_x(p), 10)
        assertEqual(getPoint_y(p), 20)
    })
    test("comptimeEmit multiple in one block", () => {
        assertEqual(addInts(3, 4), 7)
        assertEqual(mulInts(3, 4), 12)
    })
    test("comptimeEmit with template value", () => {
        assertEqual(getConst(), 100)
    })
}
