// Test: Math built-in function extensions (D037)

function assertApprox(actual: double, expected: double, msg: string) {
    const diff = Math.abs(actual - expected)
    if (diff > 0.0001) {
        println(`FAIL: ${msg} - expected ${expected}, got ${actual}`)
        exit(1)
    }
}

function main() {
    // tan
    assertApprox(Math.tan(0.0), 0.0, "tan(0)")
    assertApprox(Math.tan(0.7853981633974483), 1.0, "tan(PI/4)")

    // asin / acos / atan
    assertApprox(Math.asin(0.0), 0.0, "asin(0)")
    assertApprox(Math.asin(1.0), 1.5707963267948966, "asin(1)")
    assertApprox(Math.acos(1.0), 0.0, "acos(1)")
    assertApprox(Math.atan(1.0), 0.7853981633974483, "atan(1)")

    // atan2
    assertApprox(Math.atan2(1.0, 1.0), 0.7853981633974483, "atan2(1,1)")
    assertApprox(Math.atan2(0.0, 1.0), 0.0, "atan2(0,1)")

    // exp
    assertApprox(Math.exp(0.0), 1.0, "exp(0)")
    assertApprox(Math.exp(1.0), 2.718281828, "exp(1)")

    // log10 / log2
    assertApprox(Math.log10(100.0), 2.0, "log10(100)")
    assertApprox(Math.log10(1000.0), 3.0, "log10(1000)")
    assertApprox(Math.log2(8.0), 3.0, "log2(8)")
    assertApprox(Math.log2(1024.0), 10.0, "log2(1024)")

    // trunc
    assertApprox(Math.trunc(3.7), 3.0, "trunc(3.7)")
    assertApprox(Math.trunc(-3.7), -3.0, "trunc(-3.7)")

    // sign
    assertApprox(Math.sign(5.0), 1.0, "sign(5)")
    assertApprox(Math.sign(-3.0), -1.0, "sign(-3)")
    assertApprox(Math.sign(0.0), 0.0, "sign(0)")

    // hypot
    assertApprox(Math.hypot(3.0, 4.0), 5.0, "hypot(3,4)")
    assertApprox(Math.hypot(5.0, 12.0), 13.0, "hypot(5,12)")

    // cbrt
    assertApprox(Math.cbrt(27.0), 3.0, "cbrt(27)")
    assertApprox(Math.cbrt(8.0), 2.0, "cbrt(8)")

    // fmod
    assertApprox(Math.fmod(5.5, 2.0), 1.5, "fmod(5.5,2)")
    assertApprox(Math.fmod(10.0, 3.0), 1.0, "fmod(10,3)")

    // int args auto-convert to double
    assertApprox(Math.trunc(4), 4.0, "trunc(int 4)")
    assertApprox(Math.exp(0), 1.0, "exp(int 0)")

    println("All math builtin tests passed!")
}
