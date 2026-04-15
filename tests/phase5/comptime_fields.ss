// D088 Phase 5: comptime obj.fields() + p[name] bracket access, symmetric with runtime.

import { assertEqual } from "@/lib/test"

comptime {
    class Point { x: int; y: int }

    // Named pointStr, not toString — toString is a comptime built-in intercept.
    function pointStr(p: Point): string {
        let parts = ""
        for (name in p.fields()) {
            if (parts != "") { parts = parts + ", " }
            parts = parts + name + "=" + p[name]
        }
        return "Point(" + parts + ")"
    }

    const p = new Point(x: 10, y: 20)
    const s = pointStr(p)
    if (s != "Point(x=10, y=20)") {
        compileError("comptime pointStr(Point) mismatch: " + s)
    }

    // fields() returns a real comptime array — length() / element access work
    const names = p.fields()
    if (names.length() != 2) {
        compileError("expected 2 fields, got " + names.length())
    }
    if (names[0] != "x") { compileError("names[0] != x") }
    if (names[1] != "y") { compileError("names[1] != y") }
}

// Inheritance: child's fields() includes parent's fields
comptime {
    class Base { id: int }
    class Child extends Base { name: string }

    const c = new Child(id: 1, name: "a")
    const cf = c.fields()
    if (cf.length() != 2) { compileError("child fields length != 2") }
    if (cf[0] != "id") { compileError("child[0] != id") }
    if (cf[1] != "name") { compileError("child[1] != name") }
}

function main() {
    test("comptime fields() synthetic method", () => {
        assertEqual(1, 1)
    })
}
