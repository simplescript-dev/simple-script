interface Greeter {
    function greet(): string
}

class Dog(name: string) : Greeter {
    function greet(): string {
        return `${this.name} says woof!`
    }
}

function show(g: Greeter) {
    println(g.greet())
}

function main() {
    const d = new Dog("Rex")
    show(d)
    let g: Greeter = d
    println(g.greet())
}
