interface Printable {
    function display(): string
}

interface Serializable {
    function toStr(): string
}

class Item : Printable, Serializable {
    name: string
    value: int

    function display(): string {
        return `Item(${this.name})`
    }
    function toStr(): string {
        return `${this.name}:${this.value}`
    }
}

function show(p: Printable) {
    println(p.display())
}

function serialize(s: Serializable) {
    println(s.toStr())
}

function main() {
    const item = new Item("sword", 100)
    show(item)
    serialize(item)
}
