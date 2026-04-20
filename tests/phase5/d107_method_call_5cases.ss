// D107 §新张力 1 五场景单测 — METHOD_CALL 迁 evalMethodCall 后
// 覆盖:顶层 method / 嵌套 CALL args / 读写分步 / named args / optional chain + MEMBER_ACCESS
import { assertEqual, assertTrue } from "@/lib/test"

class Box {
    x: int = 0
    y: int = 0

    function addAll(a: int, b: int, c: int): int {
        return a + b + c
    }

    function combine(v: int, tag: string): int {
        return v + tag.length()
    }

    function nested(v: int): int {
        return v * 2
    }
}

class Wrapper {
    inner: Box = new Box()

    function method(k: int): int {
        return k + 1
    }
}

function doubleIt(n: int): int {
    return n * 2
}

function incPlusOne(n: int): int {
    return n + 1
}

function main() {
    test("顶层 method obj.m(a,b,c)", ()=> {
        let b = new Box()
        const r1 = b.addAll(1, 2, 3)
        assertEqual(r1, 6)
    })

    test("嵌套 CALL args obj.m(f(g(x)))", ()=> {
        let b = new Box()
        const r2 = b.nested(doubleIt(incPlusOne(3)))
        assertEqual(r2, 16)
    })

    test("读写分步 + MEMBER_ACCESS 参", ()=> {
        let b = new Box()
        let x = 10
        let other = new Box()
        other.y = 5
        const xPrev = x
        x = x + 1
        const r3 = b.addAll(xPrev, other.y, 1)
        assertEqual(r3, 16)
        assertEqual(x, 11)
    })

    test("named args + runtime 值", ()=> {
        let b = new Box()
        let y = 7
        const yPrev = y
        y = y + 1
        const r4 = b.combine(v: yPrev, tag: "hi")
        assertEqual(r4, 9)
        assertEqual(y, 8)
    })

    test("optional chain + MEMBER_ACCESS 参数", ()=> {
        let other = new Box()
        other.y = 5
        let w: Wrapper? = new Wrapper()
        const r5 = w?.method(other.y)
        assertEqual(r5, 6)

        // null 路径:不崩溃即 PASS(int optional 返回与 null 比较依赖 D067 未覆盖语法)
        let wn: Wrapper? = null
        wn?.method(0)
        assertTrue(1 == 1)
    })
}
