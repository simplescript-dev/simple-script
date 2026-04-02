function identity<T>(x: T): T {
    return x
}

function first<A, B>(a: A, b: B): A {
    return a
}

class Box<T> {
    value: T

    function getValue(): T {
        return this.value
    }
}

class Pair<A, B> {
    first: A
    second: B
}

function main() {
    // Explicit type args on generic function calls
    const a = identity<int>(42)
    if (a != 42) { exit(1) }

    const b = identity<string>("hello")
    if (b != "hello") { exit(1) }

    // Multiple explicit type params
    const c = first<int, string>(10, "world")
    if (c != 10) { exit(1) }

    // Explicit type args on generic class instantiation
    const b1 = new Box<int>(42)
    if (b1.value != 42) { exit(1) }

    const b2 = new Box<string>("hello")
    if (b2.value != "hello") { exit(1) }

    // Methods on explicitly-typed generic class
    const b3 = new Box<int>(99)
    if (b3.getValue() != 99) { exit(1) }

    // Multi-param explicit generic class
    const p = new Pair<int, string>(10, "world")
    if (p.first != 10) { exit(1) }
    if (p.second != "world") { exit(1) }

    // Mixed: explicit and inferred produce same mangled name
    const d = identity(77)
    const e = identity<int>(77)
    if (d != e) { exit(1) }

    println("generic_explicit_types: all passed")
}
