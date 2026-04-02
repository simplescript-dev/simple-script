// SimpleScript Showcase — A complete program demonstrating all language features
// Compile: ss build --release examples/showcase.ss -o showcase
// Run:     ./showcase

class Stats {
    total: int
    min: int
    max: int
    sum: int

    function average(): double {
        return 0.0
    }

    function display() {
        println(`  Total:   ${this.total}`)
        println(`  Min:     ${this.min}`)
        println(`  Max:     ${this.max}`)
        println(`  Sum:     ${this.sum}`)
    }
}

function computeStats(data: string, n: int): int {
    let min = data[0]
    let max = data[0]
    let sum = 0
    for (let i = 0; i < n; i++) {
        const v = data[i]
        sum = sum + v
        if (v < min) { min = v }
        if (v > max) { max = v }
    }
    // Return encoded as: total * 1000000 + min * 10000 + max * 100 + sum
    // (hacky but shows we need multiple return values or objects)
    println(`  Total:   ${n}`)
    println(`  Min:     ${min}`)
    println(`  Max:     ${max}`)
    println(`  Sum:     ${sum}`)
    return sum
}

function repeat(ch: string, n: int): string {
    let result = ""
    for (let i = 0; i < n; i++) {
        result = result + ch
    }
    return result
}

function bar(label: string, value: int, scale: int) {
    const barLen = value / scale
    const barStr = repeat("#", barLen)
    println(`  ${label}: ${barStr} (${value})`)
}

function sieve(limit: int): string {
    const isPrime = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ]

    // Mark all as prime initially
    for (let i = 2; i < limit; i++) {
        isPrime[i] = 1
    }

    // Sieve
    for (let i = 2; i * i < limit; i++) {
        if (isPrime[i] == 1) {
            let j = i * i
            while (j < limit) {
                isPrime[j] = 0
                j = j + i
            }
        }
    }

    return isPrime
}

function main() {
    println("=== SimpleScript Showcase ===")
    println("")

    // 1. String operations
    println("1. String Operations")
    const greeting = `Hello, SimpleScript!`
    println(`   ${greeting} (length: ${greeting.length()})`)
    println(`   substring(7,8): ${greeting.substring(7, 8)}`)
    println(`   indexOf("Script"): ${greeting.indexOf("Script")}`)
    println("")

    // 2. Math & loops
    println("2. Fibonacci (recursive)")
    for (let i = 0; i <= 10; i++) {
        print(`   fib(${i})=${fib(i)}`)
        if (i < 10) { print(", ") }
    }
    println("")
    println("")

    // 3. Arrays & sorting
    println("3. Array Sort")
    const data = [42, 17, 93, 5, 68, 31, 85, 12, 76, 54]
    print("   Before: ")
    printArray(data, 10)
    sort(data, 10)
    print("   After:  ")
    printArray(data, 10)
    println("")

    // 4. Statistics
    println("4. Statistics")
    computeStats(data, 10)
    println("")

    // 5. Bar chart
    println("5. Bar Chart")
    bar("Jan", 45, 5)
    bar("Feb", 30, 5)
    bar("Mar", 55, 5)
    bar("Apr", 70, 5)
    bar("May", 60, 5)
    println("")

    // 6. Sieve of Eratosthenes
    println("6. Primes (Sieve of Eratosthenes)")
    const primes = sieve(50)
    print("   Primes < 50: ")
    for (let i = 2; i < 50; i++) {
        if (primes[i] == 1) {
            print(`${i} `)
        }
    }
    println("")
    println("")

    // 7. File I/O
    println("7. File I/O")
    const report = `SimpleScript Showcase Report\nGenerated successfully\nAll features working!`
    writeFile("/tmp/ss_showcase.txt", report)
    const readBack = readFile("/tmp/ss_showcase.txt")
    println(`   Wrote and read back ${readBack.length()} bytes`)
    println("")

    // 8. Classes
    println("8. OOP")
    const stats = new Stats(10, 5, 93, 483)
    stats.display()
    println("")

    println("=== All features demonstrated! ===")
}

function fib(n: int): int {
    if (n <= 1) { return n }
    return fib(n - 1) + fib(n - 2)
}

function printArray(arr: string, n: int) {
    for (let i = 0; i < n; i++) {
        if (i > 0) { print(", ") }
        print(`${arr[i]}`)
    }
    println("")
}

function sort(arr: string, n: int) {
    for (let i = 0; i < n - 1; i++) {
        for (let j = 0; j < n - 1 - i; j++) {
            if (arr[j] > arr[j + 1]) {
                const tmp = arr[j]
                arr[j] = arr[j + 1]
                arr[j + 1] = tmp
            }
        }
    }
}
