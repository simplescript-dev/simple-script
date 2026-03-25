function findUser(id: int): string {
    if (id == 1) {
        return "Alice"
    }
    if (id == 2) {
        return "Bob"
    }
    return ""
}

function main() {
    for (let i = 0; i < 4; i++) {
        const name = findUser(i)
        if (name == "") {
            println(`user ${i}: not found`)
        } else {
            println(`user ${i}: ${name}`)
        }
    }

    // String comparison
    const a = "hello"
    const b = "hello"
    const c = "world"
    if (a == b) {
        println("a == b: true")
    }
    if (a == c) {
        println("a == c: true")
    } else {
        println("a == c: false")
    }
}
