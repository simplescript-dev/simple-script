// Test: PIR Pass 3 — uniqueness analysis
// Variables created by ALLOC with no shared references get direct drop
// (ss_drop_ClassName instead of ss_release) when released.
// NOTE: avoid template literals referencing class vars (seed bug workaround)

class Weapon(const name: string, damage: int)

class Hero(const name: string, health: int, weapon: Weapon) {
    function info(): string {
        return this.name
    }
}

// Local-only object: unique throughout, direct drop at scope exit
function testLocalUnique() {
    const w = new Weapon("Sword", 30)
    const h = new Hero("Alice", 100, w)
    println(h.info())
    if (h.health != 100) { exit(1) }
    if (h.weapon.damage != 30) { exit(1) }
    if (w.name != "Sword") { exit(1) }
}

// Field mutation on unique object
function testMutateUnique() {
    const w = new Weapon("Axe", 40)
    w.damage = 50
    if (w.damage != 50) { exit(1) }
    const d = w.damage
    println(d)
}

// Multiple unique locals — each gets direct drop independently
function testMultipleUnique() {
    const w1 = new Weapon("Bow", 20)
    const w2 = new Weapon("Staff", 15)
    if (w1.damage != 20) { exit(1) }
    if (w2.damage != 15) { exit(1) }
    println(w1.name)
    println(w2.name)
}

// Shared reference: source loses uniqueness, falls back to ss_release
function testSharedNotUnique() {
    const w = new Weapon("Dagger", 10)
    const w2 = w
    if (w.damage != 10) { exit(1) }
    if (w2.damage != 10) { exit(1) }
    w2.damage = 25
    if (w.damage != 25) { exit(1) }
    println(w.name)
}

// Return value escapes — no release inside function
function createWeapon(): Weapon {
    const w = new Weapon("Spear", 35)
    return w
}

function testReturnEscape() {
    const w = createWeapon()
    if (w.damage != 35) { exit(1) }
    println(w.name)
}

function main() {
    testLocalUnique()
    testMutateUnique()
    testMultipleUnique()
    testSharedNotUnique()
    testReturnEscape()
    println("pir_unique: all passed")
}
