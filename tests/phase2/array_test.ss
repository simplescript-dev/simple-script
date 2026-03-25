function sum(nums: int, count: int): int {
    let total = 0
    for (let i = 0; i < count; i++) {
        total = total + i
    }
    return total
}

function main() {
    const result = sum(0, 10)
    println(`sum 0..9 = ${result}`)

    // Nested function calls
    const a = sum(0, 5)
    const b = sum(0, 3)
    println(`a=${a}, b=${b}, a+b=${a + b}`)

    // Boolean expressions
    const x = 10
    const y = 20
    if (x < y && y > 15) {
        println("both true")
    }
    if (x > y || x == 10) {
        println("at least one true")
    }
}
