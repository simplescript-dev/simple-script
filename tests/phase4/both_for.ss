function main() {
    const fruits = [1, 2, 3, 4, 5]

    // for-in: no index needed
    println("for-in:")
    for (n in fruits) {
        print(n + " ")
    }
    println("")

    // C-style: when you need the index
    println("C-style with index:")
    for (let i = 0; i < fruits.length(); i++) {
        println("  [" + i + "] = " + fruits[i])
    }
}
