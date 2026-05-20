import { Regex } from "@/lib/regex"
import { assertEq } from "./import/asserts"

function main() {
    // ── test: literal matching ──
    assertEq(Regex.test("abc", "xabcx"), 1, "literal match")
    assertEq(Regex.test("xyz", "abc"), 0, "literal no match")
    assertEq(Regex.test("hello", "hello"), 1, "literal exact")

    // ── test: dot (any char) ──
    assertEq(Regex.test("a.c", "abc"), 1, "dot match")
    assertEq(Regex.test("a.c", "axc"), 1, "dot match 2")
    assertEq(Regex.test("a.c", "ac"), 0, "dot no match")
    assertEq(Regex.test("...", "abc"), 1, "dot multi")
    assertEq(Regex.test("...", "ab"), 0, "dot short")

    // ── test: anchors ──
    assertEq(Regex.test("^abc", "abcdef"), 1, "anchor start")
    assertEq(Regex.test("^abc", "xabc"), 0, "anchor start fail")
    assertEq(Regex.test("abc$", "xyzabc"), 1, "anchor end")
    assertEq(Regex.test("abc$", "abcx"), 0, "anchor end fail")
    assertEq(Regex.test("^abc$", "abc"), 1, "anchor both")
    assertEq(Regex.test("^abc$", "abcd"), 0, "anchor both fail")

    // ── test: character classes ──
    assertEq(Regex.test("[abc]", "b"), 1, "class basic")
    assertEq(Regex.test("[abc]", "x"), 0, "class no match")
    assertEq(Regex.test("[a-z]", "m"), 1, "class range")
    assertEq(Regex.test("[a-z]", "M"), 0, "class range fail")
    assertEq(Regex.test("[a-zA-Z]", "Z"), 1, "class multi range")
    assertEq(Regex.test("[^abc]", "x"), 1, "class negated")
    assertEq(Regex.test("[^abc]", "a"), 0, "class negated fail")
    assertEq(Regex.test("[0-9]", "5"), 1, "class digit range")
    assertEq(Regex.test("[\\d]", "5"), 1, "class escape in class")

    // ── test: escape sequences ──
    assertEq(Regex.test("\\d", "5"), 1, "escape digit")
    assertEq(Regex.test("\\d", "a"), 0, "escape digit fail")
    assertEq(Regex.test("\\D", "a"), 1, "escape Digit neg")
    assertEq(Regex.test("\\D", "5"), 0, "escape Digit neg fail")
    assertEq(Regex.test("\\w", "a"), 1, "escape word")
    assertEq(Regex.test("\\w", "5"), 1, "escape word digit")
    assertEq(Regex.test("\\w", "_"), 1, "escape word under")
    assertEq(Regex.test("\\w", " "), 0, "escape word fail")
    assertEq(Regex.test("\\W", " "), 1, "escape Word neg")
    assertEq(Regex.test("\\s", " "), 1, "escape space")
    assertEq(Regex.test("\\s", "a"), 0, "escape space fail")
    assertEq(Regex.test("\\S", "a"), 1, "escape Space neg")
    assertEq(Regex.test("\\.", "."), 1, "escape literal dot")
    assertEq(Regex.test("\\.", "a"), 0, "escape literal dot fail")
    assertEq(Regex.test("\\*", "*"), 1, "escape literal star")

    // ── test: quantifier * ──
    assertEq(Regex.test("^ab*c$", "ac"), 1, "star zero")
    assertEq(Regex.test("^ab*c$", "abc"), 1, "star one")
    assertEq(Regex.test("^ab*c$", "abbbc"), 1, "star many")
    assertEq(Regex.test("^ab*c$", "abx"), 0, "star fail")

    // ── test: quantifier + ──
    assertEq(Regex.test("^ab+c$", "abc"), 1, "plus one")
    assertEq(Regex.test("^ab+c$", "abbbc"), 1, "plus many")
    assertEq(Regex.test("^ab+c$", "ac"), 0, "plus zero fail")

    // ── test: quantifier ? ──
    assertEq(Regex.test("^ab?c$", "ac"), 1, "question zero")
    assertEq(Regex.test("^ab?c$", "abc"), 1, "question one")
    assertEq(Regex.test("^ab?c$", "abbc"), 0, "question two fail")

    // ── test: alternation ──
    assertEq(Regex.test("cat|dog", "I have a cat"), 1, "alt left")
    assertEq(Regex.test("cat|dog", "I have a dog"), 1, "alt right")
    assertEq(Regex.test("cat|dog", "I have a fish"), 0, "alt fail")
    assertEq(Regex.test("^a|b$", "apple"), 1, "alt anchored")
    assertEq(Regex.test("^a|b$", "cab"), 1, "alt anchored 2")

    // ── test: groups ──
    assertEq(Regex.test("(abc)", "xabcx"), 1, "group basic")
    assertEq(Regex.test("^(ab)+$", "abab"), 1, "group quant")
    assertEq(Regex.test("^(ab)+$", "ab"), 1, "group quant 2")
    assertEq(Regex.test("^(ab)+$", "aba"), 0, "group quant fail")
    assertEq(Regex.test("(cat|dog)s", "cats"), 1, "group alt")
    assertEq(Regex.test("(cat|dog)s", "dogs"), 1, "group alt 2")
    assertEq(Regex.test("((a|b)c)+", "acbc"), 1, "group nested")

    // ── test: combined patterns ──
    assertEq(Regex.test("\\w+@\\w+\\.\\w+", "user@host.com"), 1, "email-like")
    assertEq(Regex.test("\\d+", "abc 123 def"), 1, "digits")
    assertEq(Regex.test("^[a-zA-Z_]\\w*$", "hello_world"), 1, "word boundary")
    assertEq(Regex.test("^[a-zA-Z_]\\w*$", "123abc"), 0, "word boundary fail")
    assertEq(Regex.test("\\d+\\.\\d+\\.\\d+\\.\\d+", "addr 192.168.1.1 here"), 1, "ip-like")

    // ── match: return matched text ──
    assertEq(Regex.match("\\d+", "abc 123 def"), "123", "match digits")
    assertEq(Regex.match("[a-z]+", "HELLO world"), "world", "match word")
    assertEq(Regex.match("\\d+", "no digits"), "", "match none")
    assertEq(Regex.match("a+", "xaaax"), "aaa", "match greedy")
    assertEq(Regex.match("(\\d+)-(\\d+)", "date: 2024-01"), "2024-01", "match group")

    // ── matchAll ──
    const allDigits = Regex.matchAll("\\d+", "a1 b23 c456")
    assertEq(allDigits.length(), 3, "matchAll count")
    assertEq(allDigits[0], "1", "matchAll 0")
    assertEq(allDigits[1], "23", "matchAll 1")
    assertEq(allDigits[2], "456", "matchAll 2")

    const allWords = Regex.matchAll("[a-z]+", "Hello World Foo")
    assertEq(allWords.length(), 3, "matchAll words count")
    assertEq(allWords[0], "ello", "matchAll word 0")
    assertEq(allWords[1], "orld", "matchAll word 1")
    assertEq(allWords[2], "oo", "matchAll word 2")

    const noMatch = Regex.matchAll("\\d+", "no digits here")
    assertEq(noMatch.length(), 0, "matchAll empty")

    // ── matchIndex ──
    assertEq(Regex.matchIndex("\\d+", "abc 123"), 4, "matchIndex found")
    assertEq(Regex.matchIndex("^hello", "hello world"), 0, "matchIndex start")
    assertEq(Regex.matchIndex("\\d+", "no digits"), -1, "matchIndex none")

    // ── replace ──
    assertEq(Regex.replace("\\d+", "a1 b2 c3", "X"), "aX b2 c3", "replace first")
    assertEq(Regex.replace("world", "hello world", "there"), "hello there", "replace word")
    assertEq(Regex.replace("\\d+", "no digits", "X"), "no digits", "replace none")
    assertEq(Regex.replace("^hello", "hello world", "hi"), "hi world", "replace anchored")

    // ── replaceAll ──
    assertEq(Regex.replaceAll("\\d+", "a1 b2 c3", "X"), "aX bX cX", "replaceAll digits")
    assertEq(Regex.replaceAll("\\s+", "a  b   c", " "), "a b c", "replaceAll spaces")
    assertEq(Regex.replaceAll("\\d+", "abc", "X"), "abc", "replaceAll none")
    assertEq(Regex.replaceAll("[aeiou]", "hello", "*"), "h*ll*", "replaceAll class")

    // ── split ──
    const s1 = Regex.split(",", "a,b,c")
    assertEq(s1.length(), 3, "split comma count")
    assertEq(s1[0], "a", "split comma 0")
    assertEq(s1[1], "b", "split comma 1")
    assertEq(s1[2], "c", "split comma 2")

    const s2 = Regex.split("\\s+", "hello   world  foo")
    assertEq(s2.length(), 3, "split space count")
    assertEq(s2[0], "hello", "split space 0")
    assertEq(s2[1], "world", "split space 1")
    assertEq(s2[2], "foo", "split space 2")

    const s3 = Regex.split("[,;]", "a,b;c")
    assertEq(s3.length(), 3, "split class count")
    assertEq(s3[0], "a", "split class 0")
    assertEq(s3[1], "b", "split class 1")
    assertEq(s3[2], "c", "split class 2")

    const s4 = Regex.split("\\d+", "abc")
    assertEq(s4.length(), 1, "split no match")
    assertEq(s4[0], "abc", "split no match 0")

    const s5 = Regex.split("-", "-a-b-")
    assertEq(s5.length(), 4, "split edges count")
    assertEq(s5[0], "", "split edges 0")
    assertEq(s5[1], "a", "split edges 1")
    assertEq(s5[2], "b", "split edges 2")
    assertEq(s5[3], "", "split edges 3")

    // ── escape ──
    assertEq(Regex.escape("a.b*c"), "a\\.b\\*c", "escape special")
    assertEq(Regex.escape("(a|b)"), "\\(a\\|b\\)", "escape parens")
    assertEq(Regex.escape("abc"), "abc", "escape clean")
    assertEq(Regex.escape("[abc]"), "\\[abc\\]", "escape brackets")

    // Verify escaped pattern matches literal
    assertEq(Regex.test(Regex.escape("a.b"), "a.b"), 1, "escape roundtrip")
    assertEq(Regex.test(Regex.escape("a.b"), "axb"), 0, "escape roundtrip fail")

    // ── edge cases ──
    assertEq(Regex.test("", "hello"), 1, "empty pattern")
    assertEq(Regex.test("a", ""), 0, "empty text")
    assertEq(Regex.test("", ""), 1, "both empty")
    assertEq(Regex.test("^a*$", ""), 1, "star empty")

    println("All regex tests passed!")
}
