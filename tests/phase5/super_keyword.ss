// Test: super.method() calls parent class method

class Animal {
    name: string
    sound: string

    function speak(): string {
        return `${this.name} says ${this.sound}`
    }

    function type(): string {
        return "Animal"
    }
}

class Dog extends Animal {
    breed: string

    override function speak(): string {
        // Call parent's speak and extend it
        const base = super.speak()
        return `${base} (${this.breed})`
    }

    override function type(): string {
        return `Dog:${super.type()}`
    }
}

// Test multi-level: super walks one level up only
class Puppy extends Dog {
    override function speak(): string {
        // super.speak() calls Dog.speak(), not Animal.speak()
        return `Little ${super.speak()}`
    }

    override function type(): string {
        return `Puppy:${super.type()}`
    }
}

// Test super with void return
class Base {
    value: int

    function reset() {
        this.value = 0
    }

    function addAmount(n: int) {
        this.value += n
    }
}

class Derived extends Base {
    override function reset() {
        super.reset()
        this.value = 42
    }

    override function addAmount(n: int) {
        super.addAmount(n * 2)
    }
}

// Test super with protected method
class Shape {
    x: int

    protected function computeArea(): int {
        return 0
    }

    function getArea(): int {
        return this.computeArea()
    }
}

class Square extends Shape {
    side: int

    protected function computeArea(): int {
        return this.side * this.side
    }

    function getFullArea(): int {
        // Can call super's protected method
        const baseArea = super.computeArea()
        return baseArea + this.side * this.side
    }
}

function main() {
    // Test 1: Basic super.method() call
    let dog = new Dog(name: "Rex", sound: "Woof", breed: "Lab")
    const result = dog.speak()
    if (result != "Rex says Woof (Lab)") {
        println("FAIL: basic super.method()")
        exit(1)
    }

    // Test 2: super in return expression
    const t = dog.type()
    if (t != "Dog:Animal") {
        println(`FAIL: super in return, got '${t}'`)
        exit(1)
    }

    // Test 3: Multi-level inheritance
    let puppy = new Puppy(name: "Tiny", sound: "Yip", breed: "Poodle")
    const pResult = puppy.speak()
    if (pResult != "Little Tiny says Yip (Poodle)") {
        println(`FAIL: multi-level super, got '${pResult}'`)
        exit(1)
    }

    // Test 4: Multi-level type chain
    const pt = puppy.type()
    if (pt != "Puppy:Dog:Animal") {
        println(`FAIL: multi-level type, got '${pt}'`)
        exit(1)
    }

    // Test 5: Super with void method
    let d = new Derived(value: 10)
    d.reset()
    if (d.value != 42) {
        println(`FAIL: super void, got ${d.value}`)
        exit(1)
    }

    // Test 6: Super with args
    let d2 = new Derived(value: 0)
    d2.addAmount(5)
    if (d2.value != 10) {
        println(`FAIL: super with args, got ${d2.value}`)
        exit(1)
    }

    // Test 7: Super with protected method
    let sq = new Square(x: 0, side: 5)
    const fullArea = sq.getFullArea()
    if (fullArea != 25) {
        println(`FAIL: super protected, got ${fullArea}`)
        exit(1)
    }

    println("All super keyword tests passed")
}
