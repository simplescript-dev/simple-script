// D152 Phase 3 — Ref / RowId / SQLXML interface dispatch test.
//
// Ref and RowId are pointer-like opaque handles into the database (REF
// to a typed-table row, ROWID to a physical row). SQLXML wraps an XML
// column value (stream variants are added in D152 §Phase 4 once
// lib/java/io.ss declares InputStream / Reader).
//
// See docs/3-decisions/D152-jdbc-type-class-foundation.md §Phase 3.

import { assertEqual } from "@/lib/test"
import { Ref, RowId, SQLXML } from "@/lib/java/sql"

class StubRef : Ref {
    typeName: string
    payload: string

    function getBaseTypeName(): string { return this.typeName }
    function getObject(): string { return this.payload }
    function setObject(value: string) { this.payload = value }
}

class StubRowId : RowId {
    raw: string

    function getBytes(): string { return this.raw }
    function toString(): string { return this.raw }
    function equals(other: RowId): int {
        if (this.raw == other.getBytes()) { return 1 }
        return 0
    }
    function hashCode(): int { return this.raw.length() }
}

class StubSQLXML : SQLXML {
    xml: string

    function getString(): string { return this.xml }
    function setString(value: string) { this.xml = value }
    function free() { this.xml = "" }
}

function main() {
    test("Ref accessors + setObject mutates payload", () => {
        const r = new StubRef("PERSON_TYPE", "{id:1}")
        assertEqual(r.getBaseTypeName(), "PERSON_TYPE")
        assertEqual(r.getObject(), "{id:1}")
        r.setObject("{id:2}")
        assertEqual(r.getObject(), "{id:2}")
    })

    test("RowId getBytes + toString round-trip", () => {
        const id = new StubRowId("AAAFd1AABAAAOhUAAA")
        assertEqual(id.getBytes(), "AAAFd1AABAAAOhUAAA")
        assertEqual(id.toString(), "AAAFd1AABAAAOhUAAA")
    })

    test("RowId equals + hashCode (length-based stub)", () => {
        const a = new StubRowId("XYZ")
        const b = new StubRowId("XYZ")
        const c = new StubRowId("Q")
        assertEqual(a.equals(b), 1)
        assertEqual(a.equals(c), 0)
        assertEqual(a.hashCode(), 3)
    })

    test("SQLXML getString + setString round-trip + free", () => {
        const x = new StubSQLXML("<root><child/></root>")
        assertEqual(x.getString(), "<root><child/></root>")
        x.setString("<empty/>")
        assertEqual(x.getString(), "<empty/>")
        x.free()
        assertEqual(x.getString(), "")
    })
}
