// Comprehensive comptime interpreter tests
// Covers: external calls, recursion, loops, data structures, string/array/map methods, classes

function check(actual: int, expected: int, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} — got ${actual}, expected ${expected}`)
        exit(1)
    }
}

function checkStr(actual: string, expected: string, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} — got ${actual}, expected ${expected}`)
        exit(1)
    }
}

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
    check(r1, 720, "factorial(6)")

    const r2 = comptime { return fibonacci(10) }
    check(r2, 55, "fibonacci(10)")

    const r3 = comptime { return factorial(0) }
    check(r3, 1, "factorial(0) base case")

    const r4 = comptime { return fibonacci(0) }
    check(r4, 0, "fibonacci(0) base case")

    // ═══════════════════════════════════════
    // §2 External functions with loops
    // ═══════════════════════════════════════

    const l1 = comptime { return sumRange(1, 100) }
    check(l1, 5050, "sumRange(1,100)")

    const l2 = comptime { return gcd(48, 18) }
    check(l2, 6, "gcd(48,18)")

    const l3 = comptime { return gcd(17, 13) }
    check(l3, 1, "gcd(17,13) coprime")

    const l4 = comptime { return isPrime(97) }
    check(l4, 1, "isPrime(97)")

    const l5 = comptime { return isPrime(100) }
    check(l5, 0, "isPrime(100)")

    // ═══════════════════════════════════════
    // §3 Nested + composed external calls
    // ═══════════════════════════════════════

    const n1 = comptime { return max(factorial(3), fibonacci(8)) }
    check(n1, 21, "max(factorial(3),fibonacci(8))")

    const n2 = comptime { return clamp(factorial(5), 10, 100) }
    check(n2, 100, "clamp(120,10,100)")

    const n3 = comptime { return clamp(3, 10, 100) }
    check(n3, 10, "clamp(3,10,100)")

    const n4 = comptime { return abs(0 - sumRange(1, 10)) }
    check(n4, 55, "abs(-sumRange(1,10))")

    const n5 = comptime { return gcd(factorial(4), factorial(3)) }
    check(n5, 6, "gcd(24,6)")

    // ═══════════════════════════════════════
    // §4 Variable mutation + control flow
    // ═══════════════════════════════════════

    const v1 = comptime {
        let x = 1
        x = x + 10
        x = x * 2
        return x
    }
    check(v1, 22, "let mutation chain")

    const v2 = comptime {
        let sum = 0
        for (let i = 1; i <= 10; i++) {
            sum = sum + i
        }
        return sum
    }
    check(v2, 55, "comptime for loop")

    const v3 = comptime {
        let x = 1
        let count = 0
        do {
            x = x * 2
            count++
        } while (x < 100)
        return count
    }
    check(v3, 7, "comptime do-while")

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
    check(v4, 110, "comptime while+continue")

    const v5 = comptime {
        let total = 0
        for (let i = 0; i < 100; i++) {
            if (i == 5) { break }
            total = total + i
        }
        return total
    }
    check(v5, 10, "comptime for+break")

    // ═══════════════════════════════════════
    // §5 String methods in comptime
    // ═══════════════════════════════════════

    const s1 = comptime { return "hello world".length() }
    check(s1, 11, "string length")

    const s2 = comptime { return "hello world".indexOf("world") }
    check(s2, 6, "string indexOf")

    const s3 = comptime { return "hello world".indexOf("xyz") }
    check(s3, -1, "string indexOf miss")

    const s4 = comptime { return "hello world".substring(0, 5) }
    checkStr(s4, "hello", "string substring")

    const s5 = comptime { return "hello world".replace("world", "comptime") }
    checkStr(s5, "hello comptime", "string replace")

    const s6 = comptime { return "hello".startsWith("hel") }
    check(s6, 1, "string startsWith true")

    const s7 = comptime { return "hello".startsWith("xyz") }
    check(s7, 0, "string startsWith false")

    const s8 = comptime { return "hello".endsWith("llo") }
    check(s8, 1, "string endsWith true")

    const s9 = comptime { return "hello".charAt(1) }
    checkStr(s9, "e", "string charAt")

    const s10 = comptime { return "hello".includes("ell") }
    check(s10, 1, "string includes true")

    const s11 = comptime { return "abc".repeat(3) }
    checkStr(s11, "abcabcabc", "string repeat")

    const s12 = comptime { return repeatStr("ha", 3) }
    checkStr(s12, "hahaha", "external string builder")

    // ═══════════════════════════════════════
    // §6 Array methods in comptime
    // ═══════════════════════════════════════

    const a1 = comptime {
        let arr = [10, 20, 30]
        return arr.length()
    }
    check(a1, 3, "array length")

    const a2 = comptime {
        let arr = [1, 2, 3]
        arr = arr.push(4)
        return arr.length()
    }
    check(a2, 4, "array push + length")

    const a3 = comptime {
        let arr = [10, 20, 30]
        return arr.indexOf(20)
    }
    check(a3, 1, "array indexOf")

    const a4 = comptime {
        let arr = [10, 20, 30]
        return arr.indexOf(99)
    }
    check(a4, -1, "array indexOf miss")

    const a5 = comptime {
        let arr = [1, 2, 3, 4, 5]
        const sliced = arr.slice(1, 4)
        return sliced.length()
    }
    check(a5, 3, "array slice length")

    const a6 = comptime {
        let arr = [10, 20, 30]
        return arr.join("-")
    }
    checkStr(a6, "10-20-30", "array join")

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
    check(m1, 3, "map size")

    const m2 = comptime {
        let m = new Map()
        m.set("key", "val")
        return m.has("key")
    }
    check(m2, 1, "map has true")

    const m3 = comptime {
        let m = new Map()
        return m.has("missing")
    }
    check(m3, 0, "map has false")

    const m4 = comptime {
        let m = new Map()
        m.set("a", "1")
        m.set("b", "2")
        m.delete("a")
        return m.size()
    }
    check(m4, 1, "map delete + size")

    const m5 = comptime {
        let m = new Map()
        m["x"] = "hello"
        m["y"] = "world"
        return `${m["x"]} ${m["y"]}`
    }
    checkStr(m5, "hello world", "map index syntax")

    // ═══════════════════════════════════════
    // §8 Class features in comptime
    // ═══════════════════════════════════════

    const c1 = comptime {
        class Vec2 { x: int; y: int }
        const v = new Vec2(3, 4)
        return v.x * v.x + v.y * v.y
    }
    check(c1, 25, "class field arithmetic")

    const c2 = comptime {
        class Pair { first: int; second: int }
        const p = new Pair(10, 20)
        return p.first + p.second
    }
    check(c2, 30, "class named fields")

    const c3 = comptime {
        class Counter { value: int }
        let c = new Counter(0)
        c.value = c.value + 1
        c.value = c.value + 1
        c.value = c.value + 1
        return c.value
    }
    check(c3, 3, "class field mutation")

    // ═══════════════════════════════════════
    // §9 Boolean + comparison operators
    // ═══════════════════════════════════════

    const b1 = comptime {
        const a = 1 > 0
        const b = 2 < 3
        if (a && b) { return 1 }
        return 0
    }
    check(b1, 1, "boolean AND")

    const b2 = comptime {
        const a = 1 > 2
        const b = 3 > 2
        if (a || b) { return 1 }
        return 0
    }
    check(b2, 1, "boolean OR")

    const b3 = comptime {
        if (!(1 > 2)) { return 1 }
        return 0
    }
    check(b3, 1, "boolean NOT")

    const b4 = comptime {
        const x = 5
        if (x >= 3 && x <= 7) { return 1 }
        return 0
    }
    check(b4, 1, "range check")

    // ═══════════════════════════════════════
    // §10 Edge cases
    // ═══════════════════════════════════════

    const e1 = comptime { return 0 }
    check(e1, 0, "zero literal")

    const e2 = comptime { return 0 - 42 }
    check(e2, -42, "negative result")

    const e3 = comptime { return "" }
    checkStr(e3, "", "empty string")

    const e4 = comptime {
        let arr: Array<int> = []
        return arr.length()
    }
    check(e4, 0, "empty array length")

    const e5 = comptime {
        let m = new Map()
        return m.size()
    }
    check(e5, 0, "empty map size")

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
    check(e6, 42, "deeply nested if")

    println("all 52 comprehensive comptime tests passed")
}
