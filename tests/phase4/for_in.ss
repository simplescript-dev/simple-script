function main() {
    const nums = [10, 20, 30, 40, 50]

    // for-in loop
    println("for-in:")
    for (item in nums) {
        println("  " + item)
    }

    // array.length()
    println("length: " + nums.length())

    // sum with for-in
    let sum = 0
    for (n in nums) {
        sum = sum + n
    }
    println("sum: " + sum)

    // for-in with break
    println("break at 30:")
    for (n in nums) {
        if (n == 30) { break }
        println("  " + n)
    }

    // for-in + method
    const names = [1, 2, 3, 4, 5]
    print("squares: ")
    for (n in names) {
        print(n * n + " ")
    }
    println("")
}
