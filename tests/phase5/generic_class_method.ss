class Box<T>(value: T) {
    function getValue(): T {
        return this.value
    }
}

function main() {
    const b1 = new Box(42)
    if (b1.getValue() != 42) { exit(1) }

    const b2 = new Box("hello")
    if (b2.getValue() != "hello") { exit(1) }

    println("generic_class_method: all passed")
}
