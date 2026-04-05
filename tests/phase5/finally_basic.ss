// Test: finally block — basic behavior

function test1(): string {
    let trace = ""
    try {
        trace = trace + "T"
    } catch (e) {
        trace = trace + "C"
    } finally {
        trace = trace + "F"
    }
    return trace
}

function test2(): string {
    let trace = ""
    try {
        trace = trace + "T"
        throw("err")
    } catch (e) {
        trace = trace + "C"
    } finally {
        trace = trace + "F"
    }
    return trace
}

function test3(): string {
    let trace = ""
    try {
        trace = trace + "T"
    } finally {
        trace = trace + "F"
    }
    return trace
}

function test4(): string {
    let trace = ""
    try {
        try {
            trace = trace + "T"
            throw("err")
        } finally {
            trace = trace + "F"
        }
    } catch (e) {
        trace = trace + "C"
    }
    return trace
}

function test5(): string {
    let caught = ""
    try {
        throw("hello")
    } catch (e) {
        caught = e
    } finally {
        caught = caught + "!"
    }
    return caught
}

function main() {
    if (test1() != "TF") { exit(1) }
    if (test2() != "TCF") { exit(1) }
    if (test3() != "TF") { exit(1) }
    if (test4() != "TFC") { exit(1) }
    if (test5() != "hello!") { exit(1) }
    println("finally_basic: all tests passed")
}
