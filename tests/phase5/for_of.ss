// Test: for-of loops (TS-aligned syntax)

function main() {
    // Basic for-of with const
    const nums = [10, 20, 30]
    let sum = 0
    for (const n of nums) {
        sum = sum + n
    }
    if (sum != 60) { throw("basic for-of sum failed") }

    // for-of with let
    let count = 0
    for (let x of nums) {
        count = count + 1
    }
    if (count != 3) { throw("for-of let count failed") }

    // for-of with strings
    const names: Array<string> = ["Alice", "Bob", "Charlie"]
    let result = ""
    for (const name of names) {
        result = result + name + " "
    }
    if (result != "Alice Bob Charlie ") { throw("for-of strings failed") }

    // for-of with break
    let breakSum = 0
    for (const n of nums) {
        if (n == 30) { break }
        breakSum = breakSum + n
    }
    if (breakSum != 30) { throw("for-of break failed") }

    // for-of with continue
    let skipSum = 0
    for (const n of nums) {
        if (n == 20) { continue }
        skipSum = skipSum + n
    }
    if (skipSum != 40) { throw("for-of continue failed") }

    // Bare for-of (no const/let)
    let bareSum = 0
    for (item of nums) {
        bareSum = bareSum + item
    }
    if (bareSum != 60) { throw("bare for-of failed") }

    // for-in still works
    let forinSum = 0
    for (n in nums) {
        forinSum = forinSum + n
    }
    if (forinSum != 60) { throw("for-in still works") }

    println("for_of: all passed")
}
