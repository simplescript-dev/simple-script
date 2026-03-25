function main() {
    // Array push
    println("=== Array Push ===")
    let nums = [1, 2, 3]
    println("before: " + nums.length())
    nums = nums.push(4)
    nums = nums.push(5)
    println("after: " + nums.length())
    for (n in nums) {
        print(n + " ")
    }
    println("")

    // Map keys and delete
    println("")
    println("=== Map ===")
    const scores = Map()
    scores.set("alice", 95)
    scores.set("bob", 87)
    scores.set("charlie", 92)
    println("size: " + scores.size())
    println("keys: " + scores.keys())

    scores.delete("bob")
    println("after delete: size=" + scores.size())
    println("has bob: " + scores.has("bob"))

    // Build array dynamically
    println("")
    println("=== Dynamic Array ===")
    let arr = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    for (let i = 0; i < 10; i++) {
        arr[i] = i * i
    }
    for (n in arr) {
        print(n + " ")
    }
    println("")
}
