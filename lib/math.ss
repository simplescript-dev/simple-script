// SimpleScript Math Utilities — Higher-level math functions
//
// Usage:
//   import { MathUtil } from "@/lib/math"
//   MathUtil.clamp(15, 0, 10)         → 10.0
//   MathUtil.lerp(0.0, 100.0, 0.5)    → 50.0
//   MathUtil.mapRange(5, 0, 10, 0, 100) → 50.0
//   MathUtil.toDegrees(3.14159)        → ~180.0
//   MathUtil.toRadians(180.0)          → ~3.14159
//
// Constants:
//   MathUtil.PI     → 3.141592653589793
//   MathUtil.E      → 2.718281828459045
//   MathUtil.TAU    → 6.283185307179586

class MathUtil {}

// ── Constants (as zero-arg methods) ─────────────────────────

function MathUtil_PI(): double {
    return 3.141592653589793
}

function MathUtil_E(): double {
    return 2.718281828459045
}

function MathUtil_TAU(): double {
    return 6.283185307179586
}

function MathUtil_EPSILON(): double {
    return 0.00000000000000022204
}

// ── Clamping & interpolation ────────────────────────────────

function MathUtil_clamp(value: double, lo: double, hi: double): double {
    if (value < lo) { return lo }
    if (value > hi) { return hi }
    return value
}

function MathUtil_lerp(a: double, b: double, t: double): double {
    return a + (b - a) * t
}

function MathUtil_inverseLerp(a: double, b: double, value: double): double {
    if (a == b) { return 0.0 }
    return (value - a) / (b - a)
}

function MathUtil_mapRange(value: double, inMin: double, inMax: double, outMin: double, outMax: double): double {
    const t = (value - inMin) / (inMax - inMin)
    return outMin + (outMax - outMin) * t
}

// ── Angle conversion ────────────────────────────────────────

function MathUtil_toDegrees(radians: double): double {
    return radians * 180.0 / 3.141592653589793
}

function MathUtil_toRadians(degrees: double): double {
    return degrees * 3.141592653589793 / 180.0
}

// ── Comparison ──────────────────────────────────────────────

function MathUtil_approxEqual(a: double, b: double, epsilon: double): double {
    const diff = a - b
    const absDiff = Math.abs(diff)
    if (absDiff <= epsilon) { return 1.0 }
    return 0.0
}

// ── Integer utilities ───────────────────────────────────────

function MathUtil_isEven(n: int): int {
    if (n % 2 == 0) { return 1 }
    return 0
}

function MathUtil_isOdd(n: int): int {
    if (n % 2 == 0) { return 0 }
    return 1
}

function MathUtil_gcd(a: int, b: int): int {
    let x = a
    let y = b
    if (x < 0) { x = 0 - x }
    if (y < 0) { y = 0 - y }
    while (y != 0) {
        const temp = y
        y = x % y
        x = temp
    }
    return x
}

function MathUtil_lcm(a: int, b: int): int {
    if (a == 0 || b == 0) { return 0 }
    let x = a
    let y = b
    if (x < 0) { x = 0 - x }
    if (y < 0) { y = 0 - y }
    return x / MathUtil_gcd(x, y) * y
}

function MathUtil_isPowerOfTwo(n: int): int {
    if (n <= 0) { return 0 }
    if ((n & (n - 1)) == 0) { return 1 }
    return 0
}
