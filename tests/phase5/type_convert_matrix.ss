// Regression: i64 ↔ typed value conversion across all element types and usage contexts
// Catches: emitI64ToValue wrong trunc for unknown types, missing double paths

function main() {
    // ── Array element access × template string (emitI64ToValue + genExprAsString) ──
    // Untyped int array — inferArrayElemType returns "", inferType returns "i64"
    const ints = [10, 20, 30]
    if (ints[0] != 10) { exit(1) }
    println(`int: ${ints[0]}`)

    // Typed string array
    const strs: Array<string> = ["hello", "world"]
    if (strs[0] != "hello") { exit(2) }
    println(`str: ${strs[0]}`)

    // Typed double array
    const dbls: Array<double> = [1.5, 2.5, 3.5]
    if (dbls[0] != 1.5) { exit(3) }
    println(`dbl: ${dbls[0]}`)

    // ── Array element in arithmetic ──
    let sum = ints[0] + ints[1] + ints[2]
    if (sum != 60) { exit(4) }

    let dsum = dbls[0] + dbls[1]
    if (dsum != 4.0) { exit(5) }

    // ── for-in with typed arrays ──
    let total = 0
    for (n in ints) {
        total = total + n
    }
    if (total != 60) { exit(6) }

    let dtotal = 0.0
    for (d in dbls) {
        dtotal = dtotal + d
    }
    if (dtotal != 7.5) { exit(7) }

    let concat = ""
    for (s in strs) {
        concat = concat + s
    }
    if (concat != "helloworld") { exit(8) }

    // ── Array index as function argument ──
    if (doubleIt(ints[1]) != 40) { exit(9) }
    if (greet(strs[0]) != "hi hello") { exit(10) }

    // ── Compound assignment with doubles ──
    let x = 1.0
    x += 2.5
    if (x != 3.5) { exit(11) }
    x -= 1.0
    if (x != 2.5) { exit(12) }
    x *= 2.0
    if (x != 5.0) { exit(13) }
    x /= 2.0
    if (x != 2.5) { exit(14) }
}

function doubleIt(n: int): int {
    return n * 2
}

function greet(name: string): string {
    return "hi " + name
}
