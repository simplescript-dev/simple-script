// Regression: untyped array element access (inferArrayElemType returns "")
// Catches: emitI64ToValue trunc on unknown type, for-in with untyped arrays

function makeArray(): Array<int> {
    return [100, 200, 300]
}

function pickFirst(arr: Array<string>): string {
    return arr[0]
}

function main() {
    // Array from function return — element type inferred via return type
    const arr = makeArray()
    if (arr[0] != 100) { exit(1) }
    println(`first: ${arr[0]}`)

    // for-in over function-returned array
    let sum = 0
    for (v in arr) {
        sum = sum + v
    }
    if (sum != 600) { exit(2) }

    // String array passed to function
    const names = ["alice", "bob"]
    if (pickFirst(names) != "alice") { exit(3) }

    // Index access in various expression positions
    const a = [5, 10, 15]
    const mid = a[1]
    if (mid != 10) { exit(4) }

    // Array element as condition
    const flags = [1, 0, 1]
    if (flags[1] != 0) { exit(5) }

    // Nested array access in template
    const matrix = [[1, 2], [3, 4]]
    if (matrix[0][0] != 1) { exit(6) }
    if (matrix[1][1] != 4) { exit(7) }
    println(`matrix[1][1] = ${matrix[1][1]}`)
}
