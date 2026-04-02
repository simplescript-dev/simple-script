// SimpleScript — Final Demo

class Point {
    x: int
    y: int

    function toString(): string {
        return "(" + this.x + ", " + this.y + ")"
    }
    function distSq(): int {
        return this.x * this.x + this.y * this.y
    }
}

function main() {
    println("=== SimpleScript Demo ===")
    println("")

    // 1. Variables & types
    const name = "SimpleScript"
    println("1. Hello from " + name + "!")

    // 2. String methods chain
    println("2. " + "  hello world  ".trim().toUpperCase().replace("WORLD", "SS"))

    // 3. Single-quoted strings
    println('3. <div class="main">HTML works</div>')

    // 4. Recursion
    println("4. fib(20) = " + fib(20))

    // 5. Arrays + sort
    const nums = [64, 25, 12, 89, 37]
    sort(nums, nums.length())
    print("5. sorted: ")
    for (n in nums) { print(n + " ") }
    println("")

    // 6. Split + Join
    const parts = "Alice,Bob,Charlie".split(",")
    println("6. " + parts.join(" | "))

    // 7. Map
    const m = Map()
    m.set("x", 10)
    m.set("y", 20)
    println("7. map size=" + m.size() + " x=" + m.get("x"))

    // 8. Classes
    const p = new Point(3, 4)
    println("8. " + p.toString() + " dist^2=" + p.distSq())

    // 9. File I/O
    writeFile("/tmp/ss.txt", "OK")
    println("9. file: " + readFile("/tmp/ss.txt"))

    // 10. Control flow
    print("10. ")
    for (let i = 1; i <= 15; i++) {
        if (i % 15 == 0) {
            print("FizzBuzz ")
        } else if (i % 3 == 0) {
            print("Fizz ")
        } else if (i % 5 == 0) {
            print("Buzz ")
        } else {
            print(i + " ")
        }
    }
    println("")
}

function fib(n: int): int {
    if (n <= 1) { return n }
    return fib(n - 1) + fib(n - 2)
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
