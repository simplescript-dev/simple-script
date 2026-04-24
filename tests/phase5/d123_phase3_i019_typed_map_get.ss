// I019 — Map<K,V>.get value type inference(v0: string value).
// RED → GREEN 锚:before-fix `let m: Map<string,string> = new Map(); m.set("k","v"); m.get("k")`
// 返 i64 地址数字,concat "got:" + m.get("k") 打印 "got:<addr>" 而非 "got:v"。
// After-fix:inferType METHOD_CALL Map.get 按 generic value arg 返 string + codegen 路由
// ss_mapGetString → `m.get("k") == "v"` byte-equal,`"got:" + m.get("k") == "got:v"`。
//
// 覆盖 I018 §风险 §下轮升根路径 "Map<K,V>.get value 类型推断缺口" 根因闭环。

import { assertEqual } from "@/lib/test"

function main() {
    test("typed Map<string,string>.get returns string value — I019 GREEN", () => {
        const m: Map<string, string> = new Map()
        m.set("k", "v")
        assertEqual(m.get("k"), "v")
        assertEqual("got:" + m.get("k"), "got:v")
    })

    test("typed Map<string,string>.get miss returns empty string (ss_mapGetString semantics)", () => {
        const m: Map<string, string> = new Map()
        m.set("present", "yes")
        assertEqual("x:" + m.get("missing") + ":y", "x::y")
    })

    test("Controller-style req map concat — I019 parity 对齐 Java req.get", () => {
        const req: Map<string, string> = new Map()
        req.set("name", "SS")
        assertEqual("Hello, " + req.get("name") + "!", "Hello, SS!")
    })
}
