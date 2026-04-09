function main() {
    // Test 1: let + empty array + push
    let a: Array<string> = []
    a.push("x")
    a.push("y")
    a.push("z")
    if (a.length() != 3) { exit(1) }
    if (a[0] != "x") { exit(1) }
    if (a[2] != "z") { exit(1) }

    // Test 2: push in loop
    let b: Array<int> = []
    let i = 0
    while (i < 100) {
        b.push(i)
        i = i + 1
    }
    if (b.length() != 100) { exit(1) }
    if (b[0] != 0) { exit(1) }
    if (b[99] != 99) { exit(1) }

    // Test 3: push then read in loop
    let c: Array<string> = []
    i = 0
    while (i < 50) {
        c.push("val")
        i = i + 1
    }
    i = 0
    let dummy = ""
    while (i < 50) {
        dummy = c[i]
        i = i + 1
    }
    if (dummy != "val") { exit(1) }

    println("array_push_store_back: all passed")
}
