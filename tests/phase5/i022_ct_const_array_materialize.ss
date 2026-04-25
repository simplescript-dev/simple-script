// I022 — ct const Array<UserClass> materialize 漏 push 第 2/3 元素回归测试
// before: runComptimeBlockBody 出口不 reset interpReturnFlag/Val,RETURN flag leak 到下游 ct unroll
//         interpCheckLoopExit 误判提前 break,只 emit 第一次 iter 的 IR
// fix at:  bootstrap/gen/stmts/stmts_core.ss:67-72 + stmts_loop_forin.ss:115/130 + gen_types.ss:260-263

import { assertEqual } from "@/lib/test"

class R { p: string }

const A: Array<int> = comptime {
    let arr: Array<int> = []
    arr = arr.push(10)
    arr = arr.push(20)
    arr = arr.push(30)
    return arr
}

const ROUTES: Array<R> = comptime {
    let arr: Array<R> = []
    arr = arr.push(new R(p: "/a"))
    arr = arr.push(new R(p: "/b"))
    arr = arr.push(new R(p: "/c"))
    return arr
}

const C: Array<int> = [100, 200, 300]

function main() {
    test("I022 ct const Array<int> for-in 三元素全 emit", () => {
        let acc = ""
        for (n in A) { acc = acc + n + "," }
        assertEqual(acc, "10,20,30,")
    })

    test("I022 ct const Array<UserClass> for-in 三元素全 emit", () => {
        let acc = ""
        for (r in ROUTES) { acc = acc + r.p + "," }
        assertEqual(acc, "/a,/b,/c,")
    })

    test("I022 top-level Array literal 不被 ct const itemName 残留污染", () => {
        let acc = ""
        for (n in C) { acc = acc + n + "," }
        assertEqual(acc, "100,200,300,")
    })

    test("I022 ct const length() ct 求值 = 3", () => {
        assertEqual(A.length(), 3)
        assertEqual(ROUTES.length(), 3)
        assertEqual(C.length(), 3)
    })
}
