// Test: deepClone — fully independent copy
class Vec2 {
    x: int
    y: int
}
class Player {
    const name: string
    health: int
    pos: Vec2
}

function main() {
    let a = new Player("Alice", 100, new Vec2(1, 2))
    let b = a.deepClone()

    // b is independent: modifying b does not affect a
    b.health = 50
    if (a.health != 100) { exit(1) }
    if (b.health != 50) { exit(1) }

    // Mutable class-type field is recursively cloned
    b.pos.x = 99
    if (a.pos.x != 1) { exit(1) }
    if (b.pos.x != 99) { exit(1) }

    // Const string field is shared (same pointer, but immutable so safe)
    if (b.name != "Alice") { exit(1) }

    println("deep_clone: all passed")
}
