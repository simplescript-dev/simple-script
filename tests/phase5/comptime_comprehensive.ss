// Comprehensive comptime interpreter tests
// Covers: external calls, recursion, loops, data structures, string/array/map methods, classes

import { assertEq } from "./import/asserts"

// ── External helper functions ──

function factorial(n: int): int {
    if (n <= 1) { return 1 }
    return n * factorial(n - 1)
}

function fibonacci(n: int): int {
    if (n <= 0) { return 0 }
    if (n == 1) { return 1 }
    return fibonacci(n - 1) + fibonacci(n - 2)
}

function sumRange(lo: int, hi: int): int {
    let total = 0
    let i = lo
    while (i <= hi) {
        total = total + i
        i = i + 1
    }
    return total
}

function abs(x: int): int {
    if (x < 0) { return 0 - x }
    return x
}

function max(a: int, b: int): int {
    if (a > b) { return a }
    return b
}

function min(a: int, b: int): int {
    if (a < b) { return a }
    return b
}

function clamp(x: int, lo: int, hi: int): int {
    return max(lo, min(x, hi))
}

function gcd(a: int, b: int): int {
    let x = a
    let y = b
    while (y != 0) {
        const t = y
        y = x % t
        x = t
    }
    return x
}

function isPrime(n: int): int {
    if (n < 2) { return 0 }
    let i = 2
    while (i * i <= n) {
        if (n % i == 0) { return 0 }
        i = i + 1
    }
    return 1
}

function repeatStr(s: string, n: int): string {
    let result = ""
    let i = 0
    while (i < n) {
        result = `${result}${s}`
        i = i + 1
    }
    return result
}

