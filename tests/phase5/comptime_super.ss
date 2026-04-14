// Test: comptime super.method() dispatch (D088 Phase 8)
// Verifies that genValCtMethodCall walks one parent up per `super` hop,
// tracking the defining class of the currently executing method.

import { assertEqual } from "@/lib/test"

// Test 1: basic super.method() — Dog.sound calls Animal.sound
comptime {
    class CtAnimal1 {
        label: string
        function sound(): string { return "generic" }
    }
    class CtDog1 extends CtAnimal1 {
        function sound(): string {
            return super.sound() + "+woof"
        }
    }
    const d = new CtDog1(label: "Rex")
    const r1 = d.sound()
    @comptimeEmit(`function ctSuperBasic(): string { return "${r1}" }\n`)
}

// Test 2: multi-level inheritance — each super walks exactly one level up
comptime {
    class CtAnimal2 {
        function tag(): string { return "A" }
    }
    class CtDog2 extends CtAnimal2 {
        function tag(): string { return super.tag() + ":D" }
    }
    class CtPuppy2 extends CtDog2 {
        function tag(): string { return super.tag() + ":P" }
    }
    const p = new CtPuppy2()
    const r2 = p.tag()
    @comptimeEmit(`function ctSuperChain(): string { return "${r2}" }\n`)
}

// Test 3: super with arguments (positional)
comptime {
    class CtBase3 {
        function combine(a: int, b: int): int { return a * 10 + b }
    }
    class CtChild3 extends CtBase3 {
        function combine(a: int, b: int): int {
            return super.combine(a, b) + 1000
        }
    }
    const c = new CtChild3()
    const r3 = c.combine(3, 7)
    @comptimeEmit(`function ctSuperArgs(): int { return ${r3} }\n`)
}

// Test 4: void super — parent mutates this, child overrides and chains
comptime {
    class CtCounter4 {
        n: int
        function bump() { this.n = this.n + 1 }
    }
    class CtFastCounter4 extends CtCounter4 {
        function bump() {
            super.bump()
            this.n = this.n + 10
        }
    }
    const fc = new CtFastCounter4(n: 0)
    fc.bump()
    fc.bump()
    const r4 = fc.n
    @comptimeEmit(`function ctSuperVoid(): int { return ${r4} }\n`)
}

// Test 5: inherited method without override — child calls parent's method directly
// (not via super), parent's super usage stays disabled because no grandparent.
comptime {
    class CtBase5 {
        function greet(): string { return "hi" }
    }
    class CtChild5 extends CtBase5 {
        // No override; .greet() walks up to CtBase5
    }
    const cb = new CtChild5()
    const r5 = cb.greet()
    @comptimeEmit(`function ctSuperInherited(): string { return "${r5}" }\n`)
}

// Test 6: super.method() then re-read this field the parent mutated
comptime {
    class CtBox6 {
        val: int
        function set1(x: int) { this.val = x }
    }
    class CtLabelBox6 extends CtBox6 {
        function set1(x: int) {
            super.set1(x * 2)
        }
    }
    const lb = new CtLabelBox6(val: 0)
    lb.set1(21)
    const r6 = lb.val
    @comptimeEmit(`function ctSuperFieldAfter(): int { return ${r6} }\n`)
}

function main() {
    test("comptime super basic", () => {
        assertEqual(ctSuperBasic(), "generic+woof")
    })
    test("comptime super multi-level chain", () => {
        assertEqual(ctSuperChain(), "A:D:P")
    })
    test("comptime super with positional args", () => {
        assertEqual(ctSuperArgs(), 1037)
    })
    test("comptime super void with this mutation", () => {
        assertEqual(ctSuperVoid(), 22)
    })
    test("comptime inherited method (no override)", () => {
        assertEqual(ctSuperInherited(), "hi")
    })
    test("comptime super field mutation observable", () => {
        assertEqual(ctSuperFieldAfter(), 42)
    })
}
