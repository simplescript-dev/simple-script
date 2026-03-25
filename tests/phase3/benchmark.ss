function fibonacci(n: int): int {
    if (n <= 1) {
        return n
    }
    return fibonacci(n - 1) + fibonacci(n - 2)
}

function main() {
    // Compute fib(35) — a real benchmark
    const n = 35
    const result = fibonacci(n)
    println(`fib(${n}) = ${result}`)
}
