// Test: Class field destructors via RC
// When a class instance's rc drops to 0, ptr fields should be released

class Person(name: string, age: int) {
    function greet(): string {
        return `Hello, ${this.name}`
    }
}

class Pair(first: string, second: string) {
    function toString(): string {
        return `(${this.first}, ${this.second})`
    }
}

class Container(label: string, value: int) {
}

function testBasicClassDtor() {
    // Person has "name" (string/ptr field) → gets dtor
    const p = new Person("Alice", 30)
    println(p.greet())
    // p goes out of scope → destroy releases "name" string
}

function testMultiplePtrFields() {
    // Pair has two ptr fields → dtor releases both
    const pair = new Pair("hello", "world")
    println(pair.toString())
    // pair goes out of scope → destroy releases both strings
}

function testMixedFields() {
    // Container has one ptr (label) and one scalar (value) → dtor only releases label
    const c = new Container("test", 42)
    println(c.label)
    println(c.value)
}

function testMultipleInstances() {
    const p1 = new Person("Bob", 25)
    const p2 = new Person("Charlie", 35)
    println(p1.name)
    println(p2.name)
    // Both instances freed, both name strings released
}

function main() {
    testBasicClassDtor()
    testMultiplePtrFields()
    testMixedFields()
    testMultipleInstances()
    println("class dtor ok")
}
