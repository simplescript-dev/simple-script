// Test: D067 null safety Phase 2 — smart narrowing

class User {
    name: string
    age: int
}

function findUser(id: int): User? {
    if (id <= 0) { return null }
    return new User("Alice", 30)
}

function greet(user: User): string {
    return user.name
}

// Test 1: if (x != null) narrows in then-branch
function testNotNull() {
    let u: User? = findUser(1)
    if (u != null) {
        const name = greet(u)
        println(`test1: ${name}`)
    }
}

// Test 2: if (x == null) { return } narrows after if
function testEarlyReturn() {
    let u: User? = findUser(1)
    if (u == null) { return }
    const name = greet(u)
    println(`test2: ${name}`)
}

// Test 3: if (x == null) { ... } else { narrow in else }
function testElseNarrowing() {
    let u: User? = findUser(1)
    if (u == null) {
        println("test3: null")
        return
    } else {
        const name = greet(u)
        println(`test3: ${name}`)
    }
}

// Test 4: null == x (reversed operand order)
function testReversedNull() {
    let u: User? = findUser(1)
    if (null != u) {
        const name = greet(u)
        println(`test4: ${name}`)
    }
}

// Test 5: nested null narrowing
function testNested() {
    let u: User? = findUser(1)
    let v: User? = findUser(2)
    if (u != null) {
        if (v != null) {
            println(`test5: ${greet(u)} ${greet(v)}`)
        }
    }
}

// Test 6: early exit chain (multiple guards)
function testEarlyExitChain() {
    let u: User? = findUser(1)
    let v: User? = findUser(2)
    if (u == null) { return }
    if (v == null) { return }
    println(`test6: ${greet(u)} ${greet(v)}`)
}

// Test 7: narrowed variable in let assignment
function testNarrowedLet() {
    let u: User? = findUser(1)
    if (u != null) {
        let v: User = u
        println(`test7: ${v.name}`)
    }
}

// Test 8: narrowed variable in return statement
function returnUser(u: User?): User {
    if (u == null) { return new User("default", 0) }
    return u
}

function testNarrowedReturn() {
    const result = returnUser(findUser(1))
    println(`test8: ${result.name}`)
}

// Test 9: early exit with throw
function testEarlyThrow() {
    let u: User? = findUser(1)
    if (u == null) { throw("null user") }
    const name = greet(u)
    println(`test9: ${name}`)
}

// Test 10: if (x != null) { ... } else { return } narrows after
function testElseReturn() {
    let u: User? = findUser(1)
    if (u != null) {
        println(`test10 then: ${greet(u)}`)
    } else {
        return
    }
    println(`test10 after: ${greet(u)}`)
}

// Test 11: early exit with else-if
function testEarlyExitElseIf() {
    let u: User? = findUser(1)
    if (u == null) {
        return
    } else {
        println(`test11: ${greet(u)}`)
    }
    println(`test11 post: ${greet(u)}`)
}

function main() {
    testNotNull()
    testEarlyReturn()
    testElseNarrowing()
    testReversedNull()
    testNested()
    testEarlyExitChain()
    testNarrowedLet()
    testNarrowedReturn()
    testEarlyThrow()
    testElseReturn()
    testEarlyExitElseIf()
    println("null_narrowing: all passed")
}
