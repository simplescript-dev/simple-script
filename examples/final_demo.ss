// SimpleScript v1.3 — Complete Feature Demo

class Shape {
    name: string

    function toString(): string {
        return this.name
    }
    function area(): double {
        return 0.0
    }
}

class Circle extends Shape {
    radius: double

    function toString(): string {
        return "Circle(r=" + this.radius + ")"
    }
    override function area(): double {
        return 3.14159 * this.radius ** 2
    }
}

class Rect extends Shape {
    w: double
    h: double

    function toString(): string {
        return "Rect(" + this.w + "x" + this.h + ")"
    }
    override function area(): double {
        return this.w * this.h
    }
}

function main() {
    println("=== SimpleScript v1.3 ===")

    // 1. Inheritance + auto toString
    const c = new Circle("circle", 5.0)
    const r = new Rect("rect", 3.0, 4.0)
    println("1.", c, "area =", c.area())
    println("  ", r, "area =", r.area())

    // 2. String arrays + for-in
    const csv = "Alice:95,Bob:87,Charlie:92"
    const entries = csv.split(",")
    println("2. Scores:")
    for (entry in entries) {
        const parts = entry.split(":")
        println("   " + parts[0] + " => " + parts[1])
    }

    // 3. Map + string methods
    const config = Map()
    const raw = "  host=localhost\n  port=8080\n  debug=true  "
    const lines = raw.trim().split("\n")
    for (line in lines) {
        const kv = line.trim().split("=")
        config.set(kv[0], kv[1])
    }
    println("3. Config:", config.size(), "keys")
    println("   host:", config.getString("host"))
    println("   port:", config.getString("port"))

    // 4. Math + power operator
    println("4. Math:")
    println("   sqrt(144) =", sqrt(144))
    println("   2 ** 10 =", 2 ** 10)
    println("   abs(-42) =", abs(-42))

    // 5. Default params + multi-arg println
    greet()
    greet("SimpleScript")

    // 6. File I/O
    writeFile("/tmp/ss_final.txt", "SimpleScript v1.3 works!")
    println("6. File:", readFile("/tmp/ss_final.txt"))

    // 7. Array operations
    let nums = [5, 2, 8, 1, 9]
    sort(nums, nums.length())
    println("7. Sorted:", nums[0], nums[1], nums[2], nums[3], nums[4])

    println("\nAll features working!")
}

function greet(name: string = "World") {
    println("5. Hello,", name + "!")
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
