import { Ini, IniData } from "@/lib/ini"

function main() {
    // ── Basic parse ──────────────────────────────────────────
    const text = "[database]\nhost = localhost\nport = 3306\n\n[server]\nport = 8080\ndebug = true\n"
    const data = Ini.parse(text)

    // Get values
    if (data.get("database", "host") != "localhost") { exit(1) }
    if (data.get("database", "port") != "3306") { exit(1) }
    if (data.get("server", "port") != "8080") { exit(1) }
    if (data.get("server", "debug") != "true") { exit(1) }

    // Missing key returns empty string
    if (data.get("database", "missing") != "") { exit(1) }
    if (data.get("nonexistent", "key") != "") { exit(1) }

    // ── hasSection / hasKey ──────────────────────────────────
    if (data.hasSection("database") != 1) { exit(1) }
    if (data.hasSection("server") != 1) { exit(1) }
    if (data.hasSection("missing") != 0) { exit(1) }
    if (data.hasKey("database", "host") != 1) { exit(1) }
    if (data.hasKey("database", "missing") != 0) { exit(1) }

    // ── sections / keys ─────────────────────────────────────
    const secs = data.sections()
    if (secs.length() != 2) { exit(1) }
    if (secs[0] != "database") { exit(1) }
    if (secs[1] != "server") { exit(1) }

    const dbKeys = data.keys("database")
    if (dbKeys.length() != 2) { exit(1) }
    if (dbKeys[0] != "host") { exit(1) }
    if (dbKeys[1] != "port") { exit(1) }

    // ── Comments and empty lines ─────────────────────────────
    const text2 = "; this is a comment\n# another comment\n\n[section]\nkey = value\n"
    const data2 = Ini.parse(text2)
    if (data2.get("section", "key") != "value") { exit(1) }
    if (data2.sections().length() != 1) { exit(1) }

    // ── Whitespace trimming ──────────────────────────────────
    const text3 = "[spaces]\n  key1  =  value1  \nkey2=value2\n"
    const data3 = Ini.parse(text3)
    if (data3.get("spaces", "key1") != "value1") { exit(1) }
    if (data3.get("spaces", "key2") != "value2") { exit(1) }

    // ── Global section (keys before any [section]) ───────────
    const text4 = "global_key = global_value\n\n[local]\nlocal_key = local_value\n"
    const data4 = Ini.parse(text4)
    if (data4.get("", "global_key") != "global_value") { exit(1) }
    if (data4.get("local", "local_key") != "local_value") { exit(1) }

    // ── Edge cases ───────────────────────────────────────────
    // Empty value
    const text5 = "[edge]\nempty =\nwith_eq = a=b=c\n"
    const data5 = Ini.parse(text5)
    if (data5.get("edge", "empty") != "") { exit(1) }
    if (data5.get("edge", "with_eq") != "a=b=c") { exit(1) }

    // ── set: modify existing ─────────────────────────────────
    data.set("database", "host", "127.0.0.1")
    if (data.get("database", "host") != "127.0.0.1") { exit(1) }

    // ── set: add new key to existing section ─────────────────
    data.set("database", "name", "mydb")
    if (data.get("database", "name") != "mydb") { exit(1) }
    if (data.hasKey("database", "name") != 1) { exit(1) }

    // ── set: add new section ─────────────────────────────────
    data.set("cache", "ttl", "3600")
    if (data.get("cache", "ttl") != "3600") { exit(1) }
    if (data.hasSection("cache") != 1) { exit(1) }

    // ── remove ───────────────────────────────────────────────
    data.remove("database", "name")
    if (data.hasKey("database", "name") != 0) { exit(1) }
    if (data.get("database", "name") != "") { exit(1) }

    // keys() should not include removed key
    const dbKeys2 = data.keys("database")
    let foundRemoved = 0
    let ki = 0
    while (ki < dbKeys2.length()) {
        if (dbKeys2[ki] == "name") { foundRemoved = 1 }
        ki = ki + 1
    }
    if (foundRemoved != 0) { exit(1) }

    // ── stringify ────────────────────────────────────────────
    const cfg = Ini.create()
    cfg.set("app", "name", "myapp")
    cfg.set("app", "version", "1.0")
    cfg.set("db", "host", "localhost")
    const output = Ini.stringify(cfg)
    // Should contain section headers and key-value pairs
    if (output.includes("[app]") == 0) { exit(1) }
    if (output.includes("name = myapp") == 0) { exit(1) }
    if (output.includes("[db]") == 0) { exit(1) }
    if (output.includes("host = localhost") == 0) { exit(1) }

    // ── Round-trip: parse → stringify → parse ────────────────
    const original = "[alpha]\nfoo = bar\nbaz = qux\n\n[beta]\nx = 1\ny = 2\n"
    const parsed = Ini.parse(original)
    const serialized = Ini.stringify(parsed)
    const reparsed = Ini.parse(serialized)
    if (reparsed.get("alpha", "foo") != "bar") { exit(1) }
    if (reparsed.get("alpha", "baz") != "qux") { exit(1) }
    if (reparsed.get("beta", "x") != "1") { exit(1) }
    if (reparsed.get("beta", "y") != "2") { exit(1) }

    // ── Create empty and build ───────────────────────────────
    const empty = Ini.create()
    if (empty.sections().length() != 0) { exit(1) }
    empty.set("new", "key", "val")
    if (empty.get("new", "key") != "val") { exit(1) }

    println("all ini tests passed")
}
