// Test: optional method call (obj?.method()) — no double evaluation

let callCount = 0

class Box {
    value: int

    function getValue(): int {
        return this.value
    }
    function add(n: int): int {
        return this.value + n
    }
}

function makeBox(): Box {
    callCount = callCount + 1
    return new Box(42)
}

function makeNull(): Box? {
    callCount = callCount + 1
    return null
}

function main() {
    // Basic optional method call on non-null
    const box = new Box(10)
    const v1 = box?.getValue()
    if (v1 != 10) { throw("basic optional method failed") }

    // Optional method call on null — returns 0 for int
    let nullBox: Box? = null
    const v2 = nullBox?.getValue()
    if (v2 != 0) { throw("null optional method should return 0") }

    // Key test: function-returning object should be called exactly once
    callCount = 0
    const v3 = makeBox()?.getValue()
    if (v3 != 42) { throw("makeBox optional method failed") }
    if (callCount != 1) { throw("makeBox called more than once") }

    // Null-returning function should be called exactly once
    callCount = 0
    const v4 = makeNull()?.add(5)
    if (v4 != 0) { throw("null optional method with arg should return 0") }
    if (callCount != 1) { throw("makeNull called more than once") }

    // Optional method with args on non-null
    const v5 = makeBox()?.add(8)
    if (v5 != 50) { throw("optional method with arg failed") }

    println("optional_method: all passed")
}
