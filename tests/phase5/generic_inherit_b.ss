// Case B: non-generic class extends specialized generic class
class Box<T>(value: T) {
    function getValue(): T {
        return this.value
    }
}

class IntBox extends Box<int>(label: string)

class StringBox extends Box<string>(tag: int) {
    function info(): string {
        return `${this.getValue()}#${this.tag}`
    }
}

function main() {
    const b = new IntBox(42, "test")
    if (b.value != 42) { exit(1) }
    if (b.label != "test") { exit(1) }
    if (b.getValue() != 42) { exit(1) }

    const s = new StringBox("hello", 7)
    if (s.value != "hello") { exit(1) }
    if (s.tag != 7) { exit(1) }
    if (s.getValue() != "hello") { exit(1) }
    if (s.info() != "hello#7") { exit(1) }

    println("generic_inherit_b: all passed")
}
