// Test: deepClone with inheritance — child class fields cloned correctly
class Weapon(const name: string, damage: int)

class Entity(const tag: string, hp: int, weapon: Weapon)

class Hero extends Entity(level: int) {
    function info(): string {
        return `${this.tag} lv${this.level} hp${this.hp} w=${this.weapon.name}(${this.weapon.damage})`
    }
}

function main() {
    let a = new Hero("knight", 100, new Weapon("Sword", 30), 5)
    let b = a.deepClone()

    // b is fully independent
    b.hp = 50
    b.level = 10
    b.weapon.damage = 99
    if (a.hp != 100) { exit(1) }
    if (a.level != 5) { exit(1) }
    if (a.weapon.damage != 30) { exit(1) }
    if (b.hp != 50) { exit(1) }
    if (b.level != 10) { exit(1) }
    if (b.weapon.damage != 99) { exit(1) }

    // Const fields shared safely
    if (b.tag != "knight") { exit(1) }
    if (b.weapon.name != "Sword") { exit(1) }

    // Method works on cloned object
    let info = b.info()
    if (info != "knight lv10 hp50 w=Sword(99)") { exit(1) }

    println("deep_clone_inherit: all passed")
}
