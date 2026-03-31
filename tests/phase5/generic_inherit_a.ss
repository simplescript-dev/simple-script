// Case A: generic class extends non-generic class
class Container(label: string)

class Box<T> extends Container(value: T) {
    function describe(): string {
        return `${this.label}: box`
    }
}

function main() {
    const b = new Box<int>("numbers", 42)
    if (b.label != "numbers") { exit(1) }
    if (b.value != 42) { exit(1) }
    if (b.describe() != "numbers: box") { exit(1) }

    const bs = new Box<string>("words", "hello")
    if (bs.label != "words") { exit(1) }
    if (bs.value != "hello") { exit(1) }

    println("generic_inherit_a: all passed")
}
