// Test: D088 Phase 5 — obj.fields() + obj[name] + compile-time for-in unrolling
//
// Demonstrates:
//   1. obj.fields() returns field name array
//   2. obj[name] bracket notation resolves to field access (compile-time constant)
//   3. for-in over obj.fields() is compile-time unrolled (no loop in IR)

import { assertEqual } from "@/lib/test"

class Point {
    x: int
    y: int
}

class Person {
    name: string
    age: int
}

// Generic describe using fields() + bracket notation
function describePoint(p: Point): string {
    let parts = ""
    for (name in p.fields()) {
        if (parts != "") { parts = parts + ", " }
        parts = parts + name + "=" + p[name]
    }
    return "Point(" + parts + ")"
}

function describePerson(person: Person): string {
    let parts = ""
    for (name in person.fields()) {
        if (parts != "") { parts = parts + ", " }
        parts = parts + name + "=" + person[name]
    }
    return "Person(" + parts + ")"
}

// Test standalone fields() usage (returns runtime array)
function fieldCount(p: Point): int {
    const names = p.fields()
    return names.length()
}

// Test string literal bracket access
function getX(p: Point): int {
    return p["x"]
}

function main() {
    test("fields + bracket — Point describe", () => {
        const p = new Point(x: 10, y: 20)
        assertEqual(describePoint(p), "Point(x=10, y=20)")
    })

    test("fields + bracket — Person describe (mixed types)", () => {
        const person = new Person(name: "Alice", age: 30)
        assertEqual(describePerson(person), "Person(name=Alice, age=30)")
    })

    test("fields() standalone — returns field name array", () => {
        const p = new Point(x: 1, y: 2)
        assertEqual(fieldCount(p), 2)
    })

    test("bracket notation — string literal index", () => {
        const p = new Point(x: 42, y: 99)
        assertEqual(getX(p), 42)
    })
}
