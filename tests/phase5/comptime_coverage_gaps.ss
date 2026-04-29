function check(actual: int, expected: int, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} — got ${actual}, expected ${expected}`)
        exit(1)
    }
}

function checkStr(actual: string, expected: string, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} — got '${actual}', expected '${expected}'`)
        exit(1)
    }
}

// ── Generic function for comptime test ──
function identity<T>(x: T): T {
    return x
}

function add<T>(a: T, b: T): T {
    return a + b
}

// ── Class hierarchy for super test ──
class Animal {
    name: string
    function speak(): string {
        return this.name
    }
}

class Dog extends Animal {
    function speak(): string {
        return `${super.speak()} barks`
    }
}

function main() {
    // ── Gap 1: Pow operator ──
    const p1 = comptime { return 2 ** 8 }
    check(p1, 256, "2 ** 8")

    const p2 = comptime { return 3 ** 4 }
    check(p2, 81, "3 ** 4")

    const p3 = comptime { return 10 ** 0 }
    check(p3, 1, "10 ** 0")

    const p4 = comptime { return 5 ** 1 }
    check(p4, 5, "5 ** 1")

    // ── Gap 2: ...rest destructuring ──
    const r1 = comptime {
        const arr = [10, 20, 30, 40, 50]
        const [first, ...rest] = arr
        comptimeAssert(first == 10, "first element")
        return rest.length()
    }
    check(r1, 4, "rest length")

    const r2 = comptime {
        const arr = [1, 2, 3]
        const [a, b, ...tail] = arr
        comptimeAssert(a == 1, "a")
        comptimeAssert(b == 2, "b")
        return tail[0]
    }
    check(r2, 3, "rest element access")

    // ── Gap 3: super.method() ──
    const s1 = comptime {
        class Base {
            value: int
            function getVal(): int { return this.value }
        }
        class Child extends Base {
            function getVal(): int { return super.getVal() + 100 }
        }
        const c = new Child(42)
        return c.getVal()
    }
    check(s1, 142, "super.method() returns parent + 100")

    // ── Gap 4: Generic function call ──
    const g1 = comptime { return identity(42) }
    check(g1, 42, "generic identity<int>")

    const g2 = comptime { return add(10, 20) }
    check(g2, 30, "generic add<int>")

    println("All comptime coverage gap tests passed")
}
