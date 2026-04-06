class Animal {
    name: string
}

class Dog extends Animal {
    breed: string
}

class Cat extends Animal {
    indoor: int
}

function checkDog(a: Animal): string {
    if (a instanceof Dog) {
        let d = a as Dog
        return d.breed
    }
    return "not a dog"
}

function main() {
    // Basic downcast
    let a: Animal = new Dog(name: "Rex", breed: "Labrador")
    let d = a as Dog
    if (d.breed != "Labrador") { throw("downcast failed") }

    // Upcast (always succeeds)
    let dog = new Dog(name: "Max", breed: "Poodle")
    let a2 = dog as Animal
    if (a2.name != "Max") { throw("upcast failed") }

    // Self-cast
    let d2 = dog as Dog
    if (d2.breed != "Poodle") { throw("self-cast failed") }

    // instanceof + as pattern
    let result = checkDog(new Dog(name: "Buddy", breed: "Beagle"))
    if (result != "Beagle") { throw("instanceof+as failed") }

    let result2 = checkDog(new Cat(name: "Kitty", indoor: 1))
    if (result2 != "not a dog") { throw("instanceof guard failed") }

    // Failed cast caught by try/catch
    let caught = 0
    try {
        let c: Animal = new Cat(name: "Whiskers", indoor: 1)
        let bad = c as Dog
    } catch (e) {
        caught = 1
    }
    if (caught != 1) { throw("failed cast not caught") }
}
