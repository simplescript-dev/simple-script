// I020a — Typed Map<K,int>.get value 类型 int-specific cast lowering.
// RED → GREEN 锚:before-fix `let m: Map<string,int> = new Map(); m.set("k", 42); m.get("k")`
// inferType 返 i64 fallback,store i64 to i32 slot 类型层 RED;跨函数 f(n: int) 调用时
// IR emit `call i32 @f(i64 ...)` 类型 mismatch(stdout 巧合 GREEN 因 x86_64 ABI RDI 重叠)。
// After-fix:inferType 按 V=int 返 "int" + codegen `trunc i64 to i32` 静态 cast,IR 全程 i32 对齐。
//
// 覆盖 I019 §v0 scope §留下轮 "Map<K,int>.get → int(需 trunc i64 to i32 cast)" 单根因
// 在 V=int 动作面。骨架对称 I019 V=string 路径 A。

import { assertEqual } from "@/lib/test"

function addOne(n: int): int { return n + 1 }

function main() {
    test("typed Map<string,int>.get returns int value — I020a GREEN", () => {
        const m: Map<string, int> = new Map()
        m.set("answer", 42)
        m.set("year", 2026)
        assertEqual(m.get("answer"), 42)
        assertEqual(m.get("year"), 2026)
    })

    test("typed Map<string,int>.get cross-function signature — i32 contract aligned", () => {
        const m: Map<string, int> = new Map()
        m.set("k", 41)
        // before-fix: IR emit `call i32 @addOne(i64 ...)` — LLVM 类型 mismatch
        // after-fix: IR emit `call i32 @addOne(i32 ...)` — 类型对齐
        const v: int = m.get("k")
        assertEqual(addOne(v), 42)
        assertEqual(addOne(m.get("k")), 42)
    })

    test("typed Map<string,int>.get miss returns i32 0 (ss_mapGet semantics)", () => {
        const m: Map<string, int> = new Map()
        m.set("present", 99)
        assertEqual(m.get("absent"), 0)
    })

    test("I019 regression — typed Map<string,string>.get still routes ss_mapGetString", () => {
        const sm: Map<string, string> = new Map()
        sm.set("hi", "world")
        assertEqual(sm.get("hi"), "world")
        assertEqual("got:" + sm.get("hi"), "got:world")
    })

    test("untyped Map.get backward compat — methodRetTypes get→i64 fallback retained", () => {
        // untyped: declared type unknown, fallback path 走 ss_mapGet i64 (历史 backward compat)
        const um = new Map()
        um.set("k", 7)
        // untyped Map.get 返 i64,在 concat/println 上下文走 ss_i64_to_string,不影响 stdout
        assertEqual("v=" + um.get("k"), "v=7")
    })
}
