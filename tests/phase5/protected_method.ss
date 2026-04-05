// Test: protected methods — accessible within class and subclass
class Base {
    value: int

    protected function compute(): int {
        return this.value * 2
    }

    function getResult(): int {
        return this.compute()
    }
}

class Child extends Base {
    function childResult(): int {
        return this.compute() + 1
    }
}

class GrandChild extends Child {
    function grandResult(): int {
        return this.compute() + 100
    }
}

function main() {
    let b = new Base(5)
    // Protected method via public wrapper — OK
    if (b.getResult() != 10) { exit(1) }
    // Protected method from subclass — OK
    let c = new Child(7)
    if (c.childResult() != 15) { exit(1) }
    if (c.getResult() != 14) { exit(1) }
    // Protected method from grandchild — OK
    let g = new GrandChild(3)
    if (g.grandResult() != 106) { exit(1) }
    println("protected_method: all passed")
}
