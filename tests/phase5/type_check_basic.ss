// Type checking: verify that correctly-typed code compiles and runs.
// Tests exercise checkerInferType + isTypeCompatible paths.

class Animal {
    const name: string
    age: int
}

class Dog extends Animal {
    breed: string
}

function addInts(a: int, b: int): int {
    return a + b
}

function greet(name: string): string {
    return `Hello, ${name}`
}

function setAge(animal: Animal, newAge: int) {
    animal.age = newAge
}

function acceptDouble(x: double) {
    // int -> double widening is valid
}

function main() {
    // VAR_DECL: matching types
    const x: int = 42
    const y: double = 3.14
    const s: string = "hello"
    const d: double = 10  // int -> double widening

    // CALL: correct argument types
    const sum = addInts(1, 2)
    const msg = greet("world")
    acceptDouble(5)  // int -> double widening

    // Class types
    const dog = new Dog("Rex", 3, "Lab")

    // Inheritance: Dog extends Animal, so Dog is compatible with Animal param
    setAge(dog, 5)

    // MEMBER_ASSIGN: correct field type
    dog.age = 7
    dog.breed = "Husky"

    // ASSIGN: compatible types
    let n: int = 10
    n = 20

    let label: string = "start"
    label = "end"

    // Verify values are correct
    if (sum != 3) { exit(1) }
    if (dog.age != 7) { exit(1) }
    if (dog.breed != "Husky") { exit(1) }
    println("type_check_basic: all passed")
}
