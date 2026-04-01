// Test: MathUtil standard library module (D037)

import { MathUtil } from "@/lib/math"

function assert(cond: int, msg: string) {
    if (cond == 0) {
        println(`FAIL: ${msg}`)
        exit(1)
    }
}

function assertApprox(actual: double, expected: double, msg: string) {
    const diff = Math.abs(actual - expected)
    if (diff > 0.0001) {
        println(`FAIL: ${msg} - expected ${expected}, got ${actual}`)
        exit(1)
    }
}

function assertEq(actual: int, expected: int, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} - expected ${expected}, got ${actual}`)
        exit(1)
    }
}

function main() {
    // ── Constants ────────────────────────────────────────────
    assertApprox(MathUtil.PI(), 3.14159265358, "PI")
    assertApprox(MathUtil.E(), 2.71828182845, "E")
    assertApprox(MathUtil.TAU(), 6.28318530717, "TAU")

    // ── clamp ───────────────────────────────────────────────
    assertApprox(MathUtil.clamp(5.0, 0.0, 10.0), 5.0, "clamp mid")
    assertApprox(MathUtil.clamp(-1.0, 0.0, 10.0), 0.0, "clamp lo")
    assertApprox(MathUtil.clamp(15.0, 0.0, 10.0), 10.0, "clamp hi")

    // ── lerp ────────────────────────────────────────────────
    assertApprox(MathUtil.lerp(0.0, 100.0, 0.0), 0.0, "lerp 0")
    assertApprox(MathUtil.lerp(0.0, 100.0, 0.5), 50.0, "lerp 0.5")
    assertApprox(MathUtil.lerp(0.0, 100.0, 1.0), 100.0, "lerp 1")
    assertApprox(MathUtil.lerp(10.0, 20.0, 0.25), 12.5, "lerp 0.25")

    // ── inverseLerp ─────────────────────────────────────────
    assertApprox(MathUtil.inverseLerp(0.0, 100.0, 50.0), 0.5, "inverseLerp mid")
    assertApprox(MathUtil.inverseLerp(0.0, 100.0, 0.0), 0.0, "inverseLerp lo")
    assertApprox(MathUtil.inverseLerp(0.0, 100.0, 100.0), 1.0, "inverseLerp hi")

    // ── mapRange ────────────────────────────────────────────
    assertApprox(MathUtil.mapRange(5.0, 0.0, 10.0, 0.0, 100.0), 50.0, "mapRange mid")
    assertApprox(MathUtil.mapRange(0.0, 0.0, 10.0, 0.0, 100.0), 0.0, "mapRange lo")
    assertApprox(MathUtil.mapRange(10.0, 0.0, 10.0, 0.0, 100.0), 100.0, "mapRange hi")

    // ── toDegrees / toRadians ───────────────────────────────
    assertApprox(MathUtil.toDegrees(3.141592653589793), 180.0, "toDegrees PI")
    assertApprox(MathUtil.toDegrees(0.0), 0.0, "toDegrees 0")
    assertApprox(MathUtil.toRadians(180.0), 3.141592653589793, "toRadians 180")
    assertApprox(MathUtil.toRadians(90.0), 1.5707963267948966, "toRadians 90")

    // ── approxEqual ─────────────────────────────────────────
    assertApprox(MathUtil.approxEqual(1.0, 1.0000001, 0.001), 1.0, "approxEqual close")
    assertApprox(MathUtil.approxEqual(1.0, 2.0, 0.001), 0.0, "approxEqual far")

    // ── Integer utilities ───────────────────────────────────
    assertEq(MathUtil.isEven(4), 1, "isEven 4")
    assertEq(MathUtil.isEven(3), 0, "isEven 3")
    assertEq(MathUtil.isEven(0), 1, "isEven 0")
    assertEq(MathUtil.isOdd(3), 1, "isOdd 3")
    assertEq(MathUtil.isOdd(4), 0, "isOdd 4")

    assertEq(MathUtil.gcd(12, 8), 4, "gcd(12,8)")
    assertEq(MathUtil.gcd(7, 13), 1, "gcd(7,13)")
    assertEq(MathUtil.gcd(0, 5), 5, "gcd(0,5)")

    assertEq(MathUtil.lcm(4, 6), 12, "lcm(4,6)")
    assertEq(MathUtil.lcm(3, 7), 21, "lcm(3,7)")
    assertEq(MathUtil.lcm(0, 5), 0, "lcm(0,5)")

    assertEq(MathUtil.isPowerOfTwo(1), 1, "isPowerOfTwo 1")
    assertEq(MathUtil.isPowerOfTwo(8), 1, "isPowerOfTwo 8")
    assertEq(MathUtil.isPowerOfTwo(6), 0, "isPowerOfTwo 6")
    assertEq(MathUtil.isPowerOfTwo(0), 0, "isPowerOfTwo 0")

    println("All MathUtil stdlib tests passed!")
}
