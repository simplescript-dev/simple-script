function main() {
    // Currently: println(`${42}`) — verbose
    // Goal: println(42) — just works

    // Auto-convert in string concat
    const msg = "count: " + 42
    println(msg)

    const pi = "pi = " + 3.14
    println(pi)

    // println with int directly
    const x = 100
    println(x)
    println(42)
    println(3.14)

    // Mixed concat
    const result = "result: " + (10 + 20)
    println(result)
}
