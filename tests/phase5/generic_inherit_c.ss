// Case C: generic class extends generic class (type param forwarding)
class Box<T>(value: T)

class LabeledBox<T> extends Box<T>(label: string) {
    function info(): string {
        return `${this.label}: labeled`
    }
}

function main() {
    const b = new LabeledBox<int>(42, "num")
    if (b.value != 42) { exit(1) }
    if (b.label != "num") { exit(1) }
    if (b.info() != "num: labeled") { exit(1) }

    const bs = new LabeledBox<string>("hello", "str")
    if (bs.value != "hello") { exit(1) }
    if (bs.label != "str") { exit(1) }

    println("generic_inherit_c: all passed")
}
