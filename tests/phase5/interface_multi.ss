interface Shape {
    function area(): int
    function name(): string
}

class Circle : Shape {
    r: int

    function area(): int {
        return this.r * this.r * 3
    }
    function name(): string {
        return "circle"
    }
}

class Rect : Shape {
    w: int
    h: int

    function area(): int {
        return this.w * this.h
    }
    function name(): string {
        return "rect"
    }
}

function printShape(s: Shape) {
    println(`${s.name()}: area=${s.area()}`)
}

function main() {
    printShape(new Circle(5))
    printShape(new Rect(4, 6))
    // Interface-typed variable
    let s: Shape = new Circle(10)
    println(s.area())
    s = new Rect(3, 7)
    println(s.area())
}
