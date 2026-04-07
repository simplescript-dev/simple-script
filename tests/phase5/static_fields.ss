// D078: Static fields test

class Counter {
    static count: int = 0
    static name: string = "default"
    name: string

    function increment() {
        Counter.count += 1
    }
}

class Config {
    static const MAX_RETRIES: int = 3
    static debug: bool = false
}

class Tracker {
    private static total: int = 0

    static function getTotal(): int {
        return Tracker.total
    }

    static function add(n: int) {
        Tracker.total += n
    }
}

function main() {
    // Basic static field access
    if (Counter.count != 0) { exit(1) }
    if (Counter.name != "default") { exit(1) }

    // Static field assignment
    Counter.count = 10
    if (Counter.count != 10) { exit(1) }

    // Compound assignment
    Counter.count += 5
    if (Counter.count != 15) { exit(1) }

    Counter.count -= 3
    if (Counter.count != 12) { exit(1) }

    // String static field
    Counter.name = "updated"
    if (Counter.name != "updated") { exit(1) }

    // Static field modified from instance method
    let c = new Counter("test")
    c.increment()
    if (Counter.count != 13) { exit(1) }

    // Const static field (read only)
    if (Config.MAX_RETRIES != 3) { exit(1) }

    // Bool static field
    Config.debug = true
    if (Config.debug != true) { exit(1) }

    // Private static field via static method
    Tracker.add(10)
    Tracker.add(5)
    if (Tracker.getTotal() != 15) { exit(1) }

    // Static fields are class-level, not instance-level
    Counter.count = 100
    let c2 = new Counter("other")
    c2.increment()
    if (Counter.count != 101) { exit(1) }
}
