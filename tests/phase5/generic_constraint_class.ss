interface Displayable {
    function display(): string
}

class Item : Displayable {
    label: string

    function display(): string {
        return this.label
    }
}

class Wrapper<T extends Displayable> {
    value: T

    function show(): string {
        return this.value.display()
    }
}

class Pair<A extends Displayable, B extends Displayable> {
    first: A
    second: B

    function showBoth(): string {
        return `${this.first.display()} and ${this.second.display()}`
    }
}

function main() {
    const item1 = new Item("hello")
    const item2 = new Item("world")

    const w = new Wrapper(item1)
    if (w.show() != "hello") { exit(1) }

    const w2 = new Wrapper<Item>(item2)
    if (w2.show() != "world") { exit(1) }

    const p = new Pair(item1, item2)
    if (p.showBoth() != "hello and world") { exit(1) }

    println("generic_constraint_class: all passed")
}
