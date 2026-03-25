function main() {
    const s = "Hello, SimpleScript!"

    // Method syntax for string operations
    println(`length: ${s.length()}`)
    println(`indexOf("Script"): ${s.indexOf("Script")}`)
    println(`substring(7, 8): ${s.substring(7, 8)}`)

    // Chain with other operations
    const name = "42"
    const num = name.toInt()
    println(`"42".toInt() * 2 = ${num * 2}`)

    // Works on expressions
    const greeting = "hello world"
    if (greeting.indexOf("world") >= 0) {
        println("found 'world' in greeting")
    }

    // Comparison with function syntax (both work)
    const len1 = s.length()
    const len2 = s.length()
    if (len1 == len2) {
        println(`method and function return same: ${len1}`)
    }
}
