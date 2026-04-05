// Test: typed catch — Java-style multi-catch with type matching

class IOError extends Error {
    path: string
}

class ParseError extends Error {
    line: int
}

function throwIO() {
    throw(new IOError("file not found", "/data.txt"))
}

function throwParse() {
    throw(new ParseError("unexpected token", 42))
}

function throwString() {
    throw("plain string")
}

function main() {
    // Test 1: typed catch matches specific error type
    let result = ""
    try {
        throwIO()
    } catch (e: IOError) {
        result = e.path
    } catch (e: Error) {
        result = "wrong"
    }
    if (result != "/data.txt") { exit(1) }

    // Test 2: typed catch falls through to parent type
    result = ""
    try {
        throwParse()
    } catch (e: IOError) {
        result = "wrong"
    } catch (e: Error) {
        result = e.message
    }
    if (result != "unexpected token") { exit(1) }

    // Test 3: untyped catch as fallback
    result = ""
    try {
        throwString()
    } catch (e: IOError) {
        result = "wrong"
    } catch (e) {
        result = e
    }
    if (result != "plain string") { exit(1) }

    // Test 4: typed catch with inheritance — IOError is-a Error
    result = ""
    try {
        throwIO()
    } catch (e: Error) {
        result = e.message
    }
    if (result != "file not found") { exit(1) }

    // Test 5: typed catch with finally
    result = ""
    let finalized = 0
    try {
        throwIO()
    } catch (e: IOError) {
        result = e.path
    } finally {
        finalized = 1
    }
    if (result != "/data.txt") { exit(1) }
    if (finalized != 1) { exit(1) }

    // Test 6: typed catch — ParseError has extra field
    let lineNum = 0
    try {
        throwParse()
    } catch (e: ParseError) {
        lineNum = e.line
    }
    if (lineNum != 42) { exit(1) }

    println("typed_catch: all tests passed")
}
