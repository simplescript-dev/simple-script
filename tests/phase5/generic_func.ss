function identity<T>(x: T): T {
    return x
}

function first<A, B>(a: A, b: B): A {
    return a
}

function main() {
    // Basic: int
    const a = identity(42)
    if (a != 42) { exit(1) }

    // Basic: string
    const b = identity("hello")
    if (b != "hello") { exit(1) }

    // Multiple type params
    const c = first(10, "world")
    if (c != 10) { exit(1) }

    // Multiple instantiations of same function
    const d = identity(99)
    if (d != 99) { exit(1) }

    println("generic_func: all passed")
}
