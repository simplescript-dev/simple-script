// Test: comptime string utilities + lookup table generation + @derive(Default)
//
// Demonstrates:
//   1. ctJoin — join comma-separated items with custom separator
//   2. ctRepeat — repeat string N times
//   3. ctIndent — indent multiline code
//   4. ctWrap — wrap each item with prefix/suffix
//   5. ctGenLookup — generate lookup function from parallel key/value lists
//   6. ctGenReverseLookup — generate reverse lookup (value -> key)
//   7. @derive("Default") — zero-value factory method

import { assertEqual } from "@/lib/test"
import { } from "@/lib/comptime"

// ── @derive(Default) test classes ──

@derive("Default")
class Settings {
    host: string
    port: int
    ratio: double
}

@derive("Default,Equals")
class Coord {
    x: int
    y: int
}

// ── Comptime string utility tests ──

comptime {
    // ctJoin tests
    const joined1 = ctJoin("a,b,c", " | ")
    const joined2 = ctJoin("hello,world", " ")
    const joined3 = ctJoin("single", "-")
    const joined4 = ctJoin("", ",")

    // ctRepeat tests
    const rep1 = ctRepeat("ab", 3)
    const rep2 = ctRepeat("-", 5)
    const rep3 = ctRepeat("x", 0)

    // ctWrap tests
    const wrapped1 = ctWrap("a,b,c", "'", "'", ", ")
    const wrapped2 = ctWrap("x,y,z", "[", "]", " ")
    const wrapped3 = ctWrap("", "<", ">", ",")

    @comptimeEmit(`
function testJoin1(): string { return "${joined1}" }
function testJoin2(): string { return "${joined2}" }
function testJoin3(): string { return "${joined3}" }
function testJoin4(): string { return "${joined4}" }
function testRepeat1(): string { return "${rep1}" }
function testRepeat2(): string { return "${rep2}" }
function testRepeat3(): string { return "${rep3}" }
function testWrap1(): string { return "${wrapped1}" }
function testWrap2(): string { return "${wrapped2}" }
function testWrap3(): string { return "${wrapped3}" }
`)
}

// ── ctIndent test: use it to generate actual indented code ──

comptime {
    // Generate an indented function body using ctIndent
    const body = "let sum = 0\nsum = sum + 10\nsum = sum + 20\nreturn sum"
    const indented = ctIndent(body, "    ")
    @comptimeEmit("function testIndentedCode(): int {\n" + indented + "\n}")
}

// ── Lookup table generation ──

comptime {
    // HTTP status lookup: method -> default status
    const httpKeys = "GET,POST,PUT,DELETE,PATCH"
    const httpVals = "200 OK,201 Created,200 OK,204 No Content,200 OK"
    const httpLookup = ctGenLookup("httpStatus", httpKeys, httpVals, "string", "\"400 Bad Request\"")

    // Priority lookup: name -> numeric level
    const priKeys = "low,medium,high,critical"
    const priVals = "1,2,3,4"
    const priLookup = ctGenLookup("priorityLevel", priKeys, priVals, "int", "0")

    // Reverse lookup: level -> name
    const priReverse = ctGenReverseLookup("priorityName", priKeys, priVals, "int", "\"unknown\"")

    @comptimeEmit(`
${httpLookup}
${priLookup}
${priReverse}
`)
}

function main() {
    // ── ctJoin ──
    test("ctJoin — three items with pipe separator", () => {
        assertEqual(testJoin1(), "a | b | c")
    })
    test("ctJoin — two items with space", () => {
        assertEqual(testJoin2(), "hello world")
    })
    test("ctJoin — single item unchanged", () => {
        assertEqual(testJoin3(), "single")
    })
    test("ctJoin — empty input returns empty", () => {
        assertEqual(testJoin4(), "")
    })

    // ── ctRepeat ──
    test("ctRepeat — repeat 3 times", () => {
        assertEqual(testRepeat1(), "ababab")
    })
    test("ctRepeat — repeat dash 5 times", () => {
        assertEqual(testRepeat2(), "-----")
    })
    test("ctRepeat — repeat 0 times returns empty", () => {
        assertEqual(testRepeat3(), "")
    })

    // ── ctIndent ──
    test("ctIndent — generates valid indented code", () => {
        assertEqual(testIndentedCode(), 30)
    })

    // ── ctWrap ──
    test("ctWrap — wrap with quotes", () => {
        assertEqual(testWrap1(), "'a', 'b', 'c'")
    })
    test("ctWrap — wrap with brackets", () => {
        assertEqual(testWrap2(), "[x] [y] [z]")
    })
    test("ctWrap — empty input returns empty", () => {
        assertEqual(testWrap3(), "")
    })

    // ── Lookup table ──
    test("ctGenLookup — HTTP GET status", () => {
        assertEqual(httpStatus("GET"), "200 OK")
    })
    test("ctGenLookup — HTTP POST status", () => {
        assertEqual(httpStatus("POST"), "201 Created")
    })
    test("ctGenLookup — HTTP DELETE status", () => {
        assertEqual(httpStatus("DELETE"), "204 No Content")
    })
    test("ctGenLookup — unknown key returns fallback", () => {
        assertEqual(httpStatus("OPTIONS"), "400 Bad Request")
    })
    test("ctGenLookup — priority int lookup", () => {
        assertEqual(priorityLevel("critical"), 4)
    })
    test("ctGenLookup — priority unknown returns 0", () => {
        assertEqual(priorityLevel("none"), 0)
    })

    // ── Reverse lookup ──
    test("ctGenReverseLookup — level 3 -> high", () => {
        assertEqual(priorityName(3), "high")
    })
    test("ctGenReverseLookup — unknown level returns fallback", () => {
        assertEqual(priorityName(99), "unknown")
    })

    // ── @derive(Default) ──
    test("derive Default — Settings has zero values", () => {
        const s = new Settings().empty()
        assertEqual(s.host, "")
        assertEqual(s.port, 0)
    })
    test("derive Default — Coord empty equals zero coord", () => {
        const c = new Coord().empty()
        const zero = new Coord(x: 0, y: 0)
        assertEqual(c.equals(zero), 1)
    })
}
