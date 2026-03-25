function power(base: int, exp: int): int {
    let result = 1
    for (let i = 0; i < exp; i++) {
        result = result * base
    }
    return result
}

function main() {
    // Print powers of 2
    println("Powers of 2:")
    for (let i = 0; i <= 10; i++) {
        const p = power(2, i)
        println(`  2^${i} = ${p}`)
    }

    println("")

    // Collatz conjecture
    println("Collatz sequence starting at 27:")
    let n = 27
    let steps = 0
    while (n != 1) {
        if (n % 2 == 0) {
            n = n / 2
        } else {
            n = n * 3 + 1
        }
        steps = steps + 1
    }
    println(`  Reached 1 in ${steps} steps`)
}
