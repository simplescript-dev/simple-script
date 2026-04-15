// Test: @derive("Copy") and @derive("With") — immutable builder pattern

import { assertEqual } from "@/lib/test"
import { } from "@/lib/comptime"

// ── Copy derive ──

@derive("Copy")
class Point {
    x: int
    y: int
}

// ── With derive ──

@derive("With")
class Config {
    host: string
    port: int
    debug: int
}

// ── Combined: Copy + With + Equals ──

@derive("Copy,With,Equals")
class User {
    name: string
    age: int
}

function main() {
    // Copy derive
    test("derive Copy — creates independent copy", () => {
        const p = new Point(x: 10, y: 20)
        const q = p.copy()
        assertEqual(q.x, 10)
        assertEqual(q.y, 20)
    })
    test("derive Copy — original unchanged after copy mutation", () => {
        let p = new Point(x: 5, y: 15)
        let q = p.copy()
        q.x = 99
        assertEqual(p.x, 5)
        assertEqual(q.x, 99)
    })

    // With derive
    test("derive With — withHost", () => {
        const c = new Config(host: "localhost", port: 8080, debug: 0)
        const c2 = c.withHost("example.com")
        assertEqual(c2.host, "example.com")
        assertEqual(c2.port, 8080)
        assertEqual(c2.debug, 0)
    })
    test("derive With — withPort", () => {
        const c = new Config(host: "localhost", port: 8080, debug: 0)
        const c2 = c.withPort(3000)
        assertEqual(c2.host, "localhost")
        assertEqual(c2.port, 3000)
    })
    test("derive With — withDebug", () => {
        const c = new Config(host: "localhost", port: 8080, debug: 0)
        const c2 = c.withDebug(1)
        assertEqual(c2.debug, 1)
        assertEqual(c2.host, "localhost")
    })
    test("derive With — chaining", () => {
        const c = new Config(host: "localhost", port: 8080, debug: 0)
        const c2 = c.withHost("prod.example.com").withPort(443).withDebug(0)
        assertEqual(c2.host, "prod.example.com")
        assertEqual(c2.port, 443)
        assertEqual(c2.debug, 0)
    })
    test("derive With — original immutable", () => {
        const c = new Config(host: "localhost", port: 8080, debug: 0)
        const c2 = c.withPort(9090)
        assertEqual(c.port, 8080)
        assertEqual(c2.port, 9090)
    })

    // Combined: Copy + With + Equals
    test("derive combined — copy preserves equality", () => {
        const u = new User(name: "Alice", age: 30)
        const u2 = u.copy()
        assertEqual(u.equals(u2), 1)
    })
    test("derive combined — with breaks equality", () => {
        const u = new User(name: "Alice", age: 30)
        const u2 = u.withAge(31)
        assertEqual(u.equals(u2), 0)
    })
    test("derive combined — with + copy chain", () => {
        const u = new User(name: "Alice", age: 30)
        const u2 = u.withName("Bob").copy()
        assertEqual(u2.name, "Bob")
        assertEqual(u2.age, 30)
    })
}
