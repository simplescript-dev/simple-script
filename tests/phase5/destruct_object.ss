class Point(x: int, y: int)
class Player(const name: string, health: int)

function testPoint() {
    const p = new Point(3, 4)
    const { x, y } = p
    if (x != 3) { exit(1) }
    if (y != 4) { exit(1) }
}

function testPlayer() {
    const hero = new Player("Alice", 100)
    const { name, health } = hero
    if (health != 100) { exit(1) }
    if (name != "Alice") { exit(1) }
}

function testSubset() {
    const p = new Point(7, 8)
    const { y } = p
    if (y != 8) { exit(1) }
}

function testLet() {
    const p = new Point(1, 2)
    let { x, y } = p
    x = 10
    y = 20
    if (x != 10) { exit(1) }
    if (y != 20) { exit(1) }
}

function testAlias() {
    const p = new Point(5, 6)
    const { x: posX, y: posY } = p
    if (posX != 5) { exit(1) }
    if (posY != 6) { exit(1) }
}

function testAliasString() {
    const hero = new Player("Bob", 50)
    const { name: playerName, health: hp } = hero
    if (playerName != "Bob") { exit(1) }
    if (hp != 50) { exit(1) }
}

function testAliasMixed() {
    const p = new Point(9, 10)
    const { x: px, y } = p
    if (px != 9) { exit(1) }
    if (y != 10) { exit(1) }
}

function main() {
    testPoint()
    testPlayer()
    testSubset()
    testLet()
    testAlias()
    testAliasString()
    testAliasMixed()
    println("destruct_object: all passed")
}
