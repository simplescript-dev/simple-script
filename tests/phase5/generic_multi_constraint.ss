interface Printable {
    function display(): string
}

interface Scorable {
    function getScore(): int
}

interface Rankable {
    function rank(): int
}

// Implements both Printable and Scorable
class Player(name: string, score: int) : Printable, Scorable {
    function display(): string {
        return this.name
    }
    function getScore(): int {
        return this.score
    }
}

// Implements all three
class Hero(name: string, score: int, level: int) : Printable, Scorable, Rankable {
    function display(): string {
        return `${this.name} L${this.level}`
    }
    function getScore(): int {
        return this.score
    }
    function rank(): int {
        return this.level
    }
}

// Implements only Printable
class Label(text: string) : Printable {
    function display(): string {
        return this.text
    }
}

// ── Function with dual constraint ──
function showScore<T extends Printable & Scorable>(item: T): string {
    return `${item.display()}: ${item.getScore()}`
}

// ── Function with triple constraint ──
function fullInfo<T extends Printable & Scorable & Rankable>(item: T): string {
    return `${item.display()} s=${item.getScore()} r=${item.rank()}`
}

// ── Mixed: first param dual-constrained, second unconstrained ──
function labeled<T extends Printable & Scorable, U>(item: T, tag: U): string {
    return item.display()
}

// ── Class with multi-constraint ──
class Wrapper<T extends Printable & Scorable>(item: T) {
    function info(): string {
        return `${this.item.display()}: ${this.item.getScore()}`
    }
}

function main() {
    const p = new Player("Alice", 100)
    const h = new Hero("Bob", 200, 5)

    // Dual constraint function with Player (Printable & Scorable)
    const r1 = showScore(p)
    if (r1 != "Alice: 100") { exit(1) }

    // Dual constraint function with Hero (Printable & Scorable & Rankable)
    const r2 = showScore(h)
    if (r2 != "Bob L5: 200") { exit(1) }

    // Triple constraint function with Hero
    const r3 = fullInfo(h)
    if (r3 != "Bob L5 s=200 r=5") { exit(1) }

    // Mixed constraint function
    const r4 = labeled(p, 42)
    if (r4 != "Alice") { exit(1) }

    const r5 = labeled(h, "tag")
    if (r5 != "Bob L5") { exit(1) }

    // Class with multi-constraint
    const w1 = new Wrapper(p)
    if (w1.info() != "Alice: 100") { exit(1) }

    const w2 = new Wrapper(h)
    if (w2.info() != "Bob L5: 200") { exit(1) }

    // Explicit type args
    const r6 = showScore<Player>(p)
    if (r6 != "Alice: 100") { exit(1) }

    const w3 = new Wrapper<Hero>(h)
    if (w3.info() != "Bob L5: 200") { exit(1) }

    println("generic_multi_constraint: all passed")
}
