// Test: named parameter construction for classes

class Point {
    x: int
    y: int
}

class Player {
    const name: string
    health: int
    x: int
    y: int
}

function main() {
    // Basic named params (reordered)
    const p = new Point(y: 20, x: 10)
    if (p.x != 10) { exit(1) }
    if (p.y != 20) { exit(1) }

    // Named params with const + mutable fields
    const hero = new Player(health: 100, name: "Alice", x: 5, y: 10)
    if (hero.health != 100) { exit(1) }
    if (hero.x != 5) { exit(1) }
    if (hero.y != 10) { exit(1) }

    // Positional still works
    const p2 = new Point(1, 2)
    if (p2.x != 1) { exit(1) }
    if (p2.y != 2) { exit(1) }

    println("named_params: all passed")
}
