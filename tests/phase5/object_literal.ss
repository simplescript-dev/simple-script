// D084: Object literal syntax - { key: value } as class constructor sugar
import { assertEqual } from "@/lib/test"

class Point {
    x: int
    y: int
}

class Config {
    name: string
    debug: bool
    count: int
}

function createPoint(): Point {
    const p: Point = { x: 42, y: 84 }
    return p
}

function main() {
    test("basic object literal", () => {
        const p: Point = { x: 10, y: 20 }
        assertEqual(p.x, 10)
        assertEqual(p.y, 20)
    })

    test("object literal with multiple types", () => {
        const c: Config = { name: "test", debug: true, count: 42 }
        assertEqual(c.name, "test")
        assertEqual(c.debug, true)
        assertEqual(c.count, 42)
    })

    test("object literal with let and mutation", () => {
        let p: Point = { x: 1, y: 2 }
        assertEqual(p.x, 1)
        p.x = 99
        assertEqual(p.x, 99)
    })

    test("object literal in function scope", () => {
        const p = createPoint()
        assertEqual(p.x, 42)
        assertEqual(p.y, 84)
    })
}
