// Comprehensive test — exercises all language features

class Counter {
    name: string
    count: int

    function increment(): int {
        return this.count + 1
    }
    function display(): string {
        return this.name + "=" + this.count
    }
}

function main() {
    // Types
    const i = 42
    const d = 3.14
    const s = "hello"
    const b = true
    println("types: " + i + " " + d + " " + s + " " + b)

    // String methods
    const trimmed = "  HELLO  ".trim().toLowerCase()
    println("string: " + trimmed + " len=" + trimmed.length())
    println("contains: " + trimmed.contains("ell"))
    println("replace: " + trimmed.replace("hello", "world"))

    // Arrays
    const arr = [5, 3, 1, 4, 2]
    let sum = 0
    for (n in arr) { sum = sum + n }
    println("sum: " + sum + " len=" + arr.length())

    // Split + Join
    const csv = "a,b,c,d"
    const parts = csv.split(",")
    println("split: " + parts.length() + " join: " + parts.join("-"))

    // Map
    const m = Map()
    m.set("x", 10)
    m.set("y", 20)
    println("map: size=" + m.size() + " x=" + m.get("x") + " has y=" + m.has("y"))

    // Class
    const c = new Counter("hits", 99)
    println("class: " + c.display() + " inc=" + c.increment())

    // Control flow
    let result = ""
    for (let i = 1; i <= 5; i++) {
        if (i % 2 == 0) {
            result = result + "even "
        } else {
            result = result + "odd "
        }
    }
    println("flow: " + result)

    // Switch
    const grade = switch_test(85)
    println("switch: " + grade)

    // Recursion
    println("fib(10): " + fib(10))

    // File I/O
    writeFile("/tmp/ss_comp_test.txt", "OK")
    println("file: " + readFile("/tmp/ss_comp_test.txt"))

    // Single quotes
    println('quotes: <div class="x">ok</div>')

    // All passed
    println("")
    println("ALL OK")
}

function switch_test(score: int): string {
    switch (score) {
        case 100 -> return "perfect"
        default -> return "good"
    }
}

function fib(n: int): int {
    if (n <= 1) { return n }
    return fib(n - 1) + fib(n - 2)
}
