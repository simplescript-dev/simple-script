// Test: spec/71-perceus-rc.md key examples

// §1.1 field-level const
class Player {
    const name: string
    health: int
    x: int
    y: int
}

// §1.2 Assignment semantics — shared reference
function testSharedRef() {
    let a = new Player("Alice", 100, 0, 0)
    let b = a
    a.health -= 20
    // b and a point to same object — change visible
    if (b.health != 80) { exit(1) }
}

// §1.3 Field assignment
function testFieldAssign() {
    let hero = new Player("Alice", 100, 0, 0)
    hero.health -= 25
    hero.x = 10
    if (hero.health != 75) { exit(1) }
    if (hero.x != 10) { exit(1) }
    // hero.name = "Bob" → would be compile error (const field)
}

// §1.5 Function parameter mutation visible to caller
function damage(p: Player, amount: int) {
    p.health -= amount
}

function testFuncParamMutation() {
    let hero = new Player("Alice", 100, 0, 0)
    damage(hero, 25)
    if (hero.health != 75) { exit(1) }
}

// §1.6 deepClone/shallowClone
class Vec2 {
    x: int
    y: int
}
class Entity {
    const tag: string
    hp: int
    pos: Vec2
}

function testDeepClone() {
    let a = new Entity("hero", 100, new Vec2(1, 2))
    let c = a.deepClone()
    c.hp = 50
    c.pos.x = 99
    // a unaffected
    if (a.hp != 100) { exit(1) }
    if (a.pos.x != 1) { exit(1) }
    // c independent
    if (c.hp != 50) { exit(1) }
    if (c.pos.x != 99) { exit(1) }
}

function testShallowClone() {
    let a = new Entity("hero", 100, new Vec2(5, 10))
    let d = a.shallowClone()
    d.hp = 50
    if (a.hp != 100) { exit(1) }
    // shallowClone shares internal refs
    d.pos.x = 99
    if (a.pos.x != 99) { exit(1) }
}

// §1.4 let vs const binding (const prevents rebinding but allows mutable field writes)
function testConstBinding() {
    const hero2 = new Player("Alice", 100, 0, 0)
    hero2.health -= 25
    if (hero2.health != 75) { exit(1) }
    // hero2 = new Player("Bob", 80, 1, 1) → would be compile error
}

function main() {
    testSharedRef()
    testFieldAssign()
    testFuncParamMutation()
    testDeepClone()
    testShallowClone()
    testConstBinding()
    println("spec_examples: all passed")
}
