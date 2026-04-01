import { Regex } from "@/lib/regex"

function check(label: string, actual: string, expected: string) {
    if (actual != expected) {
        println(`FAIL: ${label}`)
        println(`  expected: "${expected}"`)
        println(`  actual:   "${actual}"`)
        exit(1)
    }
}

function checkInt(label: string, actual: int, expected: int) {
    if (actual != expected) {
        println(`FAIL: ${label}`)
        println(`  expected: ${expected}`)
        println(`  actual:   ${actual}`)
        exit(1)
    }
}

function main() {
    // ── test: literal matching ──
    checkInt("literal match", Regex.test("abc", "xabcx"), 1)
    checkInt("literal no match", Regex.test("xyz", "abc"), 0)
    checkInt("literal exact", Regex.test("hello", "hello"), 1)

    // ── test: dot (any char) ──
    checkInt("dot match", Regex.test("a.c", "abc"), 1)
    checkInt("dot match 2", Regex.test("a.c", "axc"), 1)
    checkInt("dot no match", Regex.test("a.c", "ac"), 0)
    checkInt("dot multi", Regex.test("...", "abc"), 1)
    checkInt("dot short", Regex.test("...", "ab"), 0)

    // ── test: anchors ──
    checkInt("anchor start", Regex.test("^abc", "abcdef"), 1)
    checkInt("anchor start fail", Regex.test("^abc", "xabc"), 0)
    checkInt("anchor end", Regex.test("abc$", "xyzabc"), 1)
    checkInt("anchor end fail", Regex.test("abc$", "abcx"), 0)
    checkInt("anchor both", Regex.test("^abc$", "abc"), 1)
    checkInt("anchor both fail", Regex.test("^abc$", "abcd"), 0)

    // ── test: character classes ──
    checkInt("class basic", Regex.test("[abc]", "b"), 1)
    checkInt("class no match", Regex.test("[abc]", "x"), 0)
    checkInt("class range", Regex.test("[a-z]", "m"), 1)
    checkInt("class range fail", Regex.test("[a-z]", "M"), 0)
    checkInt("class multi range", Regex.test("[a-zA-Z]", "Z"), 1)
    checkInt("class negated", Regex.test("[^abc]", "x"), 1)
    checkInt("class negated fail", Regex.test("[^abc]", "a"), 0)
    checkInt("class digit range", Regex.test("[0-9]", "5"), 1)
    checkInt("class escape in class", Regex.test("[\\d]", "5"), 1)

    // ── test: escape sequences ──
    checkInt("escape digit", Regex.test("\\d", "5"), 1)
    checkInt("escape digit fail", Regex.test("\\d", "a"), 0)
    checkInt("escape Digit neg", Regex.test("\\D", "a"), 1)
    checkInt("escape Digit neg fail", Regex.test("\\D", "5"), 0)
    checkInt("escape word", Regex.test("\\w", "a"), 1)
    checkInt("escape word digit", Regex.test("\\w", "5"), 1)
    checkInt("escape word under", Regex.test("\\w", "_"), 1)
    checkInt("escape word fail", Regex.test("\\w", " "), 0)
    checkInt("escape Word neg", Regex.test("\\W", " "), 1)
    checkInt("escape space", Regex.test("\\s", " "), 1)
    checkInt("escape space fail", Regex.test("\\s", "a"), 0)
    checkInt("escape Space neg", Regex.test("\\S", "a"), 1)
    checkInt("escape literal dot", Regex.test("\\.", "."), 1)
    checkInt("escape literal dot fail", Regex.test("\\.", "a"), 0)
    checkInt("escape literal star", Regex.test("\\*", "*"), 1)

    // ── test: quantifier * ──
    checkInt("star zero", Regex.test("^ab*c$", "ac"), 1)
    checkInt("star one", Regex.test("^ab*c$", "abc"), 1)
    checkInt("star many", Regex.test("^ab*c$", "abbbc"), 1)
    checkInt("star fail", Regex.test("^ab*c$", "abx"), 0)

    // ── test: quantifier + ──
    checkInt("plus one", Regex.test("^ab+c$", "abc"), 1)
    checkInt("plus many", Regex.test("^ab+c$", "abbbc"), 1)
    checkInt("plus zero fail", Regex.test("^ab+c$", "ac"), 0)

    // ── test: quantifier ? ──
    checkInt("question zero", Regex.test("^ab?c$", "ac"), 1)
    checkInt("question one", Regex.test("^ab?c$", "abc"), 1)
    checkInt("question two fail", Regex.test("^ab?c$", "abbc"), 0)

    // ── test: alternation ──
    checkInt("alt left", Regex.test("cat|dog", "I have a cat"), 1)
    checkInt("alt right", Regex.test("cat|dog", "I have a dog"), 1)
    checkInt("alt fail", Regex.test("cat|dog", "I have a fish"), 0)
    checkInt("alt anchored", Regex.test("^a|b$", "apple"), 1)
    checkInt("alt anchored 2", Regex.test("^a|b$", "cab"), 1)

    // ── test: groups ──
    checkInt("group basic", Regex.test("(abc)", "xabcx"), 1)
    checkInt("group quant", Regex.test("^(ab)+$", "abab"), 1)
    checkInt("group quant 2", Regex.test("^(ab)+$", "ab"), 1)
    checkInt("group quant fail", Regex.test("^(ab)+$", "aba"), 0)
    checkInt("group alt", Regex.test("(cat|dog)s", "cats"), 1)
    checkInt("group alt 2", Regex.test("(cat|dog)s", "dogs"), 1)
    checkInt("group nested", Regex.test("((a|b)c)+", "acbc"), 1)

    // ── test: combined patterns ──
    checkInt("email-like", Regex.test("\\w+@\\w+\\.\\w+", "user@host.com"), 1)
    checkInt("digits", Regex.test("\\d+", "abc 123 def"), 1)
    checkInt("word boundary", Regex.test("^[a-zA-Z_]\\w*$", "hello_world"), 1)
    checkInt("word boundary fail", Regex.test("^[a-zA-Z_]\\w*$", "123abc"), 0)
    checkInt("ip-like", Regex.test("\\d+\\.\\d+\\.\\d+\\.\\d+", "addr 192.168.1.1 here"), 1)

    // ── match: return matched text ──
    check("match digits", Regex.match("\\d+", "abc 123 def"), "123")
    check("match word", Regex.match("[a-z]+", "HELLO world"), "world")
    check("match none", Regex.match("\\d+", "no digits"), "")
    check("match greedy", Regex.match("a+", "xaaax"), "aaa")
    check("match group", Regex.match("(\\d+)-(\\d+)", "date: 2024-01"), "2024-01")

    // ── matchAll ──
    const allDigits = Regex.matchAll("\\d+", "a1 b23 c456")
    checkInt("matchAll count", allDigits.length(), 3)
    check("matchAll 0", allDigits[0], "1")
    check("matchAll 1", allDigits[1], "23")
    check("matchAll 2", allDigits[2], "456")

    const allWords = Regex.matchAll("[a-z]+", "Hello World Foo")
    checkInt("matchAll words count", allWords.length(), 3)
    check("matchAll word 0", allWords[0], "ello")
    check("matchAll word 1", allWords[1], "orld")
    check("matchAll word 2", allWords[2], "oo")

    const noMatch = Regex.matchAll("\\d+", "no digits here")
    checkInt("matchAll empty", noMatch.length(), 0)

    // ── matchIndex ──
    checkInt("matchIndex found", Regex.matchIndex("\\d+", "abc 123"), 4)
    checkInt("matchIndex start", Regex.matchIndex("^hello", "hello world"), 0)
    checkInt("matchIndex none", Regex.matchIndex("\\d+", "no digits"), -1)

    // ── replace ──
    check("replace first", Regex.replace("\\d+", "a1 b2 c3", "X"), "aX b2 c3")
    check("replace word", Regex.replace("world", "hello world", "there"), "hello there")
    check("replace none", Regex.replace("\\d+", "no digits", "X"), "no digits")
    check("replace anchored", Regex.replace("^hello", "hello world", "hi"), "hi world")

    // ── replaceAll ──
    check("replaceAll digits", Regex.replaceAll("\\d+", "a1 b2 c3", "X"), "aX bX cX")
    check("replaceAll spaces", Regex.replaceAll("\\s+", "a  b   c", " "), "a b c")
    check("replaceAll none", Regex.replaceAll("\\d+", "abc", "X"), "abc")
    check("replaceAll class", Regex.replaceAll("[aeiou]", "hello", "*"), "h*ll*")

    // ── split ──
    const s1 = Regex.split(",", "a,b,c")
    checkInt("split comma count", s1.length(), 3)
    check("split comma 0", s1[0], "a")
    check("split comma 1", s1[1], "b")
    check("split comma 2", s1[2], "c")

    const s2 = Regex.split("\\s+", "hello   world  foo")
    checkInt("split space count", s2.length(), 3)
    check("split space 0", s2[0], "hello")
    check("split space 1", s2[1], "world")
    check("split space 2", s2[2], "foo")

    const s3 = Regex.split("[,;]", "a,b;c")
    checkInt("split class count", s3.length(), 3)
    check("split class 0", s3[0], "a")
    check("split class 1", s3[1], "b")
    check("split class 2", s3[2], "c")

    const s4 = Regex.split("\\d+", "abc")
    checkInt("split no match", s4.length(), 1)
    check("split no match 0", s4[0], "abc")

    const s5 = Regex.split("-", "-a-b-")
    checkInt("split edges count", s5.length(), 4)
    check("split edges 0", s5[0], "")
    check("split edges 1", s5[1], "a")
    check("split edges 2", s5[2], "b")
    check("split edges 3", s5[3], "")

    // ── escape ──
    check("escape special", Regex.escape("a.b*c"), "a\\.b\\*c")
    check("escape parens", Regex.escape("(a|b)"), "\\(a\\|b\\)")
    check("escape clean", Regex.escape("abc"), "abc")
    check("escape brackets", Regex.escape("[abc]"), "\\[abc\\]")

    // Verify escaped pattern matches literal
    checkInt("escape roundtrip", Regex.test(Regex.escape("a.b"), "a.b"), 1)
    checkInt("escape roundtrip fail", Regex.test(Regex.escape("a.b"), "axb"), 0)

    // ── edge cases ──
    checkInt("empty pattern", Regex.test("", "hello"), 1)
    checkInt("empty text", Regex.test("a", ""), 0)
    checkInt("both empty", Regex.test("", ""), 1)
    checkInt("star empty", Regex.test("^a*$", ""), 1)

    println("All regex tests passed!")
}
