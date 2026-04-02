// Test: PIR with class inheritance — vtable dispatch + RC management
class Animal {
    name: string
    legs: int

    function describe(): string {
        return `${this.name} has ${this.legs} legs`
    }
}

class Cat extends Animal {
    indoor: int

    function describe(): string {
        if (this.indoor == 1) {
            return `${this.name} is an indoor cat`
        }
        return `${this.name} is an outdoor cat`
    }
}

function testInheritance() {
    const a = new Animal("Snake", 0)
    println(a.describe())
    if (a.legs != 0) { exit(1) }
}

function testSubclass() {
    const c = new Cat("Whiskers", 4, 1)
    println(c.describe())
    if (c.legs != 4) { exit(1) }
    if (c.indoor != 1) { exit(1) }
}

function main() {
    testInheritance()
    testSubclass()
    println("pir_inherit: all passed")
}
