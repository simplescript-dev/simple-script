// I020b — Typed Map<K,double>.get value 类型 double-specific bitcast lowering.
// RED → GREEN 锚:before-fix `let m: Map<string,double> = new Map(); m.set("k", 3.14); m.get("k")`
// inferType 返 i64 fallback,mapSet 侧 `bitcast double→i64` 存入,mapGet 无反向 bitcast
// → stdout `4614253070214989087`(3.14 的 IEEE-754 位模式 0x40091EB851EB851F)直泄露;
// 跨函数 f(v: double) 调用时 IR emit `call double @f(i64 ...)` 类型 mismatch。
// After-fix:inferType 按 V=double 返 "double" + codegen `bitcast i64 to double` 静态反向 cast,
// mapSet/mapGet bitcast 双向对称,IR 全程 double 对齐。
//
// 覆盖 I019 §v0 scope §留下轮 "Map<K,double>.get → double(需 bitcast i64 to double)" 单根因
// 在 V=double 动作面。骨架对称 I020a V=int 路径 A。

import { assertEqual } from "@/lib/test"

function addOne(n: double): double { return n + 1.0 }

function main() {
    test("typed Map<string,double>.get returns double value — I020b GREEN", () => {
        // 3.14 / 2.71 bit-preserving 自洽:mapSet bitcast double→i64 + mapGet bitcast i64→double
        // bit pattern 双向对称,actual 与 literal 同 bit 即 ==。
        const m: Map<string, double> = new Map()
        m.set("pi", 3.14)
        m.set("e", 2.71)
        assertEqual(m.get("pi"), 3.14)
        assertEqual(m.get("e"), 2.71)
    })

    test("typed Map<string,double>.get cross-function signature — double contract aligned", () => {
        // 精确二进制 double(0.5 = 2^-1 / 1.5 = 1 + 2^-1)避开 fp round-to-nearest 累积误差,
        // 只验签名对齐(IR emit `call double @addOne(double ...)` 非 `(i64 ...)`)。
        const m: Map<string, double> = new Map()
        m.set("k", 0.5)
        const v: double = m.get("k")
        assertEqual(addOne(v), 1.5)
        assertEqual(addOne(m.get("k")), 1.5)
    })

    test("typed Map<string,double>.get miss returns 0.0 (IEEE-754 bit 0 = +0.0)", () => {
        const m: Map<string, double> = new Map()
        m.set("present", 1.5)
        // ss_mapGet miss 返 i64 0, bitcast i64 0 to double = +0.0(IEEE-754 规格)
        assertEqual(m.get("absent"), 0.0)
    })

    test("I020a regression — typed Map<string,int>.get still truncs i64→i32", () => {
        const im: Map<string, int> = new Map()
        im.set("answer", 42)
        assertEqual(im.get("answer"), 42)
    })

    test("I019 regression — typed Map<string,string>.get still routes ss_mapGetString", () => {
        const sm: Map<string, string> = new Map()
        sm.set("hi", "world")
        assertEqual(sm.get("hi"), "world")
    })
}
