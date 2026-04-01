// Tuple types: [type, type, ...] — fixed-length typed arrays

function getCoords(): [int, int] {
    return [10, 20]
}

function getPair(): [string, int] {
    return ["hello", 42]
}

function getMixed(): [int, string, int] {
    return [1, "two", 3]
}

function main() {
    // Basic tuple with type annotation
    let t: [int, string] = [100, "world"]
    const a = t[0]
    const b = t[1]
    if (a != 100) { exit(1) }
    if (b != "world") { exit(1) }

    // Tuple from function return
    const coords = getCoords()
    if (coords[0] != 10) { exit(1) }
    if (coords[1] != 20) { exit(1) }

    // Mixed type tuple from function
    const pair = getPair()
    if (pair[0] != "hello") { exit(1) }
    if (pair[1] != 42) { exit(1) }

    // Tuple destructuring
    const [x, y] = getCoords()
    if (x != 10) { exit(1) }
    if (y != 20) { exit(1) }

    // Mixed type destructuring
    const [s, n] = getPair()
    if (s != "hello") { exit(1) }
    if (n != 42) { exit(1) }

    // Triple tuple
    const triple = getMixed()
    if (triple[0] != 1) { exit(1) }
    if (triple[1] != "two") { exit(1) }
    if (triple[2] != 3) { exit(1) }

    // Triple destructuring
    const [p, q, r] = getMixed()
    if (p != 1) { exit(1) }
    if (q != "two") { exit(1) }
    if (r != 3) { exit(1) }

    // Tuple as function parameter
    println("tuple tests passed")
}
