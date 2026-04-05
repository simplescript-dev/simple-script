// Test: instanceof with Error class hierarchy

class IOError extends Error {
    path: string
}

class ParseError extends Error {
    line: int
}

function main() {
    const ioErr = new IOError(message: "file not found", path: "/tmp/x")
    const parseErr = new ParseError(message: "syntax error", line: 42)

    // Direct type
    if (!(ioErr instanceof IOError)) { exit(1) }
    if (!(parseErr instanceof ParseError)) { exit(2) }

    // Inheritance — both are Error
    if (!(ioErr instanceof Error)) { exit(3) }
    if (!(parseErr instanceof Error)) { exit(4) }

    // Cross check
    if (ioErr instanceof ParseError) { exit(5) }
    if (parseErr instanceof IOError) { exit(6) }

    // Use in if-else branching
    let result = 0
    if (ioErr instanceof Error) {
        result = 1
    }
    if (result != 1) { exit(7) }
}
