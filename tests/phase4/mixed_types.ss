function main() {
    // Int + double = double
    println("10 + 3.14 = " + (10 + 3.14))
    println("10 * 2.5 = " + (10 * 2.5))
    println("7 / 2.0 = " + (7 / 2.0))
    println("10 - 0.5 = " + (10 - 0.5))

    // Comparison
    if (5 > 4.9) {
        println("5 > 4.9: true")
    }
    if (3.14 > 3) {
        println("3.14 > 3: true")
    }

    // In function
    println("circle area r=5: " + circleArea(5))
}

function circleArea(r: int): double {
    return 3.14159 * r * r
}
