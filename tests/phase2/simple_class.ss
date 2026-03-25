class Dog(name: string) {
    function bark(): string {
        return `${this.name} says woof!`
    }
}

function main() {
    const d = new Dog("Rex")
    println(d.bark())
}
