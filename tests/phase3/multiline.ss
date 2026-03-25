function main() {
    // Multi-line array
    const data = [
        10, 20, 30,
        40, 50, 60,
        70, 80, 90
    ]

    let sum = 0
    for (let i = 0; i < 9; i++) {
        sum = sum + data[i]
    }
    println(`sum = ${sum}`)

    // Multi-line function call
    println(
        formatUser("Alice", 30, "Beijing")
    )

    // Multi-line function params
    const result = add(
        100,
        200
    )
    println(`100 + 200 = ${result}`)
}

function formatUser(name: string, age: int, city: string): string {
    return `${name}, age ${age}, from ${city}`
}

function add(a: int, b: int): int {
    return a + b
}
