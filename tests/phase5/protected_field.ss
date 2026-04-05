// Test: protected fields — accessible within class and subclass
class Animal {
    protected sound: string
    name: string

    function getSound(): string {
        return this.sound
    }
}

class Dog extends Animal {
    breed: string

    function bark(): string {
        return this.sound
    }

    function setSound(s: string) {
        this.sound = s
    }
}

class GuideDog extends Dog {
    function guideBark(): string {
        return this.sound
    }
}

function main() {
    let d = new Dog("woof", "Rex", "Lab")
    // Public field — OK
    if (d.name != "Rex") { exit(1) }
    if (d.breed != "Lab") { exit(1) }
    // Protected access via parent public method — OK
    if (d.getSound() != "woof") { exit(1) }
    // Protected access via subclass method — OK
    if (d.bark() != "woof") { exit(1) }
    // Modify protected field from subclass — OK
    d.setSound("bark")
    if (d.bark() != "bark") { exit(1) }
    // Grandchild access — OK
    let g = new GuideDog("arf", "Buddy", "Retriever")
    if (g.guideBark() != "arf") { exit(1) }
    println("protected_field: all passed")
}
