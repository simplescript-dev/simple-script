// Test: abstract classes and methods (D071)
// Abstract = compile-time contract. Prevents instantiation, enforces implementation.

abstract class Shape {
    name: string

    abstract function area(): double
    abstract function perimeter(): double
}

class Circle extends Shape {
    radius: double

    function area(): double {
        return 3.14159 * this.radius * this.radius
    }

    function perimeter(): double {
        return 2.0 * 3.14159 * this.radius
    }
}

class Rectangle extends Shape {
    width: double
    height: double

    function area(): double {
        return this.width * this.height
    }

    function perimeter(): double {
        return 2.0 * (this.width + this.height)
    }
}

// Abstract class extending another abstract class (partial implementation)
abstract class RegularPolygon extends Shape {
    sides: int
    sideLength: double

    function perimeter(): double {
        return this.sideLength * this.sides
    }
}

class Square extends RegularPolygon {
    function area(): double {
        return this.sideLength * this.sideLength
    }
}

// Abstract with concrete methods (non-polymorphic — static dispatch)
abstract class Base {
    value: int

    abstract function transform(): int

    function getValue(): int {
        return this.value
    }
}

class Doubler extends Base {
    function transform(): int {
        return this.value * 2
    }
}

// Abstract with protected method
abstract class Animal {
    name: string

    abstract function speak(): string
}

class Dog extends Animal {
    function speak(): string {
        return `${this.name} says Woof!`
    }
}

function main() {
    // Circle: concrete subclass of abstract Shape
    const c = new Circle(name: "circle", radius: 5.0)
    if (c.area() < 78.0 || c.area() > 79.0) { exit(1) }
    if (c.perimeter() < 31.0 || c.perimeter() > 32.0) { exit(1) }

    // Rectangle
    const r = new Rectangle(name: "rect", width: 4.0, height: 6.0)
    if (r.area() != 24.0) { exit(1) }
    if (r.perimeter() != 20.0) { exit(1) }

    // Chain: Square -> RegularPolygon (abstract) -> Shape (abstract)
    const sq = new Square(name: "square", sides: 4, sideLength: 3.0)
    if (sq.area() != 9.0) { exit(1) }
    if (sq.perimeter() != 12.0) { exit(1) }

    // Concrete method from abstract class (static dispatch)
    const d = new Doubler(value: 21)
    if (d.getValue() != 21) { exit(1) }
    if (d.transform() != 42) { exit(1) }

    // Dog
    const dog = new Dog(name: "Rex")
    if (dog.speak() != "Rex says Woof!") { exit(1) }
}
