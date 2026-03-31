// Test: field assignment (mutable fields)
// Note: seed compiler cannot parse "const" in field decl, so we use all mutable for now
class Player(name: string, health: int, x: int, y: int)

function damage(p: Player, amount: int) {
    p.health -= amount
}

function main() {
    let hero = new Player("Alice", 100, 0, 0)
    hero.health -= 25
    if (hero.health != 75) { exit(1) }
    hero.x = 10
    hero.y = 20
    if (hero.x != 10) { exit(1) }
    if (hero.y != 20) { exit(1) }
    // Compound assignment
    hero.health += 5
    if (hero.health != 80) { exit(1) }
    // Function mutates shared reference
    damage(hero, 30)
    if (hero.health != 50) { exit(1) }
    println("field_assign: all passed")
}
