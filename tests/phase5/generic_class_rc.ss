class Item(name: string)

class Box<T>(value: T) {
    function getValue(): T {
        return this.value
    }
}

class Pair<A, B>(first: A, second: B)

function main() {
    // Generic class holding a class instance (RC tracking)
    const item = new Item("sword")
    const box = new Box(item)
    if (box.getValue().name != "sword") { exit(1) }

    // Multiple type params with mixed types
    const p = new Pair(42, "hello")
    if (p.first != 42) { exit(1) }
    if (p.second != "hello") { exit(1) }

    // Multiple specializations
    const intBox = new Box(100)
    const strBox = new Box("world")
    if (intBox.getValue() != 100) { exit(1) }
    if (strBox.getValue() != "world") { exit(1) }

    println("generic_class_rc: all passed")
}
