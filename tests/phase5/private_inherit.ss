// Test: private field with inheritance — public methods on parent class work
class Animal {
    private sound: string
    name: string

    function speak(): string {
        return this.sound
    }
}

class Dog extends Animal {
    breed: string

    function info(): string {
        return this.name
    }
}

function main() {
    let d = new Dog("woof", "Rex", "Lab")
    // Public field on parent — OK
    if (d.name != "Rex") { exit(1) }
    // Public field on child — OK
    if (d.breed != "Lab") { exit(1) }
    // Public method accesses private field internally — OK
    if (d.speak() != "woof") { exit(1) }
    // Child method accesses public parent field — OK
    if (d.info() != "Rex") { exit(1) }
    println("private_inherit: all passed")
}
