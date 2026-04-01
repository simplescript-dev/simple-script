// Test: this.field = value inside methods
class Counter(value: int, name: string) {
    function increment() {
        this.value += 1
    }
    function decrement() {
        this.value -= 1
    }
    function reset() {
        this.value = 0
    }
    function rename(n: string) {
        this.name = n
    }
}

class Weapon(damage: int)

class Player(name: string, health: int, weapon: Weapon) {
    function takeDamage(amount: int) {
        this.health -= amount
    }
    function heal(amount: int) {
        this.health += amount
    }
    function setWeapon(w: Weapon) {
        this.weapon = w
    }
    function upgradeWeapon(bonus: int) {
        this.weapon.damage += bonus
    }
}

function main() {
    // Simple this.field assignment
    let c = new Counter(0, "clicks")
    c.increment()
    c.increment()
    c.increment()
    if (c.value != 3) { exit(1) }
    c.decrement()
    if (c.value != 2) { exit(1) }
    c.reset()
    if (c.value != 0) { exit(1) }

    // this.field with string
    c.rename("taps")
    if (c.name != "taps") { exit(1) }

    // this.field on class with class field
    let sword = new Weapon(10)
    let hero = new Player("Alice", 100, sword)
    hero.takeDamage(25)
    if (hero.health != 75) { exit(1) }
    hero.heal(10)
    if (hero.health != 85) { exit(1) }

    // this.field = class instance
    let axe = new Weapon(20)
    hero.setWeapon(axe)
    if (hero.weapon.damage != 20) { exit(1) }

    // Nested: this.weapon.damage += bonus
    hero.upgradeWeapon(5)
    if (hero.weapon.damage != 25) { exit(1) }

    println("this_field_assign: all passed")
}
