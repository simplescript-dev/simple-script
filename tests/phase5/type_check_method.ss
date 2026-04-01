// Test: METHOD_CALL argument type checking (D054)

class Weapon(const name: string, damage: int) {
    function getDamage(): int {
        return this.damage
    }
}

class Player(const name: string, health: int, weapon: Weapon) {
    function getHealth(): int {
        return this.health
    }

    function getWeapon(): Weapon {
        return this.weapon
    }

    function describe(prefix: string): string {
        return `${prefix}: ${this.name}`
    }
}

class Animal(const species: string) {
    function getSpecies(): string {
        return this.species
    }
}

class Dog extends Animal(const dogName: string) {
    function greet(msg: string): string {
        return `${this.dogName}: ${msg}`
    }
}

function main() {
    let sword = new Weapon("Sword", 25)
    let hero = new Player("Alice", 100, sword)

    // Method call with correct string param
    const desc = hero.describe("Hero")
    if (desc != "Hero: Alice") { exit(1) }

    // Method return type inference: getHealth() -> int
    if (hero.getHealth() != 100) { exit(1) }

    // Chain: getWeapon() returns Weapon, then getDamage() returns int
    if (hero.getWeapon().getDamage() != 25) { exit(1) }

    // Inherited method type checking
    let dog = new Dog("Canine", "Rex")
    const greeting = dog.greet("hello")
    if (greeting != "Rex: hello") { exit(1) }

    // Inherited method from parent
    if (dog.getSpecies() != "Canine") { exit(1) }

    println("method type check OK")
}
