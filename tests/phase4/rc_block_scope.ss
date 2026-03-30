// Test: Block-scoped RC release
// Variables declared inside blocks should be released at block exit

function testIfBlock() {
    let x = 1
    if (x == 1) {
        const s = "in if block"
        println(s)
        // s released at block exit
    }
    println("after if")
}

function testForLoop() {
    const items = "a,b,c".split(",")
    for (item in items) {
        const msg = `item: ${item}`
        println(msg)
        // msg released each iteration
    }
    println("after for")
}

function testNestedBlocks() {
    let x = 1
    if (x == 1) {
        const outer = "outer"
        if (x == 1) {
            const inner = "inner"
            println(inner)
            // inner released here
        }
        println(outer)
        // outer released here
    }
    println("nested ok")
}

function findValue(target: string): string {
    const items = "apple,banana,cherry".split(",")
    for (item in items) {
        if (item == target) {
            const result = `found: ${item}`
            return result  // block vars + local vars released before return
        }
    }
    return "not found"
}

function testReturnInBlock() {
    println(findValue("banana"))
    println(findValue("grape"))
}

function testBreakInLoop() {
    const items = "x,y,z".split(",")
    let found = ""
    for (item in items) {
        const check = `checking ${item}`
        println(check)
        if (item == "y") {
            break  // block vars released before break
        }
    }
    println("break ok")
}

function testWhileBlock() {
    let i = 0
    while (i < 3) {
        const msg = `while: ${i}`
        println(msg)
        i = i + 1
        // msg released each iteration
    }
    println("while ok")
}

function main() {
    testIfBlock()
    testForLoop()
    testNestedBlocks()
    testReturnInBlock()
    testBreakInLoop()
    testWhileBlock()
    println("all block scope ok")
}
