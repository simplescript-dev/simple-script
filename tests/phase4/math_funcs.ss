function main() {
    // Math functions auto-convert int args to double
    println("sqrt(144) = " + sqrt(144))
    println("abs(-42.5) = " + abs(-42.5))
    println("floor(3.7) = " + floor(3.7))
    println("ceil(3.2) = " + ceil(3.2))
    println("round(3.5) = " + round(3.5))
    println("pow(2, 10) = " + pow(2, 10))
    println("min(3, 7) = " + min(3, 7))
    println("max(3, 7) = " + max(3, 7))

    // Pythagorean
    const a = 3.0
    const b = 4.0
    const c = sqrt(a * a + b * b)
    println("hypotenuse(3,4) = " + c)
}
