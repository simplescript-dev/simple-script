function main() {
    // String repeat via method (not operator)
    println("ha".repeat(3))
    println("=".repeat(30))

    // Array.includes
    const nums = [10, 20, 30, 40, 50]
    println("has 30:", nums.includes(30))
    println("has 99:", nums.includes(99))
}
