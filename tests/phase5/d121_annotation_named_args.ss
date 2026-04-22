// D121 R1-A Execute 2 — annotation args Map 通用化(STRING/INT/TRUE/FALSE/DOUBLE/MEMBER_ACCESS enum)
// D127 §A.3 parser ASSIGN 单形(COLON 已废,双形违反 feedback_dual_entry_is_dual_track)
// D127 §A.1 I003 — args value 存 AstNodeId,typed getter `getString/getInt/getBool` 走 evalAnnotationArg
// 保留原生类型;`keys()` + typed getter 代替原 `for (v in a.args)` values 迭代

import { assertEqual } from "@/lib/test"

enum HttpMethod {
    Get = "GET",
    Post = "POST"
}

@M1("positional-single")
class P1 { x: int }

@M2("a", "b", "c")
class P2 { x: int }

@M4(key = "via-assign", k2 = "second")
class P4 { x: int }

@M5(n = 42, flag = true)
class P5 { x: int }

@M6(method = HttpMethod.Get, path = "/api/search")
class P6 { x: int }

function main() {
    test("D121 R1-A — positional single → value", () => {
        const r = comptime {
            let acc = ""
            for (a in P1.annotations) { acc = a.args.getString("value") }
            return acc
        }
        assertEqual(r, "positional-single")
    })
    test("D121 R1-A — positional multi → 0/1/2", () => {
        const r = comptime {
            let acc = ""
            for (a in P2.annotations) {
                acc = a.args.getString("0") + "|" + a.args.getString("1") + "|" + a.args.getString("2")
            }
            return acc
        }
        assertEqual(r, "a|b|c")
    })
    test("D127 §A.3 ASSIGN — named via =", () => {
        const r = comptime {
            let acc = ""
            for (a in P4.annotations) {
                acc = a.args.getString("key") + "|" + a.args.getString("k2")
            }
            return acc
        }
        assertEqual(r, "via-assign|second")
    })
    test("D127 §A.1 I003 — INT/BOOL 类型保真(typed getter)", () => {
        const r = comptime {
            let acc = ""
            for (a in P5.annotations) {
                acc = `${a.args.getInt("n")}|${a.args.getBool("flag")}`
            }
            return acc
        }
        assertEqual(r, "42|true")
    })
    test("D121 — enum MEMBER_ACCESS value (Spring Boot path)", () => {
        const r = comptime {
            let acc = ""
            for (a in P6.annotations) {
                acc = a.args.getString("method") + "|" + a.args.getString("path")
            }
            return acc
        }
        assertEqual(r, "GET|/api/search")
    })
    test("D127 §A.1 I003 — keys() + getString 迭代(d097/d096 兼容镜像)", () => {
        const r = comptime {
            let acc = ""
            for (a in P2.annotations) {
                for (k in a.args.keys()) {
                    acc = acc + a.args.getString(k) + ";"
                }
            }
            return acc
        }
        assertEqual(r, "a;b;c;")
    })
}
