function main() {
    // Test break
    println("break test:")
    for (let i = 0; i < 10; i++) {
        if (i == 5) {
            break
        }
        print(`${i} `)
    }
    println("")

    // Test continue
    println("continue test (skip even):")
    for (let i = 0; i < 10; i++) {
        if (i % 2 == 0) {
            continue
        }
        print(`${i} `)
    }
    println("")

    // Test break in while
    println("while break test:")
    let n = 0
    while (n < 100) {
        if (n > 5) {
            break
        }
        print(`${n} `)
        n = n + 1
    }
    println("")

    // Find first prime > 100
    let candidate = 101
    while (candidate < 200) {
        if (isPrime(candidate) == 1) {
            println(`first prime > 100: ${candidate}`)
            break
        }
        candidate = candidate + 2
    }
}

function isPrime(n: int): int {
    if (n < 2) { return 0 }
    let i = 2
    while (i * i <= n) {
        if (n % i == 0) { return 0 }
        i = i + 1
    }
    return 1
}
