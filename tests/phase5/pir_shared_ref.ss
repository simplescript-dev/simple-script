// Test: PIR shared references — RC_INC on assignment from another variable
class Point(x: int, y: int) {
    function distSq(): int {
        return this.x * this.x + this.y * this.y
    }
}

function testSharedRef() {
    const p1 = new Point(3, 4)
    const p2 = p1
    // Both p1 and p2 reference the same object
    if (p1.x != 3) { exit(1) }
    if (p2.x != 3) { exit(1) }
    if (p1.distSq() != 25) { exit(1) }
    if (p2.distSq() != 25) { exit(1) }
}

function testChainedUse() {
    const a = new Point(1, 2)
    const b = a
    const c = b
    if (c.x != 1) { exit(1) }
    if (c.y != 2) { exit(1) }
}

function main() {
    testSharedRef()
    testChainedUse()
    println("pir_shared_ref: all passed")
}
