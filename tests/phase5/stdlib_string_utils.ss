// Test: StringUtil standard library module (D038)

import { StringUtil } from "@/lib/string_utils"

import { assert, assertEq, assertInt } from "./import/asserts"

function main() {
    // ── trimStart ───────────────────────────────────────────
    assertEq(StringUtil.trimStart("  hello  "), "hello  ", "trimStart spaces")
    assertEq(StringUtil.trimStart("\t\nhello"), "hello", "trimStart tabs+newline")
    assertEq(StringUtil.trimStart("hello"), "hello", "trimStart no ws")
    assertEq(StringUtil.trimStart("   "), "", "trimStart all ws")
    assertEq(StringUtil.trimStart(""), "", "trimStart empty")

    // ── trimEnd ─────────────────────────────────────────────
    assertEq(StringUtil.trimEnd("  hello  "), "  hello", "trimEnd spaces")
    assertEq(StringUtil.trimEnd("hello\t\n"), "hello", "trimEnd tabs+newline")
    assertEq(StringUtil.trimEnd("hello"), "hello", "trimEnd no ws")
    assertEq(StringUtil.trimEnd("   "), "", "trimEnd all ws")
    assertEq(StringUtil.trimEnd(""), "", "trimEnd empty")

    // ── capitalize ──────────────────────────────────────────
    assertEq(StringUtil.capitalize("hello"), "Hello", "capitalize lower")
    assertEq(StringUtil.capitalize("Hello"), "Hello", "capitalize already upper")
    assertEq(StringUtil.capitalize("a"), "A", "capitalize single char")
    assertEq(StringUtil.capitalize(""), "", "capitalize empty")
    assertEq(StringUtil.capitalize("123"), "123", "capitalize digit")

    // ── isBlank ─────────────────────────────────────────────
    assert(StringUtil.isBlank("") == 1, "isBlank empty")
    assert(StringUtil.isBlank("   ") == 1, "isBlank spaces")
    assert(StringUtil.isBlank("\t\n\r") == 1, "isBlank whitespace mix")
    assert(StringUtil.isBlank("hello") == 0, "isBlank text")
    assert(StringUtil.isBlank(" a ") == 0, "isBlank text with spaces")

    // ── isDigit ─────────────────────────────────────────────
    assert(StringUtil.isDigit("12345") == 1, "isDigit all digits")
    assert(StringUtil.isDigit("0") == 1, "isDigit zero")
    assert(StringUtil.isDigit("12a34") == 0, "isDigit mixed")
    assert(StringUtil.isDigit("abc") == 0, "isDigit alpha")
    assert(StringUtil.isDigit("") == 0, "isDigit empty")

    // ── isAlpha ─────────────────────────────────────────────
    assert(StringUtil.isAlpha("hello") == 1, "isAlpha lower")
    assert(StringUtil.isAlpha("Hello") == 1, "isAlpha mixed case")
    assert(StringUtil.isAlpha("ABC") == 1, "isAlpha upper")
    assert(StringUtil.isAlpha("abc123") == 0, "isAlpha with digits")
    assert(StringUtil.isAlpha("") == 0, "isAlpha empty")

    // ── isAlphaNumeric ──────────────────────────────────────
    assert(StringUtil.isAlphaNumeric("abc123") == 1, "isAlphaNumeric mixed")
    assert(StringUtil.isAlphaNumeric("hello") == 1, "isAlphaNumeric alpha only")
    assert(StringUtil.isAlphaNumeric("12345") == 1, "isAlphaNumeric digit only")
    assert(StringUtil.isAlphaNumeric("abc 123") == 0, "isAlphaNumeric with space")
    assert(StringUtil.isAlphaNumeric("") == 0, "isAlphaNumeric empty")

    // ── reverse ─────────────────────────────────────────────
    assertEq(StringUtil.reverse("hello"), "olleh", "reverse basic")
    assertEq(StringUtil.reverse("a"), "a", "reverse single")
    assertEq(StringUtil.reverse(""), "", "reverse empty")
    assertEq(StringUtil.reverse("abcd"), "dcba", "reverse 4 chars")

    // ── padCenter ───────────────────────────────────────────
    assertEq(StringUtil.padCenter("hi", 10, "-"), "----hi----", "padCenter even")
    assertEq(StringUtil.padCenter("abc", 7, "*"), "**abc**", "padCenter odd")
    assertEq(StringUtil.padCenter("hello", 5, "-"), "hello", "padCenter exact")
    assertEq(StringUtil.padCenter("hello", 3, "-"), "hello", "padCenter shorter")
    assertEq(StringUtil.padCenter("x", 4, "-"), "-x--", "padCenter asymmetric")

    // ── truncate ────────────────────────────────────────────
    assertEq(StringUtil.truncate("hello world", 8, "..."), "hello...", "truncate basic")
    assertEq(StringUtil.truncate("hi", 10, "..."), "hi", "truncate no cut")
    assertEq(StringUtil.truncate("hello", 5, "..."), "hello", "truncate exact")
    assertEq(StringUtil.truncate("hello world", 5, ".."), "hel..", "truncate short suffix")

    // ── count ───────────────────────────────────────────────
    assertInt(StringUtil.count("ababa", "ab"), 2, "count overlap")
    assertInt(StringUtil.count("hello", "l"), 2, "count single char")
    assertInt(StringUtil.count("hello", "x"), 0, "count no match")
    assertInt(StringUtil.count("aaa", "aa"), 1, "count non-overlapping")
    assertInt(StringUtil.count("hello", ""), 0, "count empty sub")

    // ── removePrefix ────────────────────────────────────────
    assertEq(StringUtil.removePrefix("hello world", "hello "), "world", "removePrefix match")
    assertEq(StringUtil.removePrefix("hello", "xyz"), "hello", "removePrefix no match")
    assertEq(StringUtil.removePrefix("hello", "hello"), "", "removePrefix full")
    assertEq(StringUtil.removePrefix("", "abc"), "", "removePrefix empty")

    // ── removeSuffix ────────────────────────────────────────
    assertEq(StringUtil.removeSuffix("hello.txt", ".txt"), "hello", "removeSuffix match")
    assertEq(StringUtil.removeSuffix("hello", ".txt"), "hello", "removeSuffix no match")
    assertEq(StringUtil.removeSuffix("hello", "hello"), "", "removeSuffix full")
    assertEq(StringUtil.removeSuffix("", "abc"), "", "removeSuffix empty")

    // ── equalsIgnoreCase ────────────────────────────────────
    assert(StringUtil.equalsIgnoreCase("Hello", "hello") == 1, "eqIC lower")
    assert(StringUtil.equalsIgnoreCase("ABC", "abc") == 1, "eqIC upper")
    assert(StringUtil.equalsIgnoreCase("Hello", "World") == 0, "eqIC diff")
    assert(StringUtil.equalsIgnoreCase("abc", "abcd") == 0, "eqIC diff len")
    assert(StringUtil.equalsIgnoreCase("", "") == 1, "eqIC both empty")

    // ── lines ───────────────────────────────────────────────
    const lns = StringUtil.lines("one\ntwo\nthree")
    assertInt(lns.length(), 3, "lines count")
    assertEq(lns[0], "one", "lines[0]")
    assertEq(lns[1], "two", "lines[1]")
    assertEq(lns[2], "three", "lines[2]")

    const singleLine = StringUtil.lines("hello")
    assertInt(singleLine.length(), 1, "lines single count")
    assertEq(singleLine[0], "hello", "lines single[0]")

    // ── words ───────────────────────────────────────────────
    const ws = StringUtil.words("  hello   world  ")
    assertInt(ws.length(), 2, "words count")
    assertEq(ws[0], "hello", "words[0]")
    assertEq(ws[1], "world", "words[1]")

    const singleWord = StringUtil.words("hello")
    assertInt(singleWord.length(), 1, "words single count")
    assertEq(singleWord[0], "hello", "words single[0]")

    const emptyWords = StringUtil.words("   ")
    assertInt(emptyWords.length(), 0, "words empty")

    println("All StringUtil stdlib tests passed!")
}
