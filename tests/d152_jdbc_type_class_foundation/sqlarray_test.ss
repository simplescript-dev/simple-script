// D152 Phase 3 — SqlArray interface dispatch test.
//
// Renamed from JDBC `Array` to `SqlArray` because SS Array<T> is the
// built-in generic array type (`interface Array` would shadow the
// keyword). The Sql- prefix matches JPA driver bindings.
//
// JDBC Types int constants (java.sql.Types):
//   INTEGER = 4, VARCHAR = 12. getBaseType() returns one of these.
//
// See docs/3-decisions/D152-jdbc-type-class-foundation.md §Phase 3.

import { assertEqual } from "@/lib/test"
import { SqlArray } from "@/lib/java/sql"

const TYPES_INTEGER = 4
const TYPES_VARCHAR = 12

class StubIntArray : SqlArray {
    function getBaseType(): int { return TYPES_INTEGER }
    function getBaseTypeName(): string { return "INTEGER" }
    function getArray(): string { return "[1,2,3]" }
    function free() {}
}

class StubVarcharArray : SqlArray {
    function getBaseType(): int { return TYPES_VARCHAR }
    function getBaseTypeName(): string { return "VARCHAR" }
    function getArray(): string { return "[\"a\",\"b\",\"c\"]" }
    function free() {}
}

function main() {
    test("SqlArray INTEGER element type", () => {
        const a = new StubIntArray()
        assertEqual(a.getBaseType(), TYPES_INTEGER)
        assertEqual(a.getBaseTypeName(), "INTEGER")
        assertEqual(a.getArray(), "[1,2,3]")
    })

    test("SqlArray VARCHAR element type", () => {
        const a = new StubVarcharArray()
        assertEqual(a.getBaseType(), TYPES_VARCHAR)
        assertEqual(a.getBaseTypeName(), "VARCHAR")
        assertEqual(a.getArray(), "[\"a\",\"b\",\"c\"]")
    })
}
