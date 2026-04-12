// Test: @derive custom handlers — built-in Equals + user-defined derive

import { assertEqual } from "@/lib/test"
import { } from "@/lib/comptime"

// ── User-defined custom derive handler ──
comptime {
    function ctDeriveDebug(className: string) {
        const info = getTypeInfo(className)
        let body = "    let r = \"" + className + " { \"\n"
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { body = body + "    r = r + \", \"\n" }
            if (f.type == "string") {
                body = body + "    r = r + \"" + f.name + ": \\\"\" + this." + f.name + " + \"\\\"\"\n"
            } else {
                body = body + "    r = r + \"" + f.name + ": \" + this." + f.name + "\n"
            }
            i = i + 1
        }
        body = body + "    return r + \" }\""
        @comptimeEmit("function debug(): string {\n" + body + "\n}")
    }
}

// ── Built-in @derive("Equals") ──

@derive("Equals")
class Point {
    x: int
    y: int
}

@derive("Equals,ToString")
class User {
    name: string
    age: int
}

// ── User-defined @derive("Debug") ──

@derive("Debug")
class Config {
    host: string
    port: int
    debug: int
}

// ── Combined: built-in + user-defined ──

@derive("Equals,Debug")
class Item {
    name: string
    quantity: int
}

function main() {
    // Built-in Equals derive
    test("derive Equals — same values", () => {
        const a = new Point(x: 3, y: 4)
        const b = new Point(x: 3, y: 4)
        assertEqual(a.equals(b), 1)
    })
    test("derive Equals — different values", () => {
        const a = new Point(x: 3, y: 4)
        const b = new Point(x: 5, y: 6)
        assertEqual(a.equals(b), 0)
    })
    test("derive Equals — partial difference", () => {
        const a = new Point(x: 3, y: 4)
        const b = new Point(x: 3, y: 99)
        assertEqual(a.equals(b), 0)
    })
    test("derive Equals with strings", () => {
        const a = new User(name: "Alice", age: 30)
        const b = new User(name: "Alice", age: 30)
        assertEqual(a.equals(b), 1)
    })
    test("derive Equals — string mismatch", () => {
        const a = new User(name: "Alice", age: 30)
        const b = new User(name: "Bob", age: 30)
        assertEqual(a.equals(b), 0)
    })
    test("derive Equals + ToString combined", () => {
        const u = new User(name: "Eve", age: 25)
        assertEqual(u.toString(), "User(name=Eve, age=25)")
    })

    // User-defined Debug derive
    test("custom derive Debug", () => {
        const c = new Config(host: "localhost", port: 8080, debug: 1)
        assertEqual(c.debug(), "Config { host: \"localhost\", port: 8080, debug: 1 }")
    })

    // Combined built-in + user-defined
    test("combined Equals + Debug", () => {
        const a = new Item(name: "sword", quantity: 3)
        const b = new Item(name: "sword", quantity: 3)
        assertEqual(a.equals(b), 1)
        assertEqual(a.debug(), "Item { name: \"sword\", quantity: 3 }")
    })
    test("combined — not equal", () => {
        const a = new Item(name: "sword", quantity: 3)
        const b = new Item(name: "shield", quantity: 1)
        assertEqual(a.equals(b), 0)
    })
}
