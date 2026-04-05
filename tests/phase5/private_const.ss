// Test: private const field — both private and immutable
class Token {
    private const secret: string
    name: string

    function verify(key: string): int {
        if (this.secret == key) { return 1 }
        return 0
    }
}

function main() {
    let t = new Token("abc123", "session")
    if (t.name != "session") { exit(1) }
    if (t.verify("abc123") != 1) { exit(1) }
    if (t.verify("wrong") != 0) { exit(1) }
    println("private_const: all passed")
}
