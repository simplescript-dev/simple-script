// Test: built-in Error class

class IOError extends Error {
    path: string
}

class ParseError extends Error {
    line: int
    col: int
}

function main() {
    // Test 1: Error base class
    const e = new Error("something failed")
    if (e.message != "something failed") { exit(1) }

    // Test 2: Custom error extends Error
    const io = new IOError("file not found", "/data.txt")
    if (io.message != "file not found") { exit(1) }
    if (io.path != "/data.txt") { exit(1) }

    // Test 3: Another custom error
    const pe = new ParseError("unexpected token", 42, 10)
    if (pe.message != "unexpected token") { exit(1) }
    if (pe.line != 42) { exit(1) }
    if (pe.col != 10) { exit(1) }

    println("error_class: all tests passed")
}
