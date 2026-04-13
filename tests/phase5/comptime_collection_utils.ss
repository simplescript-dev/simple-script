// Test: comptime collection utilities
//
// Demonstrates:
//   1. ctMap — template expansion over comma-separated items ($item/$index)
//   2. ctRange — numeric sequence generation
//   3. ctLen — count items in comma-separated list
//   4. ctContains — membership check
//   5. ctZip — dual-list template expansion ($key/$value)
//   6. ctReplaceAll — replace all occurrences (safe: handles rep containing old)

import { assertEqual } from "@/lib/test"
import { } from "@/lib/comptime"

comptime {
    // ctMap tests
    const mapped = ctMap("GET,POST,PUT", "handle$item", ",")
    const indexed = ctMap("a,b,c", "$item[$index]", ", ")
    const emptyMap = ctMap("", "x$item", ",")
    const multiRef = ctMap("x,y", "$item+$item", ",")

    // ctRange tests
    const range5 = ctRange(0, 5)
    const range37 = ctRange(3, 7)
    const rangeEmpty = ctRange(5, 5)

    // ctLen tests
    const len3 = ctLen("a,b,c")
    const len0 = ctLen("")
    const len1 = ctLen("solo")

    // ctContains tests
    const hasB = ctContains("a,b,c", "b")
    const hasD = ctContains("a,b,c", "d")
    const emptyHas = ctContains("", "x")

    // ctZip tests
    const zipped = ctZip("x,y,z", "1,2,3", "$key=$value", ", ")
    const zipTypes = ctZip("name,age", "string,int", "$key: $value", "; ")
    const zipEmpty = ctZip("", "", "$key=$value", ",")
    const zipMulti = ctZip("a,b", "1,2", "$key->$value ($key)", ",")

    // ctReplaceAll tests
    const replaced = ctReplaceAll("a.b.c.d", ".", "-")
    const repSafe = ctReplaceAll("aXbXc", "X", "XX")

    // Practical pattern: generate dispatch table from lists
    const methods = "get,post,put,delete"
    const codes = "200,201,200,204"
    const dispatchBody = ctZip(methods, codes, "    if (m == \"$key\") { return $value }", "\n")

    // Practical pattern: generate field summary from range + map
    const indices = ctRange(0, 4)
    const labels = ctMap(indices, "field_$item", ",")

    @comptimeEmit(`
function getMapped(): string { return "${mapped}" }
function getIndexed(): string { return "${indexed}" }
function getEmptyMap(): string { return "${emptyMap}" }
function getMultiRef(): string { return "${multiRef}" }
function getRange5(): string { return "${range5}" }
function getRange37(): string { return "${range37}" }
function getRangeEmpty(): string { return "${rangeEmpty}" }
function getLen3(): int { return ${len3} }
function getLen0(): int { return ${len0} }
function getLen1(): int { return ${len1} }
function getHasB(): int { return ${hasB} }
function getHasD(): int { return ${hasD} }
function getEmptyHas(): int { return ${emptyHas} }
function getZipped(): string { return "${zipped}" }
function getZipTypes(): string { return "${zipTypes}" }
function getZipEmpty(): string { return "${zipEmpty}" }
function getZipMulti(): string { return "${zipMulti}" }
function getReplaced(): string { return "${replaced}" }
function getRepSafe(): string { return "${repSafe}" }
function getLabels(): string { return "${labels}" }
function statusCode(m: string): int {
${dispatchBody}
    return 0
}
`)
}

function main() {
    // ── ctMap ──
    test("ctMap — basic template", () => {
        assertEqual(getMapped(), "handleGET,handlePOST,handlePUT")
    })

    test("ctMap — $index placeholder", () => {
        assertEqual(getIndexed(), "a[0], b[1], c[2]")
    })

    test("ctMap — empty input", () => {
        assertEqual(getEmptyMap(), "")
    })

    test("ctMap — multiple $item refs", () => {
        assertEqual(getMultiRef(), "x+x,y+y")
    })

    // ── ctRange ──
    test("ctRange — 0 to 5", () => {
        assertEqual(getRange5(), "0,1,2,3,4")
    })

    test("ctRange — 3 to 7", () => {
        assertEqual(getRange37(), "3,4,5,6")
    })

    test("ctRange — empty (start==end)", () => {
        assertEqual(getRangeEmpty(), "")
    })

    // ── ctLen ──
    test("ctLen — three items", () => {
        assertEqual(getLen3(), 3)
    })

    test("ctLen — empty string", () => {
        assertEqual(getLen0(), 0)
    })

    test("ctLen — single item", () => {
        assertEqual(getLen1(), 1)
    })

    // ── ctContains ──
    test("ctContains — found", () => {
        assertEqual(getHasB(), 1)
    })

    test("ctContains — not found", () => {
        assertEqual(getHasD(), 0)
    })

    test("ctContains — empty list", () => {
        assertEqual(getEmptyHas(), 0)
    })

    // ── ctZip ──
    test("ctZip — key-value pairs", () => {
        assertEqual(getZipped(), "x=1, y=2, z=3")
    })

    test("ctZip — typed fields", () => {
        assertEqual(getZipTypes(), "name: string; age: int")
    })

    test("ctZip — empty input", () => {
        assertEqual(getZipEmpty(), "")
    })

    test("ctZip — multiple $key refs", () => {
        assertEqual(getZipMulti(), "a->1 (a),b->2 (b)")
    })

    // ── ctReplaceAll ──
    test("ctReplaceAll — all occurrences", () => {
        assertEqual(getReplaced(), "a-b-c-d")
    })

    test("ctReplaceAll — rep contains old (no infinite loop)", () => {
        assertEqual(getRepSafe(), "aXXbXXc")
    })

    // ── Practical patterns ──
    test("ctZip — dispatch table", () => {
        assertEqual(statusCode("get"), 200)
        assertEqual(statusCode("post"), 201)
        assertEqual(statusCode("delete"), 204)
        assertEqual(statusCode("unknown"), 0)
    })

    test("ctRange + ctMap — generate labels", () => {
        assertEqual(getLabels(), "field_0,field_1,field_2,field_3")
    })
}
