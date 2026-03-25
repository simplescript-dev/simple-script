function main() {
    const s = "  Hello, World!  "

    // trim
    const trimmed = s.trim()
    println("trim: '" + trimmed + "'")

    // case conversion
    println("upper: " + trimmed.toUpperCase())
    println("lower: " + trimmed.toLowerCase())

    // startsWith / endsWith / contains
    println("startsWith 'Hello': " + trimmed.startsWith("Hello"))
    println("endsWith '!': " + trimmed.endsWith("!"))
    println("contains 'World': " + trimmed.contains("World"))
    println("contains 'xyz': " + trimmed.contains("xyz"))

    // replace
    const replaced = trimmed.replace("World", "SimpleScript")
    println("replace: " + replaced)

    // charAt
    println("charAt(0): " + trimmed.charAt(0))
    println("charAt(7): " + trimmed.charAt(7))

    // chaining
    const result = "  foo bar  ".trim().toUpperCase().replace("FOO", "HELLO")
    println("chain: " + result)
}
