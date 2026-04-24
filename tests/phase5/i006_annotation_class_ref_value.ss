// D127 §A.2 I006 — annotation IDENT 裸类名 → 类名 string
// 方案 A:`@Imp(target = MyConfig)` 中 MyConfig 作为 IDENT 在 annotation value
// 位置,comptime eval 查 interpClasses / classNodeIds,命中返类名字符串。未命中
// fall through 到原 comptimeError。与 I004 MEMBER_ACCESS enum 分支互补,在 IDENT
// scope 各司其职(enum 值通过 MEMBER_ACCESS 访问,裸 IDENT 只能是类名)。

import { assertEqual } from "@/lib/test"

class MyConfig { x: int }
class Database { host: string }

@Imp(target = MyConfig)
class App { y: int }

@Imp(target = Database, fallback = MyConfig)
class Service { z: int }

@Mix(cls = MyConfig, name = "literal-str")
class Holder { a: int }

function main() {
    test("I006 — IDENT 单类名 getString 返类名", () => {
        const s = comptime {
            let t = ""
            for (a in App.annotations) {
                if (a.args.has("target") == 1) { t = a.args.getString("target") }
            }
            return t
        }
        assertEqual(s, "MyConfig")
    })

    test("I006 — IDENT 多命名参各自返类名", () => {
        const s = comptime {
            let t = ""
            for (a in Service.annotations) {
                if (a.args.has("target") == 1) { t = t + a.args.getString("target") }
                if (a.args.has("fallback") == 1) { t = t + "|" + a.args.getString("fallback") }
            }
            return t
        }
        assertEqual(s, "Database|MyConfig")
    })

    test("I006 — IDENT 与 STRING_LIT 混用不冲突", () => {
        // 同一 annotation 混 IDENT 类引用 + STRING_LIT,证 IDENT 分支不破坏其他 kind
        const s = comptime {
            let t = ""
            for (a in Holder.annotations) {
                if (a.args.has("cls") == 1) { t = t + a.args.getString("cls") }
                if (a.args.has("name") == 1) { t = t + "-" + a.args.getString("name") }
            }
            return t
        }
        assertEqual(s, "MyConfig-literal-str")
    })
}
