// Test: comptimeDepth dispatch vs operand ct-ness — D094 validation
// Verifies that "comptime context" and "operand known-ness" are orthogonal

import { assertEq } from "./import/asserts"

function add(a: int, b: int): int { return a + b }

function main() {
    // Case 1: Pure expression auto-folds outside comptime block
    const c1 = 1 + 2
    assertEq(c1, 3, "case1: pure expr fold")

    // Case 2: Call external function from comptime block
    const c2 = comptime {
        return add(10, 20)
    }
    assertEq(c2, 30, "case2: comptime external call")

    // Case 3: Array index assign + read in comptime
    const c3 = comptime {
        let a = [1, 2, 3]
        a[1] = 42
        return a[1]
    }
    assertEq(c3, 42, "case3: comptime index assign")

    // Case 4: Template literal auto-folds with ct operands
    const name = "world"
    const greeting = `hello ${name}`
    assertEq(greeting, "hello world", "case4: template fold")

    // Case 5: Comptime block with class instantiation
    const c5 = comptime {
        class Point { x: int; y: int }
        const p = new Point(3, 4)
        return p.x + p.y
    }
    assertEq(c5, 7, "case5: comptime class fields")

    // Case 6: Comptime throw not triggered on success path
    const c6 = comptime {
        const ok = 1
        if (ok != 1) {
            throw("should not reach")
        }
        return 42
    }
    assertEq(c6, 42, "case6: comptime throw skip")

    // Case 7: Comptime map index assign + read
    const c7 = comptime {
        let m = new Map()
        m["key"] = "value"
        return m["key"]
    }
    assertEq(c7, "value", "case7: comptime map index")

    // Case 8: Postfix increment in comptime
    const c8 = comptime {
        let x = 10
        x++
        return x
    }
    assertEq(c8, 11, "case8: comptime postfix")

    // Case 9: Nested comptime — function defined and called in comptime
    const c9 = comptime {
        function mul(a: int, b: int): int { return a * b }
        return mul(6, 7)
    }
    assertEq(c9, 42, "case9: comptime local func")

    // Case 10: Comptime enum access
    const c10 = comptime {
        enum Color { Red, Green, Blue }
        return Color.Blue
    }
    assertEq(c10, 2, "case10: comptime enum")

    println("all 10 comptime dispatch tests passed")
}
