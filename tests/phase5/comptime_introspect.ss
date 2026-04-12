// Test: comptime introspection builtins — hasField, hasMethod, compileError

import { assertEqual, assertTrue } from "@/lib/test"

class Player {
    name: string
    health: int
    score: double

    function greet(): string {
        return "hello"
    }

    function takeDamage(amount: int): int {
        return this.health - amount
    }
}

// ── hasField / hasMethod tests via @comptimeEmit ────────────

comptime {
    // hasField checks
    const hf1 = hasField("Player", "name")
    const hf2 = hasField("Player", "health")
    const hf3 = hasField("Player", "missing")
    const hf4 = hasField("NonExistent", "x")

    // hasMethod checks
    const hm1 = hasMethod("Player", "greet")
    const hm2 = hasMethod("Player", "takeDamage")
    const hm3 = hasMethod("Player", "missing")
    // Exact match — "get" should not match "getString" on Map
    const hm4 = hasMethod("Map", "get")
    const hm5 = hasMethod("Map", "getStr")

    @comptimeEmit(`
function testHasFieldName(): int { return ${hf1} }
function testHasFieldHealth(): int { return ${hf2} }
function testHasFieldMissing(): int { return ${hf3} }
function testHasFieldBadClass(): int { return ${hf4} }
function testHasMethodGreet(): int { return ${hm1} }
function testHasMethodTakeDamage(): int { return ${hm2} }
function testHasMethodMissing(): int { return ${hm3} }
function testHasMethodMapGet(): int { return ${hm4} }
function testHasMethodMapGetStr(): int { return ${hm5} }
`)
}

// ── compileError test — validated via a guard ───────────────
// We can't test that compileError aborts compilation (that would make THIS test fail).
// Instead we test the guard pattern: only call compileError when validation fails.

comptime {
    // This should NOT fire — Player has "name"
    if (hasField("Player", "name") == 0) {
        compileError("Player must have 'name' field")
    }
}

function main() {
    test("hasField positive", () => {
        assertEqual(testHasFieldName(), 1)
        assertEqual(testHasFieldHealth(), 1)
    })
    test("hasField negative", () => {
        assertEqual(testHasFieldMissing(), 0)
        assertEqual(testHasFieldBadClass(), 0)
    })
    test("hasMethod positive", () => {
        assertEqual(testHasMethodGreet(), 1)
        assertEqual(testHasMethodTakeDamage(), 1)
    })
    test("hasMethod negative", () => {
        assertEqual(testHasMethodMissing(), 0)
    })
    test("hasMethod exact match", () => {
        assertEqual(testHasMethodMapGet(), 1)
        assertEqual(testHasMethodMapGetStr(), 0)
    })
}
