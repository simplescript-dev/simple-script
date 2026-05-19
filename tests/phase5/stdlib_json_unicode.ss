import { JSON, JsonNode } from "@/lib/json"

import { assert, assertEq, assertInt } from "./import/asserts"

function main() {
    // ── Basic ASCII via \uXXXX ──────────────────────────────
    const a1 = JSON.parse('{"ch":"\\u0041"}')
    assertEq(a1.getString("ch"), "A", "\\u0041 → A")

    const a2 = JSON.parse('{"ch":"\\u007A"}')
    assertEq(a2.getString("ch"), "z", "\\u007A → z")

    // ── Mixed text + unicode escape ─────────────────────────
    const a3 = JSON.parse('{"msg":"hello\\u0020world"}')
    assertEq(a3.getString("msg"), "hello world", "\\u0020 → space")

    // ── 2-byte UTF-8 (U+00E9 = é) ──────────────────────────
    const b1 = JSON.parse('{"ch":"\\u00E9"}')
    const b1s = b1.getString("ch")
    assertInt(b1s.length(), 2, "é is 2 bytes in UTF-8")
    assertInt(charCodeAt(b1s, 0), 195, "é byte 0 = 0xC3")
    assertInt(charCodeAt(b1s, 1), 169, "é byte 1 = 0xA9")

    // ── 3-byte UTF-8 (U+4E2D = 中) ─────────────────────────
    const c1 = JSON.parse('{"ch":"\\u4E2D"}')
    const c1s = c1.getString("ch")
    assertInt(c1s.length(), 3, "中 is 3 bytes in UTF-8")
    assertInt(charCodeAt(c1s, 0), 228, "中 byte 0 = 0xE4")
    assertInt(charCodeAt(c1s, 1), 184, "中 byte 1 = 0xB8")
    assertInt(charCodeAt(c1s, 2), 173, "中 byte 2 = 0xAD")

    // ── Surrogate pair (U+1F600 = 😀) ───────────────────────
    const d1 = JSON.parse('{"ch":"\\uD83D\\uDE00"}')
    const d1s = d1.getString("ch")
    assertInt(d1s.length(), 4, "😀 is 4 bytes in UTF-8")
    assertInt(charCodeAt(d1s, 0), 240, "😀 byte 0 = 0xF0")
    assertInt(charCodeAt(d1s, 1), 159, "😀 byte 1 = 0x9F")
    assertInt(charCodeAt(d1s, 2), 152, "😀 byte 2 = 0x98")
    assertInt(charCodeAt(d1s, 3), 128, "😀 byte 3 = 0x80")

    // ── \b and \f escapes ───────────────────────────────────
    const e1 = JSON.parse('{"bs":"a\\bb","ff":"a\\fb"}')
    assertInt(charCodeAt(e1.getString("bs"), 1), 8, "\\b = backspace (8)")
    assertInt(charCodeAt(e1.getString("ff"), 1), 12, "\\f = form feed (12)")

    // ── Stringify control characters ────────────────────────
    const ctrl = JSON.create().put("bs", "a" + fromCharCode(8) + "b").put("ff", "a" + fromCharCode(12) + "b")
    const ctrlStr = JSON.stringify(ctrl)
    assert(ctrlStr.indexOf("\\b") >= 0, "stringify backspace as \\b")
    assert(ctrlStr.indexOf("\\f") >= 0, "stringify form feed as \\f")

    // ── Stringify other control chars as \u00XX ──────────────
    const esc1 = JSON.create().put("x", "a" + fromCharCode(1) + "b")
    const esc1Str = JSON.stringify(esc1)
    assert(esc1Str.indexOf("\\u0001") >= 0, "stringify SOH as \\u0001")

    const esc2 = JSON.create().put("x", "a" + fromCharCode(31) + "b")
    const esc2Str = JSON.stringify(esc2)
    assert(esc2Str.indexOf("\\u001f") >= 0, "stringify US as \\u001f")

    // ── Multiple unicode escapes in one string ──────────────
    const f1 = JSON.parse('{"s":"\\u0048\\u0065\\u006C\\u006C\\u006F"}')
    assertEq(f1.getString("s"), "Hello", "multiple \\uXXXX → Hello")

    // ── Case-insensitive hex ────────────────────────────────
    const g1 = JSON.parse('{"a":"\\u00e9","b":"\\u00E9"}')
    assertEq(g1.getString("a"), g1.getString("b"), "hex case insensitive")

    println("all json unicode tests passed")
}
