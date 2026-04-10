import { assertEqual } from "@/lib/test"
import { tokenize } from "@/bootstrap/lexer"
import { parse, nGetList } from "@/bootstrap/parser"
import { interpExec, interpReset, interpPushScope, interpAsInt, interpAsStr, interpGetVar } from "@/bootstrap/interp"

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
    // ── basic function call ─────────────────────────────────
    test("function returning value", (): void => {
        run("function answer(): int { return 42 }\nlet x = answer()")
        assertEqual(interpAsInt(interpGetVar("x")), 42)
    })

    test("function with parameters", (): void => {
        run("function add(a: int, b: int): int { return a + b }\nlet x = add(3, 4)")
        assertEqual(interpAsInt(interpGetVar("x")), 7)
    })

    test("void function side effect", (): void => {
        run("let x = 0\nfunction inc() { x = x + 1 }\ninc()\ninc()\ninc()")
        assertEqual(interpAsInt(interpGetVar("x")), 3)
    })

    test("function as expression", (): void => {
        run("function twice(n: int): int { return n * 2 }\nfunction triple(n: int): int { return n * 3 }\nlet x = twice(5) + triple(3)")
        assertEqual(interpAsInt(interpGetVar("x")), 19)
    })

    // ── recursion ───────────────────────────────────────────
    test("recursive factorial", (): void => {
        run("function factorial(n: int): int {\nif (n <= 1) { return 1 }\nreturn n * factorial(n - 1)\n}\nlet x = factorial(5)")
        assertEqual(interpAsInt(interpGetVar("x")), 120)
    })

    test("recursive fibonacci", (): void => {
        run("function fib(n: int): int {\nif (n <= 0) { return 0 }\nif (n == 1) { return 1 }\nreturn fib(n - 1) + fib(n - 2)\n}\nlet x = fib(10)")
        assertEqual(interpAsInt(interpGetVar("x")), 55)
    })

    test("recursive sum", (): void => {
        run("function sum(n: int): int {\nif (n <= 0) { return 0 }\nreturn n + sum(n - 1)\n}\nlet x = sum(10)")
        assertEqual(interpAsInt(interpGetVar("x")), 55)
    })

    // ── default parameters ──────────────────────────────────
    test("default parameter used", (): void => {
        run("function greet(name: string = \"world\"): string { return name }\nlet x = greet()")
        assertEqual(interpAsStr(interpGetVar("x")), "world")
    })

    test("default parameter overridden", (): void => {
        run("function greet(name: string = \"world\"): string { return name }\nlet x = greet(\"Alice\")")
        assertEqual(interpAsStr(interpGetVar("x")), "Alice")
    })

    test("multiple defaults", (): void => {
        run("function add(a: int = 10, b: int = 20): int { return a + b }\nlet x = add()")
        assertEqual(interpAsInt(interpGetVar("x")), 30)
    })

    test("partial default parameters", (): void => {
        run("function add(a: int, b: int = 20): int { return a + b }\nlet x = add(5)")
        assertEqual(interpAsInt(interpGetVar("x")), 25)
    })

    // ── functions calling functions ──────────────────────────
    test("function calling function", (): void => {
        run("function square(n: int): int { return n * n }\nfunction sumOfSquares(a: int, b: int): int { return square(a) + square(b) }\nlet x = sumOfSquares(3, 4)")
        assertEqual(interpAsInt(interpGetVar("x")), 25)
    })

    test("chain of calls", (): void => {
        run("function a(): int { return b() + 1 }\nfunction b(): int { return c() + 1 }\nfunction c(): int { return 10 }\nlet x = a()")
        assertEqual(interpAsInt(interpGetVar("x")), 12)
    })

    // ── conditional return ──────────────────────────────────
    test("conditional return", (): void => {
        run("function abs(n: int): int {\nif (n < 0) { return 0 - n }\nreturn n\n}\nlet a = abs(5)\nlet b = abs(-3)")
        assertEqual(interpAsInt(interpGetVar("a")), 5)
        assertEqual(interpAsInt(interpGetVar("b")), 3)
    })

    // ── function with loop ──────────────────────────────────
    test("function with loop", (): void => {
        run("function sumTo(n: int): int {\nlet s = 0\nlet i = 1\nwhile (i <= n) { s = s + i\ni = i + 1 }\nreturn s\n}\nlet x = sumTo(100)")
        assertEqual(interpAsInt(interpGetVar("x")), 5050)
    })

    test("function with for loop", (): void => {
        run("function countDown(n: int): int {\nlet result = 0\nfor (let i = n; i > 0; i--) { result = result + i }\nreturn result\n}\nlet x = countDown(5)")
        assertEqual(interpAsInt(interpGetVar("x")), 15)
    })

    // ── string functions ────────────────────────────────────
    test("string concatenation in function", (): void => {
        run("function greet(name: string): string { return `hello ${name}` }\nlet x = greet(\"world\")")
        assertEqual(interpAsStr(interpGetVar("x")), "hello world")
    })
}
