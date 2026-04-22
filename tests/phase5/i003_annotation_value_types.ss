// D127 §A.1 I003 — annotation args value 类型保真
// buildAnnotationMetaArray 存 AstNodeId(raw int),evalAnnotationArg 按 nKind 回解为 typed tv;
// Map.getString/getInt/getBool/getDouble 走 evalAnnotationArg。反 D121 R1-A 原字符串化:
// 以前 args.get("n") 返 "42"(string),消费侧丢类型;现在 args.getInt("n") 返 int 42,
// bool 同理。I004 扩 enum、I005 扩 array、I006 扩 class ref,本 test 覆盖 3 基础 kind。
//
// getDouble 分支在 evalAnnotationArg 已实装(DOUBLE_LIT → interpNewDouble),但 comptime
// materialize 侧 gen_types.ss:261 `interpAsStr(double_tv)` pre-existing bug(取 tvS1
// 而非 tvD1)阻断 `return double_tv` 路径,不在本 issue 范围;double 覆盖补 test 作后续。

import { assertEqual } from "@/lib/test"

@M(s = "hi", n = 42, flag = true)
class P { x: int }

function main() {
    test("I003 — getString 返回 string tv", () => {
        const r = comptime {
            let acc = ""
            for (a in P.annotations) { acc = a.args.getString("s") }
            return acc
        }
        assertEqual(r, "hi")
    })
    test("I003 — getInt 返回原生 int(int + int 走整数算术)", () => {
        const r = comptime {
            let acc = 0
            for (a in P.annotations) { acc = acc + a.args.getInt("n") }
            return acc
        }
        assertEqual(r, 42)
    })
    test("I003 — getBool 返回原生 bool(bool == true 成立)", () => {
        const r = comptime {
            let hit = 0
            for (a in P.annotations) {
                if (a.args.getBool("flag") == true) { hit = 1 }
            }
            return hit
        }
        assertEqual(r, 1)
    })
}
