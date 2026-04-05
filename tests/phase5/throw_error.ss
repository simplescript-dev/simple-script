// Test: throw Error class instances

class IOError extends Error {
    path: string
}

function main() {
    // Test 1: throw new Error, catch gets message string (backward compatible)
    let caught = ""
    try {
        throw(new Error("bad thing"))
    } catch (e) {
        caught = e
    }
    if (caught != "bad thing") { exit(1) }

    // Test 2: throw new IOError, catch gets message string
    caught = ""
    try {
        throw(new IOError("not found", "/data.txt"))
    } catch (e) {
        caught = e
    }
    if (caught != "not found") { exit(1) }

    // Test 3: throw string still works (backward compatible)
    caught = ""
    try {
        throw("plain string error")
    } catch (e) {
        caught = e
    }
    if (caught != "plain string error") { exit(1) }

    // Test 4: throw Error in try-finally
    caught = ""
    let finalized = 0
    try {
        throw(new Error("oops"))
    } catch (e) {
        caught = e
    } finally {
        finalized = 1
    }
    if (caught != "oops") { exit(1) }
    if (finalized != 1) { exit(1) }

    println("throw_error: all tests passed")
}
