// Test: PIR Pass 2 — Move Analysis
// When let b = a and a is never used after, the retain+release pair is eliminated.
// Correctness: b owns the reference, final RC_DEC frees it properly.

class Vec2 {
    x: int
    y: int

    function mag(): int {
        return this.x * this.x + this.y * this.y
    }
}

class Box {
    label: string
    value: int
}

// Case 1: simple move — a not used after let b = a
function testSimpleMove() {
    let a = new Vec2(3, 4)
    let b = a
    // a is not used after this point — move optimization applies
    if (b.x != 3) { exit(1) }
    if (b.y != 4) { exit(1) }
    if (b.mag() != 25) { exit(1) }
}

// Case 2: chained moves — a→b→c, each source unused after
function testChainedMove() {
    let a = new Vec2(10, 20)
    let b = a
    let c = b
    // a, b not used after — two moves
    if (c.x != 10) { exit(1) }
    if (c.y != 20) { exit(1) }
}

// Case 3: NOT a move — a is used after the assignment
function testNotAMove() {
    let a = new Vec2(5, 6)
    let b = a
    // a IS used after — retain must happen (not a move)
    if (a.x != 5) { exit(1) }
    if (b.x != 5) { exit(1) }
}

// Case 4: move with function return
function makeBox(): Box {
    let b = new Box("test", 42)
    return b
}

function testMoveWithReturn() {
    let b = makeBox()
    let c = b
    // b not used after — move
    if (c.label != "test") { exit(1) }
    if (c.value != 42) { exit(1) }
}

// Case 5: move into function argument context
function consume(v: Vec2): int {
    return v.mag()
}

function testMoveBeforeCall() {
    let a = new Vec2(1, 2)
    let b = a
    // a not used after — move
    let result = consume(b)
    if (result != 5) { exit(1) }
}

// Case 6: multiple independent objects — some moves, some not
function testMixed() {
    let a = new Vec2(1, 0)
    let b = new Vec2(0, 1)
    let c = a
    // a not used after → move
    // b still used → not move
    if (c.x != 1) { exit(1) }
    if (b.y != 1) { exit(1) }
}

function main() {
    testSimpleMove()
    testChainedMove()
    testNotAMove()
    testMoveWithReturn()
    testMoveBeforeCall()
    testMixed()
    println("pir_move: all passed")
}
