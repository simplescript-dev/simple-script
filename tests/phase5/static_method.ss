// Test: static methods on classes (D070)

class MathUtils {
    static function max(a: int, b: int): int {
        if (a > b) { return a }
        return b
    }

    static function min(a: int, b: int): int {
        if (a < b) { return a }
        return b
    }

    static function zero(): int {
        return 0
    }
}

class Counter {
    count: int

    static function create(): Counter {
        return new Counter(0)
    }

    function increment(): int {
        this.count = this.count + 1
        return this.count
    }
}

// Static with access modifiers
class Validator {
    static function isValid(s: string): int {
        if (s.length() >= 3) { return 1 }
        return 0
    }

    private static function helper(): int {
        return 42
    }
}

function main() {
    // Basic static method calls
    const m = MathUtils.max(10, 20)
    if (m != 20) { exit(1) }

    const n = MathUtils.min(10, 20)
    if (n != 10) { exit(1) }

    const z = MathUtils.zero()
    if (z != 0) { exit(1) }

    // Static factory method
    const c = Counter.create()
    const v1 = c.increment()
    if (v1 != 1) { exit(1) }
    const v2 = c.increment()
    if (v2 != 2) { exit(1) }

    // Static with access modifier
    const ok = Validator.isValid("abc")
    if (ok != 1) { exit(1) }
    const bad = Validator.isValid("ab")
    if (bad != 0) { exit(1) }
}
