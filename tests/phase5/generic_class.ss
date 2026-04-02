class Box<T> {
    value: T
}

class Pair<A, B> {
    first: A
    second: B
}

function main() {
    // Basic: int
    const b1 = new Box(42)
    if (b1.value != 42) { exit(1) }

    // Basic: string
    const b2 = new Box("hello")
    if (b2.value != "hello") { exit(1) }

    // Multiple type params
    const p = new Pair(10, "world")
    if (p.first != 10) { exit(1) }
    if (p.second != "world") { exit(1) }

    // Multiple instantiations of same type
    const b3 = new Box(99)
    if (b3.value != 99) { exit(1) }

    println("generic_class: all passed")
}
