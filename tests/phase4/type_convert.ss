function main() {
    // Explicit conversions already work via methods
    const s = "42"
    println("toInt: " + s.toInt())
    println("toDouble: " + "3.14".toDouble())

    // Negative numbers
    const neg = -42
    println("neg: " + neg)
    println("neg * 2: " + (neg * 2))

    const negD = -3.14
    println("negD: " + negD)

    // Mixed expressions
    const total = 100
    const tax = 0.08
    const price = total + total * tax
    println("price: " + price)

    // Integer division then multiply
    const a = 7
    const b = 2
    println("7 / 2 = " + (a / b))
    println("7 / 2.0 = " + (a / 2.0))
    println("7 % 2 = " + (a % b))
}
