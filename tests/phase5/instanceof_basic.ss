// Test: instanceof operator — basic class type checking

class Animal {
    name: string
}

class Dog extends Animal {
    breed: string
}

class Cat extends Animal {
    indoor: int
}

function main() {
    const dog = new Dog(name: "Rex", breed: "Labrador")
    const cat = new Cat(name: "Whiskers", indoor: 1)

    // Direct type check
    if (!(dog instanceof Dog)) { exit(1) }
    if (!(cat instanceof Cat)) { exit(2) }

    // Inheritance check — Dog is also Animal
    if (!(dog instanceof Animal)) { exit(3) }
    if (!(cat instanceof Animal)) { exit(4) }

    // Negative check — Dog is not Cat
    if (dog instanceof Cat) { exit(5) }
    if (cat instanceof Dog) { exit(6) }
}
