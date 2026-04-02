// Type checking: NEW_EXPR constructor argument types.
// Tests both positional and named constructor calls with correct types.

class Point {
    x: int
    y: int
}

class Player {
    const name: string
    health: int
    score: double
}

class Animal {
    const name: string
    age: int
}

class Dog extends Animal {
    breed: string
}

function main() {
    // Positional args: correct types
    const p = new Point(10, 20)
    const player = new Player("Alice", 100, 95.5)
    const dog = new Dog("Rex", 3, "Labrador")

    // Named args: correct types
    const p2 = new Point(x: 5, y: 15)
    const player2 = new Player(name: "Bob", health: 80, score: 88.0)
    const dog2 = new Dog(name: "Buddy", age: 2, breed: "Poodle")

    // int -> double widening in constructor
    const player3 = new Player("Eve", 50, 70)

    // Verify values
    if (p.x != 10) { exit(1) }
    if (p.y != 20) { exit(1) }
    if (player.name != "Alice") { exit(1) }
    if (player.health != 100) { exit(1) }
    if (dog.breed != "Labrador") { exit(1) }
    if (p2.x != 5) { exit(1) }
    if (player2.name != "Bob") { exit(1) }
    if (dog2.breed != "Poodle") { exit(1) }
    println("type_check_new_expr: all passed")
}
