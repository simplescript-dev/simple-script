function main() {
    // String array from split
    const parts = "hello,world,foo,bar".split(",")
    println("length: " + parts.length())

    // IndexAccess on string array
    println("parts[0]: " + parts[0])
    println("parts[2]: " + parts[2])

    // for-in on string array
    print("for-in: ")
    for (p in parts) {
        print(p + " ")
    }
    println("")

    // String methods on elements
    println("upper: " + parts[0].toUpperCase())
    println("contains 'oo': " + parts[2].contains("oo"))

    // Int array still works
    const nums = [10, 20, 30]
    let sum = 0
    for (n in nums) {
        sum += n
    }
    println("int sum: " + sum)
    println("nums[1]: " + nums[1])
}
