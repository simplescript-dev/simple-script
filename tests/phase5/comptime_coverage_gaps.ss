import { assertEq } from "./import/asserts"

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
    assertEq(p1, 256, "2 ** 8")

    const p2 = comptime { return 3 ** 4 }
    assertEq(p2, 81, "3 ** 4")

    const p3 = comptime { return 10 ** 0 }
    assertEq(p3, 1, "10 ** 0")

    const p4 = comptime { return 5 ** 1 }
    assertEq(p4, 5, "5 ** 1")

    // ── Gap 2: ...rest destructuring ──
    const r1 = comptime {
        const arr = [10, 20, 30, 40, 50]
        const [first, ...rest] = arr
        comptimeAssert(first == 10, "first element")
        return rest.length()
    }
    assertEq(r1, 4, "rest length")

    const r2 = comptime {
        const arr = [1, 2, 3]
        const [a, b, ...tail] = arr
        comptimeAssert(a == 1, "a")
        comptimeAssert(b == 2, "b")
        return tail[0]
    }
    assertEq(r2, 3, "rest element access")

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
    assertEq(s1, 142, "super.method() returns parent + 100")

    // ── Gap 4: Generic function call ──
    const g1 = comptime { return identity(42) }
    assertEq(g1, 42, "generic identity<int>")

    const g2 = comptime { return add(10, 20) }
    assertEq(g2, 30, "generic add<int>")

    println("All comptime coverage gap tests passed")
}
