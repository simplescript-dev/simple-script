function main() {
    // String repeat
    println("ha".repeat(3))
    println("-".repeat(20))

    // Array reverse
    const nums = [1, 2, 3, 4, 5]
    nums.reverse()
    print("reversed: ")
    for (n in nums) { print(n + " ") }
    println("")

    // Array indexOf
    const data = [10, 20, 30, 40, 50]
    println("indexOf 30: " + data.indexOf(30))
    println("indexOf 99: " + data.indexOf(99))

    // Ternary + repeat for bar chart
    println("")
    println("=== Bar Chart ===")
    const scores = [85, 92, 78, 95, 88]
    const names = "Alice,Bob,Charlie,Dave,Eve".split(",")
    for (let i = 0; i < 5; i++) {
        const bar = "#".repeat(scores[i] / 5)
        const grade = scores[i] >= 90 ? "A" : scores[i] >= 80 ? "B" : "C"
        println(names[i] + " " + grade + " " + bar)
    }
}
