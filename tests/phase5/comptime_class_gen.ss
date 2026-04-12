// Test: comptime class generation — @comptimeEmit generates entire class definitions

import { assertEqual } from "@/lib/test"

// Generate a simple DTO class at compile time
comptime {
    const fields = "x: int\n    y: int\n    z: int"
    @comptimeEmit(`
class Vector3 {
    ${fields}
}
`)
}

// Generate a class with string fields (needs RC/dtor)
comptime {
    @comptimeEmit(`
class Pair {
    first: string
    second: string
}
`)
}

// Generate a class with a method
comptime {
    @comptimeEmit(`
class Greeting {
    message: string

    function greet(name: string): string {
        return this.message + ", " + name + "!"
    }
}
`)
}

function main() {
    test("comptime generated class — int fields", () => {
        const v = new Vector3(x: 1, y: 2, z: 3)
        assertEqual(v.x + v.y + v.z, 6)
    })
    test("comptime generated class — string fields (RC)", () => {
        const p = new Pair(first: "hello", second: "world")
        assertEqual(p.first, "hello")
        assertEqual(p.second, "world")
    })
    test("comptime generated class — with method", () => {
        const g = new Greeting(message: "Hello")
        assertEqual(g.greet("SimpleScript"), "Hello, SimpleScript!")
    })
    test("comptime generated class — field mutation", () => {
        let v = new Vector3(x: 10, y: 20, z: 30)
        v.x = 100
        assertEqual(v.x, 100)
        assertEqual(v.y, 20)
    })
}
