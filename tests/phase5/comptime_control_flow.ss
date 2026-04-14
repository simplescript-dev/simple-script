// Test: D089 Phase 5 — comptime control flow + higher-order methods
//
// Verifies that the new gen-layer comptime path handles:
//   1. Array higher-order methods (map/filter/reduce) with arrow callbacks
//   2. Switch on string/int
//   3. Do-while loops
//   4. Try/catch/finally (no throw — body + finally run)

import { assertEqual } from "@/lib/test"

comptime {
    const arr = [1, 2, 3, 4, 5]
    const doubled = arr.map((x: int): int => x * 2)
    const sum = arr.reduce((a: int, b: int): int => a + b, 0)
    const evens = arr.filter((x: int): int => x % 2 == 0)

    @comptimeEmit(`
function ctDoubledJoin(): string { return "${doubled.join(",")}" }
function ctSum(): int { return ${sum} }
function ctEvensLen(): int { return ${evens.length()} }
`)
}

comptime {
    const kind = "http"
    let status = 0
    switch (kind) {
        case "http" -> status = 200
        case "err" -> status = 500
        default -> status = 0
    }

    const n = 2
    let label = ""
    switch (n) {
        case 1 -> label = "one"
        case 2 -> label = "two"
        case 3 -> label = "three"
        default -> label = "other"
    }

    @comptimeEmit(`
function ctStatus(): int { return ${status} }
function ctLabel(): string { return "${label}" }
`)
}

comptime {
    let dwSum = 0
    let i = 1
    do {
        dwSum = dwSum + i
        i = i + 1
    } while (i <= 5)

    @comptimeEmit(`
function ctDoSum(): int { return ${dwSum} }
`)
}

comptime {
    let mark = 0
    try {
        mark = 1
    } catch (e) {
        mark = 99
    } finally {
        mark = mark + 10
    }

    @comptimeEmit(`
function ctTryMark(): int { return ${mark} }
`)
}

function main() {
    test("comptime array.map + join", () => { assertEqual(ctDoubledJoin(), "2,4,6,8,10") })
    test("comptime array.reduce", () => { assertEqual(ctSum(), 15) })
    test("comptime array.filter", () => { assertEqual(ctEvensLen(), 2) })
    test("comptime switch on string", () => { assertEqual(ctStatus(), 200) })
    test("comptime switch on int", () => { assertEqual(ctLabel(), "two") })
    test("comptime do-while", () => { assertEqual(ctDoSum(), 15) })
    test("comptime try/finally", () => { assertEqual(ctTryMark(), 11) })
}
