class Animal(name: string, sound: string) {
    function speak(): string {
        return this.name + " says " + this.sound
    }
}

class Dog extends Animal(breed: string) {
    function info(): string {
        return this.breed
    }
}

function main() {
    const a = new Animal("Cat", "meow")
    println(a.speak())

    const d = new Dog("Rex", "woof", "Lab")
    println("created dog")
    println(d.info())
    println("calling speak...")
    println(d.speak())
}
