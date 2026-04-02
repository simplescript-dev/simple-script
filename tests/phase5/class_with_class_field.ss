// Test: class field holding another class instance (RC correctness)
class Weapon {
    name: string
    damage: int
}
class Player {
    name: string
    health: int
    weapon: Weapon
}

function main() {
    let sword = new Weapon("Sword", 50)
    let hero = new Player("Alice", 100, sword)
    // Read through nested access
    if (hero.weapon.damage != 50) { exit(1) }
    // Modify nested field
    hero.weapon.damage += 10
    if (hero.weapon.damage != 60) { exit(1) }
    if (sword.damage != 60) { exit(1) }
    // Replace weapon field with new object
    let axe = new Weapon("Axe", 80)
    hero.weapon = axe
    if (hero.weapon.damage != 80) { exit(1) }
    if (hero.weapon.name != "Axe") { exit(1) }
    // Old sword should still be valid (has its own ref)
    if (sword.damage != 60) { exit(1) }
    println("class_with_class_field: all passed")
}
