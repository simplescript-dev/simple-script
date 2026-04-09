// Test: Array<string> index assignment with RC
// Verifies strings survive scope exit after being stored in array

function makeString(n: int): string {
    return "item_" + n
}

function main() {
    let arr: Array<string> = []
    arr.push("")
    arr.push("")
    arr.push("")

    // Assign via index — strings created in inner scope
    let i = 0
    while (i < 3) {
        const s = makeString(i)
        arr[i] = s
        i = i + 1
    }

    // Verify strings survive after function scope exit
    if (arr[0] != "item_0") { exit(1) }
    if (arr[1] != "item_1") { exit(1) }
    if (arr[2] != "item_2") { exit(1) }

    // Overwrite — old values should be released, new retained
    arr[0] = "replaced"
    if (arr[0] != "replaced") { exit(1) }

    // Push + index assign mix
    let names: Array<string> = []
    names.push("alice")
    names.push("bob")
    names[1] = "charlie"
    if (names[0] != "alice") { exit(1) }
    if (names[1] != "charlie") { exit(1) }
}
