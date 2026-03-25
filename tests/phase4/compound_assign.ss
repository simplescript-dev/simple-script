function main() {
    let x = 100
    x += 10
    println("100 += 10 = " + x)
    x -= 30
    println("-= 30 = " + x)
    x *= 2
    println("*= 2 = " + x)
    x /= 4
    println("/= 4 = " + x)
    x %= 7
    println("%= 7 = " + x)

    // Practical: accumulator
    let total = 0
    for (let i = 1; i <= 10; i++) {
        total += i
    }
    println("sum 1..10 = " + total)

    // Factorial with *=
    let fact = 1
    for (let i = 1; i <= 6; i++) {
        fact *= i
    }
    println("6! = " + fact)
}
