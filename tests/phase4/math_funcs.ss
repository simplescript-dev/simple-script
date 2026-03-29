function main() {
    // Math functions auto-convert int args to double
    println("Math.sqrt(144) = " + Math.sqrt(144))
    println("Math.abs(-42.5) = " + Math.abs(-42.5))
    println("Math.floor(3.7) = " + Math.floor(3.7))
    println("Math.ceil(3.2) = " + Math.ceil(3.2))
    println("Math.round(3.5) = " + Math.round(3.5))
    println("Math.pow(2, 10) = " + Math.pow(2, 10))
    println("Math.min(3, 7) = " + Math.min(3, 7))
    println("Math.max(3, 7) = " + Math.max(3, 7))

    // Pythagorean
    const a = 3.0
    const b = 4.0
    const c = Math.sqrt(a * a + b * b)
    println("hypotenuse(3,4) = " + c)
}
