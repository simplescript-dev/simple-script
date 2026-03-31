// Test: user-defined deepClone override (spec §1.6)
class Config(name: string, value: int)

class Player(const id: string, health: int, config: Config) {
    // User overrides deepClone — doubles health on clone
    function deepClone(): Player {
        return new Player(this.id, this.health * 2, this.config.deepClone())
    }
}

function main() {
    let a = new Player("p1", 50, new Config("mode", 1))
    let b = a.deepClone()

    // User override doubles health
    if (b.health != 100) { exit(1) }

    // id shared (const string)
    if (b.id != "p1") { exit(1) }

    // config is deep-cloned (independent)
    b.config.value = 99
    if (a.config.value != 1) { exit(1) }
    if (b.config.value != 99) { exit(1) }

    println("clone_override: all passed")
}
