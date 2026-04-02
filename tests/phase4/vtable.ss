// Test: vtable virtual method dispatch (true polymorphism)

class Shape {
    kind: string

    function area(): int {
        return 0
    }
    function describe(): string {
        return this.kind
    }
}

class Circle extends Shape {
    radius: int

    function area(): int {
        return this.radius * this.radius * 3
    }
}

class Rect extends Shape {
    width: int
    height: int

    function area(): int {
        return this.width * this.height
    }
}

function printArea(s: Shape) {
    println(s.describe())
    println(s.area())
}

function main() {
    const c = new Circle("circle", 5)
    const r = new Rect("rect", 4, 6)

    // Direct calls
    println(c.area())
    println(r.area())

    // Polymorphic dispatch through base type
    printArea(c)
    printArea(r)
}
