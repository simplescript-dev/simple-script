// Test: nested field assignment and shared references
class Vec2(x: int, y: int)
class Entity(name: string, hp: int, pos: Vec2)

function moveTo(e: Entity, nx: int, ny: int) {
    e.pos.x = nx
    e.pos.y = ny
}

function main() {
    let pos = new Vec2(0, 0)
    let e = new Entity("hero", 100, pos)
    // Direct nested field assign
    e.pos.x = 5
    e.pos.y = 10
    if (e.pos.x != 5) { exit(1) }
    if (e.pos.y != 10) { exit(1) }
    // Shared ref sees change
    if (pos.x != 5) { exit(1) }
    // Function mutates nested field
    moveTo(e, 20, 30)
    if (e.pos.x != 20) { exit(1) }
    if (pos.y != 30) { exit(1) }
    // Compound assignment on nested field
    e.pos.x += 5
    if (e.pos.x != 25) { exit(1) }
    e.hp -= 10
    if (e.hp != 90) { exit(1) }
    println("nested_field: all passed")
}
