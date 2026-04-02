// Test: PIR with method calls and class instances passed as arguments
class Rect {
    w: int
    h: int

    function area(): int {
        return this.w * this.h
    }
    function perimeter(): int {
        return 2 * (this.w + this.h)
    }
}

function describeRect(r: Rect): string {
    return `Rect(${r.w}x${r.h}) area=${r.area()}`
}

function testMethodCalls() {
    const r = new Rect(10, 5)
    if (r.area() != 50) { exit(1) }
    if (r.perimeter() != 30) { exit(1) }
    const desc = describeRect(r)
    println(desc)
}

function makeRect(w: int, h: int): Rect {
    return new Rect(w, h)
}

function testFactoryReturn() {
    const r = makeRect(7, 3)
    if (r.area() != 21) { exit(1) }
    if (r.w != 7) { exit(1) }
}

function main() {
    testMethodCalls()
    testFactoryReturn()
    println("pir_method_call: all passed")
}
