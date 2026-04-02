// Test: class body field declarations (D061 — TS/Java-style)

// Basic class with body fields
class Point {
    x: int
    y: int
}

// Class with const field
class Config {
    const name: string
    value: int
}

// Class with methods
class Counter {
    count: int

    function increment() {
        this.count += 1
    }

    function getCount(): int {
        return this.count
    }
}

// Inheritance with body fields
class Point3D extends Point {
    z: int
}

// Class with optional field
class Profile {
    name: string
    age?: int
}

function main() {
    // Basic fields
    const p = new Point(3, 4)
    if (p.x != 3) { exit(1) }
    if (p.y != 4) { exit(1) }

    // Const field
    const cfg = new Config("test", 42)
    if (cfg.name != "test") { exit(1) }
    if (cfg.value != 42) { exit(1) }
    cfg.value = 99
    if (cfg.value != 99) { exit(1) }

    // Methods
    let ctr = new Counter(0)
    ctr.increment()
    ctr.increment()
    if (ctr.getCount() != 2) { exit(1) }

    // Inheritance
    const p3 = new Point3D(1, 2, 3)
    if (p3.x != 1) { exit(1) }
    if (p3.y != 2) { exit(1) }
    if (p3.z != 3) { exit(1) }

    // Optional field
    const prof = new Profile("Alice")
    if (prof.name != "Alice") { exit(1) }

    println("class_body_fields: all passed")
}
