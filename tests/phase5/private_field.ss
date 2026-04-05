// Test: private fields and methods — access within class works
class Account {
    const name: string
    private balance: int

    function getBalance(): int {
        return this.balance
    }

    function deposit(amount: int) {
        this.balance = this.balance + amount
    }

    private function log(msg: string) {
        // internal logging
    }

    function transfer(other: Account, amount: int) {
        this.balance = this.balance - amount
        other.balance = other.balance + amount
        this.log("transferred")
    }
}

function main() {
    let a = new Account("Alice", 100)
    let b = new Account("Bob", 50)
    // Public field access
    if (a.name != "Alice") { exit(1) }
    // Public method access
    if (a.getBalance() != 100) { exit(1) }
    a.deposit(20)
    if (a.getBalance() != 120) { exit(1) }
    // Same-class private access (transfer accesses other.balance)
    a.transfer(b, 30)
    if (a.getBalance() != 90) { exit(1) }
    if (b.getBalance() != 80) { exit(1) }
    println("private_field: all passed")
}
