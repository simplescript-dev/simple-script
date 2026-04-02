interface Scorable {
    function getScore(): int
}

class Entry : Scorable {
    name: string
    score: int

    function getScore(): int {
        return this.score
    }
}

// Mixed: T constrained, U unconstrained
function extract<T extends Scorable, U>(item: T, extra: U): int {
    return item.getScore()
}

// Only second param constrained
function process<A, B extends Scorable>(label: A, item: B): int {
    return item.getScore()
}

function main() {
    const e = new Entry("test", 42)

    const r1 = extract(e, 99)
    if (r1 != 42) { exit(1) }

    const r2 = extract(e, "hello")
    if (r2 != 42) { exit(1) }

    const r3 = process("label", e)
    if (r3 != 42) { exit(1) }

    const r4 = process(123, e)
    if (r4 != 42) { exit(1) }

    println("generic_constraint_multi: all passed")
}
