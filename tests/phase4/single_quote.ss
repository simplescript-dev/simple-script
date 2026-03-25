function main() {
    // Single-quoted strings
    const s1 = 'hello'
    const s2 = "hello"
    println("single: " + s1)
    println("double: " + s2)

    if (s1 == s2) {
        println("equal: true")
    }

    // Single quotes can contain double quotes
    const html = '<div class="main">content</div>'
    println("html: " + html)

    // Double quotes can contain single quotes
    const msg = "it's working"
    println("msg: " + msg)

    // Escape in single quotes
    const escaped = 'line1\nline2'
    println("escaped: " + escaped)
}
