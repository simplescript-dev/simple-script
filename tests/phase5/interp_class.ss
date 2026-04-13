import { assertEqual } from "@/lib/test"
import { classFields } from "@/bootstrap/interp_stubs"
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
    // ── basic class creation ───────────────────────────────
    test("class: new with named args", (): void => {
        run("class Dog {\nname: string\nage: int\n}\nlet d = new Dog(name: \"Buddy\", age: 3)\nlet n = d.name\nlet a = d.age")
        assertEqual(interpAsStr(interpGetVar("n")), "Buddy")
        assertEqual(interpAsInt(interpGetVar("a")), 3)
    })

    test("class: new with positional args", (): void => {
        run("class Point {\nx: int\ny: int\n}\nlet p = new Point(10, 20)\nlet x = p.x\nlet y = p.y")
        assertEqual(interpAsInt(interpGetVar("x")), 10)
        assertEqual(interpAsInt(interpGetVar("y")), 20)
    })

    test("class: no fields", (): void => {
        run("class Marker {\n}\nlet m = new Marker()\nlet t = 42")
        assertEqual(interpAsInt(interpGetVar("t")), 42)
    })

    test("class: field defaults", (): void => {
        run("class Config {\ndebug: int = 0\nname: string = \"default\"\n}\nlet c = new Config()\nlet d = c.debug\nlet n = c.name")
        assertEqual(interpAsInt(interpGetVar("d")), 0)
        assertEqual(interpAsStr(interpGetVar("n")), "default")
    })

    test("class: default overridden", (): void => {
        run("class Config {\nname: string = \"default\"\n}\nlet c = new Config(name: \"custom\")\nlet n = c.name")
        assertEqual(interpAsStr(interpGetVar("n")), "custom")
    })

    // ── field assignment ───────────────────────────────────
    test("class: field assignment", (): void => {
        run("class Box {\nvalue: int\n}\nlet b = new Box(value: 0)\nb.value = 42\nlet v = b.value")
        assertEqual(interpAsInt(interpGetVar("v")), 42)
    })

    test("class: compound field assignment", (): void => {
        run("class Counter {\ncount: int\n}\nlet c = new Counter(count: 10)\nc.count += 5\nlet x = c.count")
        assertEqual(interpAsInt(interpGetVar("x")), 15)
    })

    // ── method calls ──────────────────────────────────────
    test("class: method returning value", (): void => {
        run("class Dog {\nname: string\nfunction greet(): string { return this.name }\n}\nlet d = new Dog(name: \"Rex\")\nlet g = d.greet()")
        assertEqual(interpAsStr(interpGetVar("g")), "Rex")
    })

    test("class: method with parameters", (): void => {
        run("class Calc {\nfunction add(a: int, b: int): int { return a + b }\n}\nlet c = new Calc()\nlet r = c.add(3, 4)")
        assertEqual(interpAsInt(interpGetVar("r")), 7)
    })

    test("class: method modifying fields", (): void => {
        run("class Counter {\ncount: int\nfunction inc() { this.count = this.count + 1 }\n}\nlet c = new Counter(count: 0)\nc.inc()\nc.inc()\nc.inc()\nlet x = c.count")
        assertEqual(interpAsInt(interpGetVar("x")), 3)
    })

    test("class: method calling method", (): void => {
        run("class Calc {\nfunction twice(n: int): int { return n * 2 }\nfunction quad(n: int): int { return this.twice(this.twice(n)) }\n}\nlet c = new Calc()\nlet r = c.quad(3)")
        assertEqual(interpAsInt(interpGetVar("r")), 12)
    })

    // ── this keyword ──────────────────────────────────────
    test("class: this field mutation", (): void => {
        run("class Acc {\ntotal: int\nfunction add(n: int) { this.total = this.total + n }\n}\nlet a = new Acc(total: 0)\na.add(10)\na.add(20)\nlet t = a.total")
        assertEqual(interpAsInt(interpGetVar("t")), 30)
    })

    // ── inheritance ───────────────────────────────────────
    test("class: inherited fields", (): void => {
        run("class Animal {\nname: string\n}\nclass Dog extends Animal {\nbreed: string\n}\nlet d = new Dog(name: \"Buddy\", breed: \"Lab\")\nlet n = d.name\nlet b = d.breed")
        assertEqual(interpAsStr(interpGetVar("n")), "Buddy")
        assertEqual(interpAsStr(interpGetVar("b")), "Lab")
    })

    test("class: inherited methods", (): void => {
        run("class Animal {\nname: string\nfunction getName(): string { return this.name }\n}\nclass Dog extends Animal {\nbreed: string\n}\nlet d = new Dog(name: \"Rex\", breed: \"Poodle\")\nlet n = d.getName()")
        assertEqual(interpAsStr(interpGetVar("n")), "Rex")
    })

    test("class: method override", (): void => {
        run("class Animal {\nfunction speak(): string { return \"...\" }\n}\nclass Dog extends Animal {\nfunction speak(): string { return \"Woof\" }\n}\nlet d = new Dog()\nlet s = d.speak()")
        assertEqual(interpAsStr(interpGetVar("s")), "Woof")
    })

    test("class: parent method not overridden", (): void => {
        run("class Base {\nfunction hello(): string { return \"hi\" }\n}\nclass Child extends Base {\nfunction world(): string { return \"world\" }\n}\nlet c = new Child()\nlet h = c.hello()\nlet w = c.world()")
        assertEqual(interpAsStr(interpGetVar("h")), "hi")
        assertEqual(interpAsStr(interpGetVar("w")), "world")
    })

    // ── multiple objects ──────────────────────────────────
    test("class: multiple objects independent", (): void => {
        run("class Box {\nval: int\n}\nlet a = new Box(val: 1)\nlet b = new Box(val: 2)\na.val = 99\nlet av = a.val\nlet bv = b.val")
        assertEqual(interpAsInt(interpGetVar("av")), 99)
        assertEqual(interpAsInt(interpGetVar("bv")), 2)
    })

    test("class: objects in expressions", (): void => {
        run("class Point {\nx: int\ny: int\n}\nlet a = new Point(x: 1, y: 2)\nlet b = new Point(x: 10, y: 20)\nlet sum = a.x + b.y")
        assertEqual(interpAsInt(interpGetVar("sum")), 21)
    })
}
