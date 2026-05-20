import { Template } from "@/lib/template"
import { assertEq } from "./import/asserts"

function main() {
    let vars = new Map()
    vars.set("name", "Alice")
    vars.set("greeting", "Hello")

    // ── Basic variable substitution ──
    assertEq(Template.render("{{name}}", vars), "Alice", "basic var")
    assertEq(Template.render("{{greeting}}, {{name}}!", vars), "Hello, Alice!", "two vars")
    assertEq(Template.render("{{unknown}}", vars), "", "missing var")
    assertEq(Template.render("plain text", vars), "plain text", "no tags")
    assertEq(Template.render("", vars), "", "empty template")
    assertEq(Template.render("Hi {{name}} bye", vars), "Hi Alice bye", "text around var")

    // ── Whitespace in tags ──
    assertEq(Template.render("{{ name }}", vars), "Alice", "spaces in tag")
    assertEq(Template.render("{{  greeting  }}", vars), "Hello", "spaces in tag 2")

    // ── Sections ──
    vars.set("loggedIn", "true")
    assertEq(Template.render("{{#loggedIn}}Welcome!{{/loggedIn}}", vars), "Welcome!", "section true")
    assertEq(Template.render("{{#admin}}Admin{{/admin}}", vars), "", "section false")
    assertEq(Template.render("{{#loggedIn}}Hi {{name}}{{/loggedIn}}", vars), "Hi Alice", "section with var")
    assertEq(Template.render("A{{#loggedIn}}B{{/loggedIn}}C", vars), "ABC", "section mixed")

    // ── Inverted sections ──
    assertEq(Template.render("{{^admin}}Guest{{/admin}}", vars), "Guest", "inverted false")
    assertEq(Template.render("{{^loggedIn}}Not logged in{{/loggedIn}}", vars), "", "inverted true")
    assertEq(Template.render("{{^admin}}Hi {{name}}{{/admin}}", vars), "Hi Alice", "inverted with var")

    // ── Truthiness ──
    vars.set("empty", "")
    vars.set("zero", "0")
    vars.set("falseVal", "false")
    vars.set("truthy", "yes")
    assertEq(Template.render("{{#empty}}yes{{/empty}}", vars), "", "empty not truthy")
    assertEq(Template.render("{{#zero}}yes{{/zero}}", vars), "", "zero not truthy")
    assertEq(Template.render("{{#falseVal}}yes{{/falseVal}}", vars), "", "false not truthy")
    assertEq(Template.render("{{#truthy}}yes{{/truthy}}", vars), "yes", "truthy val")

    // ── Comments ──
    assertEq(Template.render("Hello{{! ignored }}World", vars), "HelloWorld", "comment")
    assertEq(Template.render("A{{!  comment  }}B", vars), "AB", "comment with spaces")
    assertEq(Template.render("{{! nothing }}", vars), "", "comment only")

    // ── Nested sections ──
    vars.set("a", "true")
    vars.set("b", "true")
    assertEq(Template.render("{{#a}}X{{#b}}Y{{/b}}Z{{/a}}", vars), "XYZ", "nested both true")

    vars.set("b", "false")
    assertEq(Template.render("{{#a}}X{{#b}}Y{{/b}}Z{{/a}}", vars), "XZ", "nested inner false")

    vars.set("a", "false")
    vars.set("b", "true")
    assertEq(Template.render("{{#a}}X{{#b}}Y{{/b}}Z{{/a}}", vars), "", "nested outer false")

    // Reset for remaining tests
    vars.set("a", "true")
    vars.set("b", "true")

    // ── Escaped delimiters ──
    assertEq(Template.render("\\{{name}}", vars), "{{name}}", "escaped tag")
    assertEq(Template.render("A\\{{B}}C", vars), "A{{B}}C", "escaped mixed")

    // ── HTML escape ──
    assertEq(Template.escape("a&b"), "a&amp;b", "escape amp")
    assertEq(Template.escape("<div>"), "&lt;div&gt;", "escape lt gt")
    assertEq(Template.escape("say \"hi\""), "say &quot;hi&quot;", "escape quot")
    assertEq(Template.escape("it's"), "it&#39;s", "escape apos")
    assertEq(Template.escape("hello"), "hello", "escape clean")
    assertEq(Template.escape(""), "", "escape empty")
    assertEq(Template.escape("<b>&\"'</b>"), "&lt;b&gt;&amp;&quot;&#39;&lt;/b&gt;", "escape all")

    // ── HTML unescape ──
    assertEq(Template.unescape("&lt;div&gt;"), "<div>", "unescape lt")
    assertEq(Template.unescape("a&amp;b"), "a&b", "unescape amp")
    assertEq(Template.unescape("&quot;hi&quot;"), "\"hi\"", "unescape quot")
    assertEq(Template.unescape("&#39;s"), "'s", "unescape apos")
    assertEq(Template.unescape("hello"), "hello", "unescape clean")
    assertEq(Template.unescape(""), "", "unescape empty")
    assertEq(Template.unescape("&unknown;"), "&unknown;", "unescape partial")
    assertEq(Template.unescape(Template.escape("<b>it's \"cool\" & fun</b>")), "<b>it's \"cool\" & fun</b>", "roundtrip")

    // ── Variables extraction ──
    const v1 = Template.variables("{{a}} and {{b}}")
    assertEq(v1.length(), 2, "vars count 2")
    assertEq(v1[0], "a", "vars 0")
    assertEq(v1[1], "b", "vars 1")

    const v2 = Template.variables("{{#x}}{{y}}{{/x}}")
    assertEq(v2.length(), 2, "section vars count")
    assertEq(v2[0], "x", "section vars 0")
    assertEq(v2[1], "y", "section vars 1")

    const v3 = Template.variables("{{a}}{{a}}{{b}}")
    assertEq(v3.length(), 2, "dedup count")
    assertEq(v3[0], "a", "dedup 0")
    assertEq(v3[1], "b", "dedup 1")

    const v4 = Template.variables("{{! comment }}{{x}}")
    assertEq(v4.length(), 1, "skip comments")
    assertEq(v4[0], "x", "skip comments 0")

    const v5 = Template.variables("no tags here")
    assertEq(v5.length(), 0, "no vars")

    // ── Strip ──
    assertEq(Template.strip("Hello {{name}}, {{greeting}}!"), "Hello , !", "strip vars")
    assertEq(Template.strip("{{#a}}content{{/a}}rest"), "contentrest", "strip sections")
    assertEq(Template.strip("no tags"), "no tags", "strip clean")
    assertEq(Template.strip(""), "", "strip empty")
    assertEq(Template.strip("A{{! x }}B"), "AB", "strip comment")

    // ── Edge cases ──
    assertEq(Template.render("{not a tag}", vars), "{not a tag}", "single brace")
    assertEq(Template.render("{{}}", vars), "", "empty tag")

    println("All template tests passed!")
}
