function add(a: int, b: int): int {
    return a + b
}

function multiply(a: int, b: int): int {
    return a * b
}

function factorial(n: int): int {
    if (n <= 1) { return 1 }
    return n * factorial(n - 1)
}
