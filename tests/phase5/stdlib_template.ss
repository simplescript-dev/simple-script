import { Template } from "@/lib/template"

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
    let vars = new Map()
    vars.set("name", "Alice")
    vars.set("greeting", "Hello")

    // ── Basic variable substitution ──
    check("basic var", Template.render("{{name}}", vars), "Alice")
    check("two vars", Template.render("{{greeting}}, {{name}}!", vars), "Hello, Alice!")
    check("missing var", Template.render("{{unknown}}", vars), "")
    check("no tags", Template.render("plain text", vars), "plain text")
    check("empty template", Template.render("", vars), "")
    check("text around var", Template.render("Hi {{name}} bye", vars), "Hi Alice bye")

    // ── Whitespace in tags ──
    check("spaces in tag", Template.render("{{ name }}", vars), "Alice")
    check("spaces in tag 2", Template.render("{{  greeting  }}", vars), "Hello")

    // ── Sections ──
    vars.set("loggedIn", "true")
    check("section true", Template.render("{{#loggedIn}}Welcome!{{/loggedIn}}", vars), "Welcome!")
    check("section false", Template.render("{{#admin}}Admin{{/admin}}", vars), "")
    check("section with var", Template.render("{{#loggedIn}}Hi {{name}}{{/loggedIn}}", vars), "Hi Alice")
    check("section mixed", Template.render("A{{#loggedIn}}B{{/loggedIn}}C", vars), "ABC")

    // ── Inverted sections ──
    check("inverted false", Template.render("{{^admin}}Guest{{/admin}}", vars), "Guest")
    check("inverted true", Template.render("{{^loggedIn}}Not logged in{{/loggedIn}}", vars), "")
    check("inverted with var", Template.render("{{^admin}}Hi {{name}}{{/admin}}", vars), "Hi Alice")

    // ── Truthiness ──
    vars.set("empty", "")
    vars.set("zero", "0")
    vars.set("falseVal", "false")
    vars.set("truthy", "yes")
    check("empty not truthy", Template.render("{{#empty}}yes{{/empty}}", vars), "")
    check("zero not truthy", Template.render("{{#zero}}yes{{/zero}}", vars), "")
    check("false not truthy", Template.render("{{#falseVal}}yes{{/falseVal}}", vars), "")
    check("truthy val", Template.render("{{#truthy}}yes{{/truthy}}", vars), "yes")

    // ── Comments ──
    check("comment", Template.render("Hello{{! ignored }}World", vars), "HelloWorld")
    check("comment with spaces", Template.render("A{{!  comment  }}B", vars), "AB")
    check("comment only", Template.render("{{! nothing }}", vars), "")

    // ── Nested sections ──
    vars.set("a", "true")
    vars.set("b", "true")
    check("nested both true", Template.render("{{#a}}X{{#b}}Y{{/b}}Z{{/a}}", vars), "XYZ")

    vars.set("b", "false")
    check("nested inner false", Template.render("{{#a}}X{{#b}}Y{{/b}}Z{{/a}}", vars), "XZ")

    vars.set("a", "false")
    vars.set("b", "true")
    check("nested outer false", Template.render("{{#a}}X{{#b}}Y{{/b}}Z{{/a}}", vars), "")

    // Reset for remaining tests
    vars.set("a", "true")
    vars.set("b", "true")

    // ── Escaped delimiters ──
    check("escaped tag", Template.render("\\{{name}}", vars), "{{name}}")
    check("escaped mixed", Template.render("A\\{{B}}C", vars), "A{{B}}C")

    // ── HTML escape ──
    check("escape amp", Template.escape("a&b"), "a&amp;b")
    check("escape lt gt", Template.escape("<div>"), "&lt;div&gt;")
    check("escape quot", Template.escape("say \"hi\""), "say &quot;hi&quot;")
    check("escape apos", Template.escape("it's"), "it&#39;s")
    check("escape clean", Template.escape("hello"), "hello")
    check("escape empty", Template.escape(""), "")
    check("escape all", Template.escape("<b>&\"'</b>"), "&lt;b&gt;&amp;&quot;&#39;&lt;/b&gt;")

    // ── HTML unescape ──
    check("unescape lt", Template.unescape("&lt;div&gt;"), "<div>")
    check("unescape amp", Template.unescape("a&amp;b"), "a&b")
    check("unescape quot", Template.unescape("&quot;hi&quot;"), "\"hi\"")
    check("unescape apos", Template.unescape("&#39;s"), "'s")
    check("unescape clean", Template.unescape("hello"), "hello")
    check("unescape empty", Template.unescape(""), "")
    check("unescape partial", Template.unescape("&unknown;"), "&unknown;")
    check("roundtrip", Template.unescape(Template.escape("<b>it's \"cool\" & fun</b>")), "<b>it's \"cool\" & fun</b>")

    // ── Variables extraction ──
    const v1 = Template.variables("{{a}} and {{b}}")
    checkInt("vars count 2", v1.length(), 2)
    check("vars 0", v1[0], "a")
    check("vars 1", v1[1], "b")

    const v2 = Template.variables("{{#x}}{{y}}{{/x}}")
    checkInt("section vars count", v2.length(), 2)
    check("section vars 0", v2[0], "x")
    check("section vars 1", v2[1], "y")

    const v3 = Template.variables("{{a}}{{a}}{{b}}")
    checkInt("dedup count", v3.length(), 2)
    check("dedup 0", v3[0], "a")
    check("dedup 1", v3[1], "b")

    const v4 = Template.variables("{{! comment }}{{x}}")
    checkInt("skip comments", v4.length(), 1)
    check("skip comments 0", v4[0], "x")

    const v5 = Template.variables("no tags here")
    checkInt("no vars", v5.length(), 0)

    // ── Strip ──
    check("strip vars", Template.strip("Hello {{name}}, {{greeting}}!"), "Hello , !")
    check("strip sections", Template.strip("{{#a}}content{{/a}}rest"), "contentrest")
    check("strip clean", Template.strip("no tags"), "no tags")
    check("strip empty", Template.strip(""), "")
    check("strip comment", Template.strip("A{{! x }}B"), "AB")

    // ── Edge cases ──
    check("single brace", Template.render("{not a tag}", vars), "{not a tag}")
    check("empty tag", Template.render("{{}}", vars), "")

    println("All template tests passed!")
}
