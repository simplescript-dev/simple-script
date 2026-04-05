// Test: protected const field — both protected and immutable
class Config {
    protected const secret: string
    name: string

    function verify(key: string): int {
        if (this.secret == key) { return 1 }
        return 0
    }
}

class AppConfig extends Config {
    function checkSecret(key: string): int {
        if (this.secret == key) { return 1 }
        return 0
    }
}

function main() {
    let c = new AppConfig("abc123", "myapp")
    if (c.name != "myapp") { exit(1) }
    // Protected access via parent method — OK
    if (c.verify("abc123") != 1) { exit(1) }
    // Protected access via subclass method — OK
    if (c.checkSecret("abc123") != 1) { exit(1) }
    if (c.checkSecret("wrong") != 0) { exit(1) }
    println("protected_const: all passed")
}
