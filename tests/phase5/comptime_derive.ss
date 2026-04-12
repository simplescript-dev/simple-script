// Test: @derive annotation — automatic comptime method generation

import { assertEqual } from "@/lib/test"
import { } from "@/lib/comptime"

@derive("ToJson")
class Product {
    name: string
    price: double
    inStock: int
}

@derive("ToString")
class Point {
    x: int
    y: int
}

@derive("ToJson,ToString")
class User {
    name: string
    age: int
}

function main() {
    test("derive ToJson on Product", () => {
        const p = new Product(name: "Widget", price: 9.99, inStock: 1)
        assertEqual(p.toJson(), "{\"name\":\"Widget\",\"price\":9.99,\"inStock\":1}")
    })
    test("derive ToString on Point", () => {
        const p = new Point(x: 3, y: 4)
        assertEqual(p.toString(), "Point(x=3, y=4)")
    })
    test("derive ToJson on User", () => {
        const u = new User(name: "Alice", age: 30)
        assertEqual(u.toJson(), "{\"name\":\"Alice\",\"age\":30}")
    })
    test("derive ToString on User", () => {
        const u = new User(name: "Bob", age: 25)
        assertEqual(u.toString(), "User(name=Bob, age=25)")
    })
}
