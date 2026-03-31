// Test: PIR basic — class instances in function body get PIR-managed RC
class Dog(name: string, age: int) {
    function bark(): string {
        return `${this.name} says woof!`
    }
}

function createDog(): Dog {
    const d = new Dog("Rex", 3)
    return d
}

function testLocalScope() {
    const d = new Dog("Buddy", 5)
    println(d.bark())
    // d's RC_DEC scheduled by PIR at last use (here)
}

function testReturnEscape() {
    // createDog returns d → PIR marks as escaped, no RC_DEC inside createDog
    const d = createDog()
    println(d.bark())
    if (d.name != "Rex") { exit(1) }
    if (d.age != 3) { exit(1) }
}

function testMultipleVars() {
    const d1 = new Dog("Alpha", 1)
    const d2 = new Dog("Beta", 2)
    println(d1.name)
    println(d2.name)
    if (d1.age != 1) { exit(1) }
    if (d2.age != 2) { exit(1) }
}

function main() {
    testLocalScope()
    testReturnEscape()
    testMultipleVars()
    println("pir_basic: all passed")
}
