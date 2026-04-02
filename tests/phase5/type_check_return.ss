// Type checking: verify return type consistency.
// Tests that functions with declared return types compile when returning compatible values.

class Point(x: int, y: int)

class Point3D extends Point(z: int)

// Basic return types
function getInt(): int {
    return 42
}

function getString(): string {
    return "hello"
}

function getDouble(): double {
    return 3.14
}

// int -> double widening in return
function intToDouble(): double {
    return 10
}

// Return class instance
function createPoint(): Point {
    return new Point(1, 2)
}

// Return subclass from parent type (inheritance compatibility)
function createAnimal(): Point {
    return new Point3D(1, 2, 3)
}

// Return from conditionals
function conditionalReturn(x: int): string {
    if (x > 0) {
        return "positive"
    }
    return "non-positive"
}

// Return from method call chain
function getLength(s: string): int {
    return s.length()
}

// Return expression result
function compute(a: int, b: int): int {
    return a + b * 2
}

// Return string from template literal
function formatName(name: string): string {
    return `Hello, ${name}!`
}

// Return bool (int in SS)
function isPositive(x: int): int {
    return x > 0
}

// Method return type
class Calculator(value: int) {
    function getValue(): int {
        return this.value
    }

    function getLabel(): string {
        return "calculator"
    }

    function doubled(): int {
        return this.value * 2
    }
}

function main() {
    if (getInt() != 42) { exit(1) }
    if (getString() != "hello") { exit(1) }
    if (getDouble() != 3.14) { exit(1) }
    if (intToDouble() != 10.0) { exit(1) }

    const p = createPoint()
    if (p.x != 1) { exit(1) }

    const a = createAnimal()
    if (a.x != 1) { exit(1) }

    if (conditionalReturn(5) != "positive") { exit(1) }
    if (conditionalReturn(-1) != "non-positive") { exit(1) }

    if (getLength("abc") != 3) { exit(1) }
    if (compute(3, 4) != 11) { exit(1) }
    if (formatName("Alice") != "Hello, Alice!") { exit(1) }
    if (isPositive(5) != 1) { exit(1) }

    const calc = new Calculator(10)
    if (calc.getValue() != 10) { exit(1) }
    if (calc.getLabel() != "calculator") { exit(1) }
    if (calc.doubled() != 20) { exit(1) }

    println("type_check_return: all passed")
}
