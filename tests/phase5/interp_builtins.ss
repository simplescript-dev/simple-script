import { assertEqual } from "@/lib/test"
import { tokenize } from "@/bootstrap/lexer"
import { parse, nGetList } from "@/bootstrap/parser"
import { interpExec, interpReset, interpPushScope, interpAsInt, interpAsStr, interpGetVar, interpType } from "@/bootstrap/interp"

function run(code: string) {
    interpReset()
    interpPushScope()
    tokenize(code)
    const root = parse("")
    const list = nGetList(root)
    if (list != "") {
        const stmts = list.split(",")
        let idx = 0
        while (idx < stmts.length()) {
            interpExec(parseInt(stmts[idx]))
            idx = idx + 1
        }
    }
}

function main() {
    // ── String methods ────────────────────────────────────
    test("string: length", (): void => {
        run("let r = \"hello\".length()")
        assertEqual(interpAsInt(interpGetVar("r")), 5)
    })

    test("string: split", (): void => {
        run("let parts = \"a,b,c\".split(\",\")\nlet len = parts.length()\nlet first = parts[0]\nlet last = parts[2]")
        assertEqual(interpAsInt(interpGetVar("len")), 3)
        assertEqual(interpAsStr(interpGetVar("first")), "a")
        assertEqual(interpAsStr(interpGetVar("last")), "c")
    })

    test("string: indexOf", (): void => {
        run("let r = \"hello world\".indexOf(\"world\")\nlet miss = \"hello\".indexOf(\"xyz\")")
        assertEqual(interpAsInt(interpGetVar("r")), 6)
        assertEqual(interpAsInt(interpGetVar("miss")), -1)
    })

    test("string: substring", (): void => {
        run("let r = \"hello\".substring(1, 3)")
        assertEqual(interpAsStr(interpGetVar("r")), "ell")
    })

    test("string: trim", (): void => {
        run("let r = \"  hello  \".trim()")
        assertEqual(interpAsStr(interpGetVar("r")), "hello")
    })

    test("string: replace", (): void => {
        run("let r = \"hello world\".replace(\"world\", \"SS\")")
        assertEqual(interpAsStr(interpGetVar("r")), "hello SS")
    })

    test("string: startsWith/endsWith", (): void => {
        run("let a = \"hello\".startsWith(\"hel\")\nlet b = \"hello\".endsWith(\"llo\")\nlet c = \"hello\".startsWith(\"xyz\")")
        assertEqual(interpAsInt(interpGetVar("a")), 1)
        assertEqual(interpAsInt(interpGetVar("b")), 1)
        assertEqual(interpAsInt(interpGetVar("c")), 0)
    })

    test("string: toUpperCase/toLowerCase", (): void => {
        run("let a = \"Hello\".toUpperCase()\nlet b = \"Hello\".toLowerCase()")
        assertEqual(interpAsStr(interpGetVar("a")), "HELLO")
        assertEqual(interpAsStr(interpGetVar("b")), "hello")
    })

    test("string: charAt", (): void => {
        run("let r = \"hello\".charAt(1)")
        assertEqual(interpAsStr(interpGetVar("r")), "e")
    })

    test("string: includes", (): void => {
        run("let a = \"hello world\".includes(\"world\")\nlet b = \"hello\".includes(\"xyz\")")
        assertEqual(interpAsInt(interpGetVar("a")), 1)
        assertEqual(interpAsInt(interpGetVar("b")), 0)
    })

    // ── Array methods ─────────────────────────────────────
    test("array: length", (): void => {
        run("let a = [10, 20, 30]\nlet r = a.length()\nlet e = []\nlet r2 = e.length()")
        assertEqual(interpAsInt(interpGetVar("r")), 3)
        assertEqual(interpAsInt(interpGetVar("r2")), 0)
    })

    test("array: push", (): void => {
        run("let a = [1, 2]\na.push(3)\nlet len = a.length()\nlet last = a[2]")
        assertEqual(interpAsInt(interpGetVar("len")), 3)
        assertEqual(interpAsInt(interpGetVar("last")), 3)
    })

    test("array: join", (): void => {
        run("let a = [1, 2, 3]\nlet r = a.join(\"-\")")
        assertEqual(interpAsStr(interpGetVar("r")), "1-2-3")
    })

    test("array: indexOf", (): void => {
        run("let a = [10, 20, 30]\nlet r = a.indexOf(20)\nlet miss = a.indexOf(99)")
        assertEqual(interpAsInt(interpGetVar("r")), 1)
        assertEqual(interpAsInt(interpGetVar("miss")), -1)
    })

    test("array: slice", (): void => {
        run("let a = [10, 20, 30, 40, 50]\nlet r = a.slice(1, 3)\nlet len = r.length()\nlet first = r[0]\nlet last = r[1]")
        assertEqual(interpAsInt(interpGetVar("len")), 2)
        assertEqual(interpAsInt(interpGetVar("first")), 20)
        assertEqual(interpAsInt(interpGetVar("last")), 30)
    })

    test("array: map with arrow", (): void => {
        run("let a = [1, 2, 3]\nlet r = a.map((x: int): int => x * 2)\nlet v0 = r[0]\nlet v1 = r[1]\nlet v2 = r[2]")
        assertEqual(interpAsInt(interpGetVar("v0")), 2)
        assertEqual(interpAsInt(interpGetVar("v1")), 4)
        assertEqual(interpAsInt(interpGetVar("v2")), 6)
    })

    test("array: filter with arrow", (): void => {
        run("let a = [1, 2, 3, 4, 5]\nlet r = a.filter((x: int): int => x > 2)\nlet len = r.length()\nlet v0 = r[0]")
        assertEqual(interpAsInt(interpGetVar("len")), 3)
        assertEqual(interpAsInt(interpGetVar("v0")), 3)
    })

    test("array: forEach with arrow", (): void => {
        run("let sum = 0\nlet a = [1, 2, 3]\na.forEach((x: int): void => {\nsum = sum + x\n})")
        assertEqual(interpAsInt(interpGetVar("sum")), 6)
    })

    test("array: reduce with arrow", (): void => {
        run("let a = [1, 2, 3, 4]\nlet r = a.reduce((acc: int, x: int): int => acc + x, 0)")
        assertEqual(interpAsInt(interpGetVar("r")), 10)
    })

    // ── Map methods ───────────────────────────────────────
    test("map: set/get/has/size", (): void => {
        run("let m = new Map()\nm.set(\"name\", \"Alice\")\nm.set(\"age\", \"30\")\nlet n = m.getString(\"name\")\nlet h = m.has(\"name\")\nlet miss = m.has(\"xyz\")\nlet sz = m.size()")
        assertEqual(interpAsStr(interpGetVar("n")), "Alice")
        assertEqual(interpAsInt(interpGetVar("h")), 1)
        assertEqual(interpAsInt(interpGetVar("miss")), 0)
        assertEqual(interpAsInt(interpGetVar("sz")), 2)
    })

    test("map: delete", (): void => {
        run("let m = new Map()\nm.set(\"a\", \"1\")\nm.set(\"b\", \"2\")\nm.delete(\"a\")\nlet h = m.has(\"a\")\nlet sz = m.size()")
        assertEqual(interpAsInt(interpGetVar("h")), 0)
        assertEqual(interpAsInt(interpGetVar("sz")), 1)
    })

    test("map: keys", (): void => {
        run("let m = new Map()\nm.set(\"x\", \"1\")\nm.set(\"y\", \"2\")\nlet ks = m.keys()\nlet len = ks.length()\nlet k0 = ks[0]\nlet k1 = ks[1]")
        assertEqual(interpAsInt(interpGetVar("len")), 2)
        assertEqual(interpAsStr(interpGetVar("k0")), "x")
        assertEqual(interpAsStr(interpGetVar("k1")), "y")
    })

    test("map: overwrite value", (): void => {
        run("let m = new Map()\nm.set(\"k\", \"old\")\nm.set(\"k\", \"new\")\nlet v = m.getString(\"k\")\nlet sz = m.size()")
        assertEqual(interpAsStr(interpGetVar("v")), "new")
        assertEqual(interpAsInt(interpGetVar("sz")), 1)
    })

    // ── Built-in functions ────────────────────────────────
    test("parseInt", (): void => {
        run("let r = parseInt(\"42\")")
        assertEqual(interpAsInt(interpGetVar("r")), 42)
    })

    test("parseDouble", (): void => {
        run("let r = parseDouble(\"3.14\")\nlet check = r > 3.0")
        assertEqual(interpAsInt(interpGetVar("check")), 1)
    })

    test("toString", (): void => {
        run("let r = toString(42)")
        assertEqual(interpAsStr(interpGetVar("r")), "42")
    })

    // ── Integration: string processing pipeline ───────────
    test("integration: split + map + join", (): void => {
        run("let csv = \"alice,bob,charlie\"\nlet names = csv.split(\",\")\nlet upper = names.map((s: string): string => s.toUpperCase())\nlet result = upper.join(\";\")")
        assertEqual(interpAsStr(interpGetVar("result")), "ALICE;BOB;CHARLIE")
    })

    test("integration: map as config store", (): void => {
        run("let config = new Map()\nconfig.set(\"host\", \"localhost\")\nconfig.set(\"port\", \"8080\")\nlet url = config.getString(\"host\") + \":\" + config.getString(\"port\")")
        assertEqual(interpAsStr(interpGetVar("url")), "localhost:8080")
    })
}
