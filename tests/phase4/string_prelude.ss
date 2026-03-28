function main() {
    // trim
    println("  hello  ".trim())
    // toUpperCase / toLowerCase
    println("hello".toUpperCase())
    println("WORLD".toLowerCase())
    // replace
    println("hello world".replace("world", "SS"))
    // repeat
    println("ab".repeat(3))
    // padStart / padEnd
    println("42".padStart(5, "0"))
    println("hi".padEnd(5, "."))
    // join
    const arr = ["a", "b", "c"]
    println(arr.join("-"))
    // contains / startsWith / endsWith (inlined)
    println("hello".contains("ell"))
    println("hello".startsWith("hel"))
    println("hello".endsWith("llo"))
    println("done")
}
