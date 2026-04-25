// I020c — Typed Map<K,ClassName>.get value 类型 inttoptr + RC retain + D067 null safety lowering.
// RED → GREEN 锚:before-fix `let m: Map<string,User> = new Map(); m.set("k", alice); m.get("k").name`
// inferType 返 i64 fallback,后续 `if (u != null)` icmp 把 i32 与 ptr null 比 → llc error
// `null must be a pointer type` 编译直接拒;narrow 后字段访问 ss_int_to_string(i32 %N) 二次撞错。
// After-fix:inferType 按 V=class 返 "ClassName?" + codegen `inttoptr i64 to ptr` +
// emitRetainForType (双 RC 统一分派,V=class 自动选 ss_retain;ss_retain 内置 isnull guard
// miss 路径 retain no-op),D067 既有 T? narrow 机制 (`if (u != null)` then-branch 视作非空) 复用。
//
// 覆盖 I019 §v0 scope §留下轮 "Map<K,ClassName>.get → ClassName?(需 inttoptr + 条件 retain +
// null safety 三件闭环)" 单根因在 V=class 动作面。骨架对称 I020a/I020b 但叠加 RC + nullability。

import { assertEqual } from "@/lib/test"

class User {
    name: string = ""
    age: int = 0
}

function getUser(m: Map<string, User>, k: string): User? {
    return m.get(k)
}

function main() {
    test("typed Map<string,User>.get hit + miss narrow — I020c GREEN", () => {
        const m: Map<string, User> = new Map()
        const alice = new User()
        alice.name = "alice"
        alice.age = 30
        m.set("k", alice)
        const u = m.get("k")
        if (u == null) { throw("hit branch: u null") }
        assertEqual(u.name, "alice")
        assertEqual(u.age, 30)
        const u2 = m.get("missing")
        if (u2 != null) { throw("miss branch: u2 not null") }
    })

    test("cross-function Map<string,User>.get returns User? signature aligned", () => {
        const m: Map<string, User> = new Map()
        const alice = new User()
        alice.name = "alice"
        m.set("k", alice)
        const u = getUser(m, "k")
        if (u == null) { throw("getUser: u null") }
        assertEqual(u.name, "alice")
        const u2 = getUser(m, "missing")
        if (u2 != null) { throw("getUser miss: u2 not null") }
    })

    test("RC retain symmetry — multiple gets stable no double-free", () => {
        const m: Map<string, User> = new Map()
        const a = new User()
        a.name = "alice"
        const b = new User()
        b.name = "bob"
        m.set("a", a)
        m.set("b", b)
        const u1 = m.get("a")
        const u2 = m.get("a")
        const u3 = m.get("b")
        if (u1 == null) { throw("u1 null") }
        if (u2 == null) { throw("u2 null") }
        if (u3 == null) { throw("u3 null") }
        assertEqual(u1.name, "alice")
        assertEqual(u2.name, "alice")
        assertEqual(u3.name, "bob")
    })

    test("I020b regression — typed Map<string,double>.get still bitcasts i64→double", () => {
        const dm: Map<string, double> = new Map()
        dm.set("k", 0.5)
        assertEqual(dm.get("k"), 0.5)
    })

    test("I020a regression — typed Map<string,int>.get still truncs i64→i32", () => {
        const im: Map<string, int> = new Map()
        im.set("k", 42)
        assertEqual(im.get("k"), 42)
    })

    test("I019 regression — typed Map<string,string>.get still routes ss_mapGetString", () => {
        const sm: Map<string, string> = new Map()
        sm.set("k", "world")
        assertEqual(sm.get("k"), "world")
    })
}
