// Test: @derive(Hash), @derive(Comparable), and ctForEachField helper
//
// Demonstrates:
//   1. @derive("Hash") — generates hashCode(): int (Java-style polynomial hash)
//   2. @derive("Comparable") — generates compareTo(other): int (field-by-field ordering)
//   3. ctForEachField — template expansion per field with $name/$type placeholders

import { assertEqual, assertTrue } from "@/lib/test"
import { } from "@/lib/comptime"

// ── Test classes ──

@derive("Hash,Equals")
class Point {
    x: int
    y: int
}

@derive("Hash,Comparable")
class Person {
    name: string
    age: int
}

@derive("Comparable")
class Version {
    major: int
    minor: int
    patch: int
}

// ── ctForEachField test ──

comptime {
    const fieldList = ctForEachField("Point", "$name:$type", ", ")
    const personFields = ctForEachField("Person", "$name", ",")

    @comptimeEmit(`
function pointFieldSummary(): string { return "${fieldList}" }
function personFieldList(): string { return "${personFields}" }
`)
}

function main() {
    // ── Hash: consistency ──
    test("derive Hash — same values produce same hash", () => {
        const p1 = new Point(x: 10, y: 20)
        const p2 = new Point(x: 10, y: 20)
        assertEqual(p1.hashCode(), p2.hashCode())
    })

    // ── Hash: different values ──
    test("derive Hash — different values produce different hash", () => {
        const p1 = new Point(x: 10, y: 20)
        const p2 = new Point(x: 20, y: 10)
        assertTrue(p1.hashCode() != p2.hashCode())
    })

    // ── Hash: non-negative ──
    test("derive Hash — result is non-negative", () => {
        const p = new Point(x: -100, y: -200)
        assertTrue(p.hashCode() >= 0)
    })

    // ── Hash: string fields affect hash ──
    test("derive Hash — string field lengths affect hash", () => {
        const a = new Person(name: "Alice", age: 30)
        const b = new Person(name: "Bob", age: 30)
        assertTrue(a.hashCode() != b.hashCode())
    })

    // ── Comparable: equal ──
    test("derive Comparable — equal objects return 0", () => {
        const a = new Person(name: "Alice", age: 30)
        const b = new Person(name: "Alice", age: 30)
        assertEqual(a.compareTo(b), 0)
    })

    // ── Comparable: less by first field ──
    test("derive Comparable — less by first string field", () => {
        const a = new Person(name: "Alice", age: 30)
        const b = new Person(name: "Bob", age: 30)
        assertEqual(a.compareTo(b), -1)
    })

    // ── Comparable: greater by first field ──
    test("derive Comparable — greater by first string field", () => {
        const a = new Person(name: "Bob", age: 30)
        const b = new Person(name: "Alice", age: 30)
        assertEqual(a.compareTo(b), 1)
    })

    // ── Comparable: falls through to second field ──
    test("derive Comparable — falls through to second field", () => {
        const a = new Person(name: "Alice", age: 25)
        const b = new Person(name: "Alice", age: 30)
        assertEqual(a.compareTo(b), -1)
    })

    // ── Comparable: three-field version ordering ──
    test("derive Comparable — patch version differs", () => {
        const v1 = new Version(major: 1, minor: 2, patch: 3)
        const v2 = new Version(major: 1, minor: 2, patch: 4)
        assertEqual(v1.compareTo(v2), -1)
    })

    test("derive Comparable — major version takes priority", () => {
        const v1 = new Version(major: 2, minor: 0, patch: 0)
        const v2 = new Version(major: 1, minor: 9, patch: 9)
        assertEqual(v1.compareTo(v2), 1)
    })

    // ── ctForEachField ──
    test("ctForEachField — Point field summary", () => {
        assertEqual(pointFieldSummary(), "x:int, y:int")
    })

    test("ctForEachField — Person field names", () => {
        assertEqual(personFieldList(), "name,age")
    })
}
