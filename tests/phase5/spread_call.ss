// Test: spread in function calls — foo(...args)

function add3(a: int, b: int, c: int): int {
    return a + b + c
}

function greet(name: string, greeting: string): string {
    return `${greeting}, ${name}!`
}

function add2(a: int, b: int): int {
    return a + b
}

function main() {
    // Basic spread: all args from array
    const nums = [10, 20, 30]
    const result = add3(...nums)
    if (result != 60) { throw("basic spread failed") }

    // Spread with string array
    const parts: Array<string> = ["Alice", "Hello"]
    const msg = greet(...parts)
    if (msg != "Hello, Alice!") { throw("string spread failed") }

    // Mixed: some regular args + spread for rest
    const rest = [20, 30]
    const mixed = add3(10, ...rest)
    if (mixed != 60) { throw("mixed spread failed") }

    // Spread with 2-arg function
    const pair = [5, 7]
    const sum2 = add2(...pair)
    if (sum2 != 12) { throw("2-arg spread failed") }

    println("spread_call: all passed")
}
