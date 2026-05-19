import { URL, UrlParts } from "@/lib/url"

import { assert, assertEq } from "./import/asserts"

function main() {
    // ── Full URL parsing ─────────────────────────────────────
    const u1 = URL.parse("https://user:pass@example.com:8080/path/to?q=1&r=2#frag")
    assertEq(u1.protocol(), "https", "full: protocol")
    assertEq(u1.username(), "user", "full: username")
    assertEq(u1.password(), "pass", "full: password")
    assertEq(u1.hostname(), "example.com", "full: hostname")
    assertEq(u1.port(), "8080", "full: port")
    assertEq(u1.pathname(), "/path/to", "full: pathname")
    assertEq(u1.search(), "q=1&r=2", "full: search")
    assertEq(u1.hash(), "frag", "full: hash")
    assertEq(u1.host(), "example.com:8080", "full: host")
    assertEq(u1.origin(), "https://example.com:8080", "full: origin")

    // ── Simple URL ───────────────────────────────────────────
    const u2 = URL.parse("https://example.com/index.html")
    assertEq(u2.protocol(), "https", "simple: protocol")
    assertEq(u2.hostname(), "example.com", "simple: hostname")
    assertEq(u2.port(), "", "simple: no port")
    assertEq(u2.pathname(), "/index.html", "simple: pathname")
    assertEq(u2.search(), "", "simple: no search")
    assertEq(u2.hash(), "", "simple: no hash")
    assertEq(u2.host(), "example.com", "simple: host no port")
    assertEq(u2.origin(), "https://example.com", "simple: origin no port")

    // ── No path ──────────────────────────────────────────────
    const u3 = URL.parse("https://example.com")
    assertEq(u3.hostname(), "example.com", "nopath: hostname")
    assertEq(u3.pathname(), "", "nopath: empty pathname")

    // ── Query only ───────────────────────────────────────────
    const u4 = URL.parse("https://example.com?key=val")
    assertEq(u4.hostname(), "example.com", "queryonly: hostname")
    assertEq(u4.pathname(), "", "queryonly: pathname")
    assertEq(u4.search(), "key=val", "queryonly: search")

    // ── Fragment only ────────────────────────────────────────
    const u5 = URL.parse("https://example.com#section")
    assertEq(u5.hostname(), "example.com", "fragonly: hostname")
    assertEq(u5.hash(), "section", "fragonly: hash")
    assertEq(u5.search(), "", "fragonly: no search")

    // ── Username only (no password) ──────────────────────────
    const u6 = URL.parse("ftp://admin@files.example.com/pub")
    assertEq(u6.protocol(), "ftp", "useronly: protocol")
    assertEq(u6.username(), "admin", "useronly: username")
    assertEq(u6.password(), "", "useronly: no password")
    assertEq(u6.hostname(), "files.example.com", "useronly: hostname")
    assertEq(u6.pathname(), "/pub", "useronly: pathname")

    // ── IPv6 host ────────────────────────────────────────────
    const u7 = URL.parse("http://[::1]:3000/api")
    assertEq(u7.hostname(), "[::1]", "ipv6: hostname")
    assertEq(u7.port(), "3000", "ipv6: port")
    assertEq(u7.pathname(), "/api", "ipv6: pathname")

    // ── IPv6 without port ────────────────────────────────────
    const u8 = URL.parse("http://[2001:db8::1]/path")
    assertEq(u8.hostname(), "[2001:db8::1]", "ipv6np: hostname")
    assertEq(u8.port(), "", "ipv6np: no port")

    // ── Protocol case normalization ──────────────────────────
    const u9 = URL.parse("HTTP://Example.COM/Path")
    assertEq(u9.protocol(), "http", "case: protocol lowercase")
    assertEq(u9.hostname(), "Example.COM", "case: hostname preserved")
    assertEq(u9.pathname(), "/Path", "case: path preserved")

    // ── href round-trip ──────────────────────────────────────
    const url10 = "https://user:pass@example.com:8080/path?q=1#frag"
    const u10 = URL.parse(url10)
    assertEq(u10.href(), url10, "href: full round-trip")

    const url11 = "https://example.com/page"
    const u11 = URL.parse(url11)
    assertEq(u11.href(), url11, "href: simple round-trip")

    // ── URL.format ───────────────────────────────────────────
    const u12 = URL.parse("https://example.com:443/api?v=2")
    assertEq(URL.format(u12), "https://example.com:443/api?v=2", "format")

    // ── URL.resolve — absolute ref ───────────────────────────
    assertEq(URL.resolve("https://a.com/x", "https://b.com/y"), "https://b.com/y", "resolve: absolute")

    // ── URL.resolve — absolute path ──────────────────────────
    assertEq(URL.resolve("https://a.com/x/y", "/z"), "https://a.com/z", "resolve: abs path")

    // ── URL.resolve — relative path ──────────────────────────
    assertEq(URL.resolve("https://a.com/x/y", "z"), "https://a.com/x/z", "resolve: relative")

    // ── URL.resolve — protocol-relative ──────────────────────
    assertEq(URL.resolve("https://a.com/x", "//b.com/y"), "https://b.com/y", "resolve: proto-rel")

    // ── URL.parseQuery — basic ───────────────────────────────
    const q1 = URL.parseQuery("a=1&b=hello&c=world")
    assertEq(q1.getString("a"), "1", "parseQuery: a")
    assertEq(q1.getString("b"), "hello", "parseQuery: b")
    assertEq(q1.getString("c"), "world", "parseQuery: c")

    // ── URL.parseQuery — with leading ? ──────────────────────
    const q2 = URL.parseQuery("?x=10&y=20")
    assertEq(q2.getString("x"), "10", "parseQuery: leading ?")
    assertEq(q2.getString("y"), "20", "parseQuery: leading ? y")

    // ── URL.parseQuery — encoded values ──────────────────────
    const q3 = URL.parseQuery("name=hello%20world&path=%2Fhome")
    assertEq(q3.getString("name"), "hello world", "parseQuery: decode space")
    assertEq(q3.getString("path"), "/home", "parseQuery: decode slash")

    // ── URL.parseQuery — plus as space ───────────────────────
    const q4 = URL.parseQuery("q=hello+world")
    assertEq(q4.getString("q"), "hello world", "parseQuery: plus space")

    // ── URL.parseQuery — key without value ───────────────────
    const q5 = URL.parseQuery("flag&key=val")
    assertEq(q5.getString("flag"), "", "parseQuery: key no value")
    assertEq(q5.getString("key"), "val", "parseQuery: key with value")

    // ── URL.parseQuery — empty ───────────────────────────────
    const q6 = URL.parseQuery("")
    assert(q6.has("x") == 0, "parseQuery: empty has no keys")

    // ── URL.encodeQuery — parallel arrays ────────────────────
    let ek: Array<string> = []
    let ev: Array<string> = []
    ek = ek.push("name")
    ev = ev.push("Alice Bob")
    ek = ek.push("age")
    ev = ev.push("30")
    const encoded = URL.encodeQuery(ek, ev)
    assertEq(encoded, "name=Alice%20Bob&age=30", "encodeQuery")

    // ── URL.encodeQuery — single pair ────────────────────────
    let ek2: Array<string> = []
    let ev2: Array<string> = []
    ek2 = ek2.push("q")
    ev2 = ev2.push("hello world")
    assertEq(URL.encodeQuery(ek2, ev2), "q=hello%20world", "encodeQuery: single")

    // ── URL.encodeComponent ──────────────────────────────────
    assertEq(URL.encodeComponent("hello"), "hello", "encode: plain")
    assertEq(URL.encodeComponent("hello world"), "hello%20world", "encode: space")
    assertEq(URL.encodeComponent("a=b&c=d"), "a%3Db%26c%3Dd", "encode: special")
    assertEq(URL.encodeComponent("~test-val_1.0"), "~test-val_1.0", "encode: unreserved")

    // ── URL.decodeComponent ──────────────────────────────────
    assertEq(URL.decodeComponent("hello"), "hello", "decode: plain")
    assertEq(URL.decodeComponent("hello%20world"), "hello world", "decode: %20")
    assertEq(URL.decodeComponent("a%3Db%26c"), "a=b&c", "decode: special")
    assertEq(URL.decodeComponent("hello+world"), "hello world", "decode: plus")

    // ── URL.decodeComponent — case insensitive hex ───────────
    assertEq(URL.decodeComponent("%2f"), "/", "decode: lowercase hex")
    assertEq(URL.decodeComponent("%2F"), "/", "decode: uppercase hex")

    // ── Encode/decode round-trip ─────────────────────────────
    const original = "hello world/path?q=v&a=b#sec"
    assertEq(URL.decodeComponent(URL.encodeComponent(original)), original, "encode-decode roundtrip")

    // ── file:// scheme ───────────────────────────────────────
    const u13 = URL.parse("file:///usr/local/bin")
    assertEq(u13.protocol(), "file", "file: protocol")
    assertEq(u13.hostname(), "", "file: empty hostname")
    assertEq(u13.pathname(), "/usr/local/bin", "file: pathname")

    // ── Custom scheme ────────────────────────────────────────
    const u14 = URL.parse("custom+scheme://host/path")
    assertEq(u14.protocol(), "custom+scheme", "custom: protocol")
    assertEq(u14.hostname(), "host", "custom: hostname")

    // ── Path without scheme ──────────────────────────────────
    const u15 = URL.parse("/just/a/path")
    assertEq(u15.protocol(), "", "noscheme: no protocol")
    assertEq(u15.pathname(), "/just/a/path", "noscheme: pathname")

    println("all url tests passed")
}