function main() {
    // ═══════════════════════════════════════
    // §1 Recursive external functions
    // ═══════════════════════════════════════

    const r1 = comptime { return factorial(6) }
    assertEq(r1, 720, "factorial(6)")

    const r2 = comptime { return fibonacci(10) }
    assertEq(r2, 55, "fibonacci(10)")

    const r3 = comptime { return factorial(0) }
    assertEq(r3, 1, "factorial(0) base case")

    const r4 = comptime { return fibonacci(0) }
    assertEq(r4, 0, "fibonacci(0) base case")

    // ═══════════════════════════════════════
    // §2 External functions with loops
    // ═══════════════════════════════════════

    const l1 = comptime { return sumRange(1, 100) }
    assertEq(l1, 5050, "sumRange(1,100)")

    const l2 = comptime { return gcd(48, 18) }
    assertEq(l2, 6, "gcd(48,18)")

    const l3 = comptime { return gcd(17, 13) }
    assertEq(l3, 1, "gcd(17,13) coprime")

    const l4 = comptime { return isPrime(97) }
    assertEq(l4, 1, "isPrime(97)")

    const l5 = comptime { return isPrime(100) }
    assertEq(l5, 0, "isPrime(100)")

    // ═══════════════════════════════════════
    // §3 Nested + composed external calls
    // ═══════════════════════════════════════

    const n1 = comptime { return max(factorial(3), fibonacci(8)) }
    assertEq(n1, 21, "max(factorial(3),fibonacci(8))")

    const n2 = comptime { return clamp(factorial(5), 10, 100) }
    assertEq(n2, 100, "clamp(120,10,100)")

    const n3 = comptime { return clamp(3, 10, 100) }
    assertEq(n3, 10, "clamp(3,10,100)")

    const n4 = comptime { return abs(0 - sumRange(1, 10)) }
    assertEq(n4, 55, "abs(-sumRange(1,10))")

    const n5 = comptime { return gcd(factorial(4), factorial(3)) }
    assertEq(n5, 6, "gcd(24,6)")

    // ═══════════════════════════════════════
    // §4 Variable mutation + control flow
    // ═══════════════════════════════════════

    const v1 = comptime {
        let x = 1
        x = x + 10
        x = x * 2
        return x
    }
    assertEq(v1, 22, "let mutation chain")

    const v2 = comptime {
        let sum = 0
        for (let i = 1; i <= 10; i++) {
            sum = sum + i
        }
        return sum
    }
    assertEq(v2, 55, "comptime for loop")

    const v3 = comptime {
        let x = 1
        let count = 0
        do {
            x = x * 2
            count++
        } while (x < 100)
        return count
    }
    assertEq(v3, 7, "comptime do-while")

    const v4 = comptime {
        let result = 0
        let i = 0
        while (i < 20) {
            i = i + 1
            if (i % 2 != 0) { continue }
            result = result + i
        }
        return result
    }
    assertEq(v4, 110, "comptime while+continue")

    const v5 = comptime {
        let total = 0
        for (let i = 0; i < 100; i++) {
            if (i == 5) { break }
            total = total + i
        }
        return total
    }
    assertEq(v5, 10, "comptime for+break")

    // ═══════════════════════════════════════
    // §5 String methods in comptime
    // ═══════════════════════════════════════

    const s1 = comptime { return "hello world".length() }
    assertEq(s1, 11, "string length")

    const s2 = comptime { return "hello world".indexOf("world") }
    assertEq(s2, 6, "string indexOf")

    const s3 = comptime { return "hello world".indexOf("xyz") }
    assertEq(s3, -1, "string indexOf miss")

    const s4 = comptime { return "hello world".substring(0, 5) }
    assertEq(s4, "hello", "string substring")

    const s5 = comptime { return "hello world".replace("world", "comptime") }
    assertEq(s5, "hello comptime", "string replace")

    const s6 = comptime { return "hello".startsWith("hel") }
    assertEq(s6, 1, "string startsWith true")

    const s7 = comptime { return "hello".startsWith("xyz") }
    assertEq(s7, 0, "string startsWith false")

    const s8 = comptime { return "hello".endsWith("llo") }
    assertEq(s8, 1, "string endsWith true")

    const s9 = comptime { return "hello".charAt(1) }
    assertEq(s9, "e", "string charAt")

    const s10 = comptime { return "hello".includes("ell") }
    assertEq(s10, 1, "string includes true")

    const s11 = comptime { return "abc".repeat(3) }
    assertEq(s11, "abcabcabc", "string repeat")

    const s12 = comptime { return repeatStr("ha", 3) }
    assertEq(s12, "hahaha", "external string builder")

    // ═══════════════════════════════════════
    // §6 Array methods in comptime
    // ═══════════════════════════════════════

    const a1 = comptime {
        let arr = [10, 20, 30]
        return arr.length()
    }
    assertEq(a1, 3, "array length")

    const a2 = comptime {
        let arr = [1, 2, 3]
        arr = arr.push(4)
        return arr.length()
    }
    assertEq(a2, 4, "array push + length")

    const a3 = comptime {
        let arr = [10, 20, 30]
        return arr.indexOf(20)
    }
    assertEq(a3, 1, "array indexOf")

    const a4 = comptime {
        let arr = [10, 20, 30]
        return arr.indexOf(99)
    }
    assertEq(a4, -1, "array indexOf miss")

    const a5 = comptime {
        let arr = [1, 2, 3, 4, 5]
        const sliced = arr.slice(1, 4)
        return sliced.length()
    }
    assertEq(a5, 3, "array slice length")

    const a6 = comptime {
        let arr = [10, 20, 30]
        return arr.join("-")
    }
    assertEq(a6, "10-20-30", "array join")

    // ═══════════════════════════════════════
    // §7 Map methods in comptime
    // ═══════════════════════════════════════

    const m1 = comptime {
        let m = new Map()
        m.set("a", "1")
        m.set("b", "2")
        m.set("c", "3")
        return m.size()
    }
    assertEq(m1, 3, "map size")

    const m2 = comptime {
        let m = new Map()
        m.set("key", "val")
        return m.has("key")
    }
    assertEq(m2, 1, "map has true")

    const m3 = comptime {
        let m = new Map()
        return m.has("missing")
    }
    assertEq(m3, 0, "map has false")

    const m4 = comptime {
        let m = new Map()
        m.set("a", "1")
        m.set("b", "2")
        m.delete("a")
        return m.size()
    }
    assertEq(m4, 1, "map delete + size")

    const m5 = comptime {
        let m = new Map()
        m["x"] = "hello"
        m["y"] = "world"
        return `${m["x"]} ${m["y"]}`
    }
    assertEq(m5, "hello world", "map index syntax")

    // ═══════════════════════════════════════
    // §8 Class features in comptime
    // ═══════════════════════════════════════

    const c1 = comptime {
        class Vec2 { x: int; y: int }
        const v = new Vec2(3, 4)
        return v.x * v.x + v.y * v.y
    }
    assertEq(c1, 25, "class field arithmetic")

    const c2 = comptime {
        class Pair { first: int; second: int }
        const p = new Pair(10, 20)
        return p.first + p.second
    }
    assertEq(c2, 30, "class named fields")

    const c3 = comptime {
        class Counter { value: int }
        let c = new Counter(0)
        c.value = c.value + 1
        c.value = c.value + 1
        c.value = c.value + 1
        return c.value
    }
    assertEq(c3, 3, "class field mutation")

    // ═══════════════════════════════════════
    // §9 Boolean + comparison operators
    // ═══════════════════════════════════════

    const b1 = comptime {
        const a = 1 > 0
        const b = 2 < 3
        if (a && b) { return 1 }
        return 0
    }
    assertEq(b1, 1, "boolean AND")

    const b2 = comptime {
        const a = 1 > 2
        const b = 3 > 2
        if (a || b) { return 1 }
        return 0
    }
    assertEq(b2, 1, "boolean OR")

    const b3 = comptime {
        if (!(1 > 2)) { return 1 }
        return 0
    }
    assertEq(b3, 1, "boolean NOT")

    const b4 = comptime {
        const x = 5
        if (x >= 3 && x <= 7) { return 1 }
        return 0
    }
    assertEq(b4, 1, "range check")

    // ═══════════════════════════════════════
    // §10 Edge cases
    // ═══════════════════════════════════════

    const e1 = comptime { return 0 }
    assertEq(e1, 0, "zero literal")

    const e2 = comptime { return 0 - 42 }
    assertEq(e2, -42, "negative result")

    const e3 = comptime { return "" }
    assertEq(e3, "", "empty string")

    const e4 = comptime {
        let arr: Array<int> = []
        return arr.length()
    }
    assertEq(e4, 0, "empty array length")

    const e5 = comptime {
        let m = new Map()
        return m.size()
    }
    assertEq(e5, 0, "empty map size")

    const e6 = comptime {
        if (1 == 1) {
            if (2 == 2) {
                if (3 == 3) {
                    return 42
                }
            }
        }
        return 0
    }
    assertEq(e6, 42, "deeply nested if")

    println("all 52 comprehensive comptime tests passed")
}
