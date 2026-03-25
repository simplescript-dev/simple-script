function isPrime(n: int): int {
    if (n < 2) {
        return 0
    }
    let i = 2
    while (i * i <= n) {
        if (n % i == 0) {
            return 0
        }
        i = i + 1
    }
    return 1
}

function main() {
    println("Primes up to 30:")
    for (let n = 2; n <= 30; n++) {
        if (isPrime(n) == 1) {
            println(`  ${n}`)
        }
    }
}
