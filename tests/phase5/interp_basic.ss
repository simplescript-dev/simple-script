import { assertEqual } from "@/lib/test"
import { tokenize } from "@/bootstrap/lexer"
import { parse, nGetList } from "@/bootstrap/parser"
import { interpExec, interpReset, interpPushScope, interpType, interpAsInt, interpAsStr, interpAsDouble, interpAsBool, interpGetVar } from "@/bootstrap/interp"

function main() {
    // Single tokenize+parse+execute, test everything in one shot
    interpReset()
    interpPushScope()

    tokenize("const a = 1 + 2\nconst b = 5 > 3\nconst c = \"hello\"\nconst d = true && false\nconst e = true || false\nconst f = !true\nconst g = true ? 1 : 2\nconst h = false ? 1 : 2\nconst i = null ?? 42\nconst j = 10 ?? 42\nconst k = -5\nconst l = \"count: \" + 42\nconst m = null == null\nconst n = 5 & 3\nconst o = 1 << 3\nconst p = 3.14\nconst q = 1.5 + 2.5\nconst r = 10\nconst s = r + 5\n")
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

    test("int arithmetic", (): void => {
        assertEqual(interpAsInt(interpGetVar("a")), 3)
    })

    test("comparison", (): void => {
        assertEqual(interpAsBool(interpGetVar("b")), 1)
    })

    test("string literal", (): void => {
        assertEqual(interpAsStr(interpGetVar("c")), "hello")
    })

    test("logical AND", (): void => {
        assertEqual(interpAsBool(interpGetVar("d")), 0)
    })

    test("logical OR", (): void => {
        assertEqual(interpAsBool(interpGetVar("e")), 1)
    })

    test("logical NOT", (): void => {
        assertEqual(interpAsBool(interpGetVar("f")), 0)
    })

    test("ternary true", (): void => {
        assertEqual(interpAsInt(interpGetVar("g")), 1)
    })

    test("ternary false", (): void => {
        assertEqual(interpAsInt(interpGetVar("h")), 2)
    })

    test("null coalescing null", (): void => {
        assertEqual(interpAsInt(interpGetVar("i")), 42)
    })

    test("null coalescing non-null", (): void => {
        assertEqual(interpAsInt(interpGetVar("j")), 10)
    })

    test("unary negation", (): void => {
        assertEqual(interpAsInt(interpGetVar("k")), -5)
    })

    test("string + int concat", (): void => {
        assertEqual(interpAsStr(interpGetVar("l")), "count: 42")
    })

    test("null equality", (): void => {
        assertEqual(interpAsBool(interpGetVar("m")), 1)
    })

    test("bitwise AND", (): void => {
        assertEqual(interpAsInt(interpGetVar("n")), 1)
    })

    test("left shift", (): void => {
        assertEqual(interpAsInt(interpGetVar("o")), 8)
    })

    test("double literal", (): void => {
        assertEqual(interpType(interpGetVar("p")), "double")
    })

    test("double addition", (): void => {
        assertEqual(interpType(interpGetVar("q")), "double")
    })

    test("variable lookup", (): void => {
        assertEqual(interpAsInt(interpGetVar("r")), 10)
        assertEqual(interpAsInt(interpGetVar("s")), 15)
    })
}
