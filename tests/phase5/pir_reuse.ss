// Test: PIR Pass 5 — reuse analysis
// When a unique variable is dropped and the next statement allocates
// the same type, memory is reused (ss_drop_fields + new_reuse).

class Point {
    x: int
    y: int
}

class Weapon {
    const name: string
    damage: int
}

class Hero {
    const name: string
    health: int
    weapon: Weapon
}

// Basic same-type reuse: drop Point, alloc Point
function testBasicReuse() {
    const p1 = new Point(1, 2)
    const x1 = p1.x
    const p2 = new Point(3, 4)
    if (p2.x != 3) { exit(1) }
    if (p2.y != 4) { exit(1) }
    if (x1 != 1) { exit(1) }
    println("basic reuse ok")
}

// Reuse with string fields: old string released, new string retained
function testReuseWithStrings() {
    const w1 = new Weapon("Sword", 30)
    const n1 = w1.name
    const w2 = new Weapon("Axe", 40)
    if (w2.name != "Axe") { exit(1) }
    if (w2.damage != 40) { exit(1) }
    if (n1 != "Sword") { exit(1) }
    println("reuse with strings ok")
}

// No reuse — different types (Point dropped, Weapon allocated)
function testNoReuseDiffType() {
    const p = new Point(5, 6)
    const px = p.x
    const w = new Weapon("Bow", 20)
    if (w.damage != 20) { exit(1) }
    if (px != 5) { exit(1) }
    println("no reuse diff type ok")
}

// No reuse — shared reference (not unique)
function testNoReuseShared() {
    const p1 = new Point(7, 8)
    const p1ref = p1
    const px = p1ref.x
    const p2 = new Point(9, 10)
    if (p2.x != 9) { exit(1) }
    if (px != 7) { exit(1) }
    println("no reuse shared ok")
}

// Reuse with class-typed field (Weapon inside Hero)
function testReuseWithClassField() {
    const w = new Weapon("Staff", 25)
    const h1 = new Hero("Alice", 100, w)
    const name1 = h1.name
    const h2 = new Hero("Bob", 80, w)
    if (h2.name != "Bob") { exit(1) }
    if (h2.health != 80) { exit(1) }
    if (h2.weapon.damage != 25) { exit(1) }
    if (name1 != "Alice") { exit(1) }
    println("reuse with class field ok")
}

// Sequential reuses in loop-like pattern
function testSequentialReuse() {
    const p1 = new Point(1, 1)
    const v1 = p1.x + p1.y
    const p2 = new Point(2, 2)
    const v2 = p2.x + p2.y
    const p3 = new Point(3, 3)
    const v3 = p3.x + p3.y
    if (v1 != 2) { exit(1) }
    if (v2 != 4) { exit(1) }
    if (v3 != 6) { exit(1) }
    println("sequential reuse ok")
}

// Reuse with field mutation before drop
function testReuseAfterMutation() {
    const p1 = new Point(10, 20)
    p1.x = 15
    const val = p1.x
    const p2 = new Point(30, 40)
    if (p2.x != 30) { exit(1) }
    if (p2.y != 40) { exit(1) }
    if (val != 15) { exit(1) }
    println("reuse after mutation ok")
}

function main() {
    testBasicReuse()
    testReuseWithStrings()
    testNoReuseDiffType()
    testNoReuseShared()
    testReuseWithClassField()
    testSequentialReuse()
    testReuseAfterMutation()
    println("pir_reuse: all passed")
}
