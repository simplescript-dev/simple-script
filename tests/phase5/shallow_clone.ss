// Test: shallowClone — first-layer copy, internal refs shared
class Vec2 {
    x: int
    y: int
}
class Entity {
    name: string
    hp: int
    pos: Vec2
}

function main() {
    let a = new Entity("hero", 100, new Vec2(5, 10))
    let b = a.shallowClone()

    // b has independent top-level fields
    b.hp = 50
    if (a.hp != 100) { exit(1) }
    if (b.hp != 50) { exit(1) }
    b.name = "clone"
    if (a.name != "hero") { exit(1) }

    // But internal ref-type field (pos) is SHARED
    b.pos.x = 99
    if (a.pos.x != 99) { exit(1) }

    println("shallow_clone: all passed")
}
