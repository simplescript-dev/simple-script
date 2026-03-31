function max2<T>(a: T, b: T): T {
    if (a > b) { return a }
    return b
}

function addOne<T>(x: T): T {
    return x + 1
}

function main() {
    // Int comparison
    if (max2(3, 7) != 7) { exit(1) }
    if (max2(10, 2) != 10) { exit(1) }

    // Generic arithmetic
    if (addOne(41) != 42) { exit(1) }

    println("generic_multi_call: all passed")
}
