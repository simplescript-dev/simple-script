import { JSON, JsonNode } from "@/lib/json"

function assert(cond: int, msg: string) {
    if (cond == 0) {
        println(`FAIL: ${msg}`)
        exit(1)
    }
}

function assertEq(actual: string, expected: string, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} — expected "${expected}", got "${actual}"`)
        exit(1)
    }
}

function assertInt(actual: int, expected: int, msg: string) {
    if (actual != expected) {
        println(`FAIL: ${msg} — expected ${expected}, got ${actual}`)
        exit(1)
    }
}

function main() {
    // ── getDouble ────────────────────────────────────────────
    const obj1 = JSON.parse('{"pi":3.14,"count":42,"neg":-0.5}')
    assert(obj1.getDouble("pi") > 3.13, "getDouble pi lower")
    assert(obj1.getDouble("pi") < 3.15, "getDouble pi upper")
    assert(obj1.getDouble("count") > 41.9, "getDouble int as double")
    assert(obj1.getDouble("neg") < -0.4, "getDouble negative")
    assert(obj1.getDouble("missing") == 0.0, "getDouble missing returns 0")

    // ── getBool ──────────────────────────────────────────────
    const obj2 = JSON.parse('{"active":true,"deleted":false}')
    assertInt(obj2.getBool("active"), 1, "getBool true")
    assertInt(obj2.getBool("deleted"), 0, "getBool false")
    assertInt(obj2.getBool("missing"), 0, "getBool missing")

    // ── has ──────────────────────────────────────────────────
    const obj3 = JSON.parse('{"name":"Alice","age":30}')
    assertInt(obj3.has("name"), 1, "has existing key")
    assertInt(obj3.has("age"), 1, "has existing key 2")
    assertInt(obj3.has("email"), 0, "has missing key")

    // ── keys ─────────────────────────────────────────────────
    const obj4 = JSON.parse('{"a":1,"b":2,"c":3}')
    const k = obj4.keys()
    assertInt(k.length(), 3, "keys length")
    assertEq(k[0], "a", "keys[0]")
    assertEq(k[1], "b", "keys[1]")
    assertEq(k[2], "c", "keys[2]")

    // empty object keys
    const obj5 = JSON.parse('{}')
    assertInt(obj5.keys().length(), 0, "empty object keys")

    // ── asDouble / asBool ────────────────────────────────────
    const arr1 = JSON.parse('[3.14, true, false]')
    assert(arr1.get(0).asDouble() > 3.13, "asDouble from array")
    assertInt(arr1.get(1).asBool(), 1, "asBool true from array")
    assertInt(arr1.get(2).asBool(), 0, "asBool false from array")

    // ── put double / putBool / putNull ───────────────────────
    const built = JSON.create().put("pi", 3.14).putBool("ok", 1).putNull("data")
    assert(built.getDouble("pi") > 3.13, "put double")
    assertInt(built.getBool("ok"), 1, "putBool")
    assertEq(built.get("data").type(), "null", "putNull type")

    // ── add double / addBool / addNull ───────────────────────
    const arr2 = JSON.createArray().add(2.5).addBool(1).addNull()
    assert(arr2.get(0).asDouble() > 2.4, "add double")
    assertInt(arr2.get(1).asBool(), 1, "addBool")
    assertEq(arr2.get(2).type(), "null", "addNull type")

    // ── stringify with escape ────────────────────────────────
    const esc1 = JSON.create().put("msg", "hello\tworld")
    assertEq(JSON.stringify(esc1), '{"msg":"hello\\tworld"}', "stringify escapes tab")

    const esc2 = JSON.create().put("path", "c:\\dir\\file")
    assertEq(JSON.stringify(esc2), '{"path":"c:\\\\dir\\\\file"}', "stringify escapes backslash")

    const esc3 = JSON.create().put("q", 'say "hi"')
    assertEq(JSON.stringify(esc3), '{"q":"say \\"hi\\""}', "stringify escapes quotes")

    const esc4 = JSON.create().put("nl", "line1\nline2")
    assertEq(JSON.stringify(esc4), '{"nl":"line1\\nline2"}', "stringify escapes newline")

    // ── parse escape round-trip ──────────────────────────────
    const rt = JSON.parse('{"t":"a\\tb","n":"a\\nb","bs":"a\\\\b","q":"a\\"b","sl":"a\\/b"}')
    assertEq(rt.getString("t"), "a\tb", "parse \\t")
    assertEq(rt.getString("n"), "a\nb", "parse \\n")
    assertEq(rt.getString("bs"), "a\\b", "parse \\\\")
    assertEq(rt.getString("q"), 'a"b', "parse \\\"")
    assertEq(rt.getString("sl"), "a/b", "parse \\/")

    // ── scientific notation ──────────────────────────────────
    const sci = JSON.parse('{"a":1e2,"b":1.5E3,"c":2e-1,"d":-3.5e+2}')
    assert(sci.getDouble("a") > 99.0, "sci 1e2")
    assert(sci.getDouble("a") < 101.0, "sci 1e2 upper")
    assert(sci.getDouble("b") > 1499.0, "sci 1.5E3")
    assert(sci.getDouble("b") < 1501.0, "sci 1.5E3 upper")
    assert(sci.getDouble("c") > 0.19, "sci 2e-1")
    assert(sci.getDouble("c") < 0.21, "sci 2e-1 upper")
    assert(sci.getDouble("d") < -349.0, "sci -3.5e+2")
    assert(sci.getDouble("d") > -351.0, "sci -3.5e+2 upper")

    // ── stringify bool / null ────────────────────────────────
    const mixed = JSON.create().put("s", "hi").put("n", 1).putBool("b", 1).putNull("x")
    assertEq(JSON.stringify(mixed), '{"s":"hi","n":1,"b":true,"x":null}', "stringify mixed types")

    // ── stringify array with mixed types ─────────────────────
    const arr3 = JSON.createArray().add("a").add(1).addBool(0).addNull()
    assertEq(JSON.stringify(arr3), '["a",1,false,null]', "stringify mixed array")

    println("all json tests passed")
}
