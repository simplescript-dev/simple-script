import { assertEqual } from "@/lib/test"
import { tokenize } from "@/bootstrap/lexer"
import { parse, nGetList } from "@/bootstrap/parser"
import { interpExec, interpReset, interpPushScope, interpType, interpAsInt, interpAsStr, interpGetVar, interpGetReturnFlag, interpGetReturnVal } from "@/bootstrap/interp"

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
    // ── if/else ──────────────────────────────────────────────
    test("if true branch", (): void => {
        run("let x = 0\nif (true) { x = 1 }")
        assertEqual(interpAsInt(interpGetVar("x")), 1)
    })

    test("if false branch", (): void => {
        run("let x = 0\nif (false) { x = 1 }")
        assertEqual(interpAsInt(interpGetVar("x")), 0)
    })

    test("if-else", (): void => {
        run("let x = 0\nif (false) { x = 1 } else { x = 2 }")
        assertEqual(interpAsInt(interpGetVar("x")), 2)
    })

    test("nested if", (): void => {
        run("let x = 0\nif (true) { if (true) { x = 42 } }")
        assertEqual(interpAsInt(interpGetVar("x")), 42)
    })

    // ── while ────────────────────────────────────────────────
    test("while loop sum", (): void => {
        run("let sum = 0\nlet i = 0\nwhile (i < 5) { sum = sum + i\ni = i + 1 }")
        assertEqual(interpAsInt(interpGetVar("sum")), 10)
    })

    // ── for loop ─────────────────────────────────────────────
    test("for loop sum", (): void => {
        run("let sum = 0\nfor (let i = 1; i <= 5; i++) { sum = sum + i }")
        assertEqual(interpAsInt(interpGetVar("sum")), 15)
    })

    test("for loop with compound assign", (): void => {
        run("let sum = 0\nfor (let i = 0; i < 3; i++) { sum += 10 }")
        assertEqual(interpAsInt(interpGetVar("sum")), 30)
    })

    // ── do-while ─────────────────────────────────────────────
    test("do-while executes at least once", (): void => {
        run("let x = 0\ndo { x = x + 1 } while (false)")
        assertEqual(interpAsInt(interpGetVar("x")), 1)
    })

    test("do-while loop", (): void => {
        run("let x = 0\ndo { x = x + 1 } while (x < 3)")
        assertEqual(interpAsInt(interpGetVar("x")), 3)
    })

    // ── break ────────────────────────────────────────────────
    test("break exits loop", (): void => {
        run("let x = 0\nwhile (true) { x = x + 1\nif (x == 3) { break } }")
        assertEqual(interpAsInt(interpGetVar("x")), 3)
    })

    test("break in for loop", (): void => {
        run("let last = 0\nfor (let i = 0; i < 100; i++) { if (i == 5) { break }\nlast = i }")
        assertEqual(interpAsInt(interpGetVar("last")), 4)
    })

    // ── continue ─────────────────────────────────────────────
    test("continue skips iteration", (): void => {
        run("let sum = 0\nfor (let i = 0; i < 5; i++) { if (i == 2) { continue }\nsum = sum + i }")
        assertEqual(interpAsInt(interpGetVar("sum")), 8)
    })

    // ── return ───────────────────────────────────────────────
    test("return stops execution", (): void => {
        run("let x = 1\nif (true) { x = 2\nreturn\nx = 3 }")
        assertEqual(interpAsInt(interpGetVar("x")), 2)
        assertEqual(interpGetReturnFlag(), 1)
    })

    test("return with value", (): void => {
        run("if (true) { return 42 }")
        assertEqual(interpGetReturnFlag(), 1)
        assertEqual(interpAsInt(interpGetReturnVal()), 42)
    })

    // ── assignment ───────────────────────────────────────────
    test("simple reassignment", (): void => {
        run("let x = 1\nx = 5")
        assertEqual(interpAsInt(interpGetVar("x")), 5)
    })

    test("compound +=", (): void => {
        run("let x = 10\nx += 5")
        assertEqual(interpAsInt(interpGetVar("x")), 15)
    })

    test("compound -=", (): void => {
        run("let x = 10\nx -= 3")
        assertEqual(interpAsInt(interpGetVar("x")), 7)
    })

    test("compound *=", (): void => {
        run("let x = 4\nx *= 3")
        assertEqual(interpAsInt(interpGetVar("x")), 12)
    })

    test("compound /=", (): void => {
        run("let x = 20\nx /= 4")
        assertEqual(interpAsInt(interpGetVar("x")), 5)
    })

    test("compound %=", (): void => {
        run("let x = 10\nx %= 3")
        assertEqual(interpAsInt(interpGetVar("x")), 1)
    })

    test("string +=", (): void => {
        run("let s = \"hello\"\ns += \" world\"")
        assertEqual(interpAsStr(interpGetVar("s")), "hello world")
    })

    // ── postfix inc/dec ──────────────────────────────────────
    test("postfix increment", (): void => {
        run("let x = 5\nx++")
        assertEqual(interpAsInt(interpGetVar("x")), 6)
    })

    test("postfix decrement", (): void => {
        run("let x = 5\nx--")
        assertEqual(interpAsInt(interpGetVar("x")), 4)
    })

    // ── for-in with array ────────────────────────────────────
    test("for-in over array", (): void => {
        run("let sum = 0\nconst arr = [10, 20, 30]\nfor (x in arr) { sum = sum + x }")
        assertEqual(interpAsInt(interpGetVar("sum")), 60)
    })

    test("for-in with break", (): void => {
        run("let sum = 0\nconst arr = [1, 2, 3, 4, 5]\nfor (x in arr) { if (x == 3) { break }\nsum = sum + x }")
        assertEqual(interpAsInt(interpGetVar("sum")), 3)
    })

    // ── array literal + index ────────────────────────────────
    test("array literal and index access", (): void => {
        run("const arr = [10, 20, 30]\nlet x = arr[1]")
        assertEqual(interpAsInt(interpGetVar("x")), 20)
    })

    test("array index assign", (): void => {
        run("let arr = [1, 2, 3]\narr[1] = 99\nlet x = arr[1]")
        assertEqual(interpAsInt(interpGetVar("x")), 99)
    })

    // ── nested control flow ──────────────────────────────────
    test("nested loops with break", (): void => {
        run("let count = 0\nfor (let i = 0; i < 3; i++) { for (let j = 0; j < 3; j++) { if (j == 2) { break }\ncount = count + 1 } }")
        assertEqual(interpAsInt(interpGetVar("count")), 6)
    })

    test("while with continue and break", (): void => {
        run("let sum = 0\nlet i = 0\nwhile (i < 10) { i = i + 1\nif (i % 2 == 0) { continue }\nif (i > 7) { break }\nsum = sum + i }")
        assertEqual(interpAsInt(interpGetVar("sum")), 16)
    })
}
