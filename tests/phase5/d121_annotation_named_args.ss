// D121 R1-A Execute 2 — AnnotationMeta.args: Map<string, string>
// + value kind 通用化(STRING/INT/TRUE/FALSE/DOUBLE/MEMBER_ACCESS enum)
// + R2-B parser ASSIGN `=` 等同 COLON `:` NAMED_ARG(范围限 annotation)
// + Map for-in comptime iterate values(兼容 d097 / d096_p4_l2h 旧 test)

import { assertEqual } from "@/lib/test"

enum HttpMethod {
    Get = "GET",
    Post = "POST"
}

@M1("positional-single")
class P1 { x: int }

@M2("a", "b", "c")
class P2 { x: int }

@M3(key: "via-colon")
class P3 { x: int }

@M4(key = "via-assign", k2 = "second")
class P4 { x: int }

@M5(n = 42, flag = true)
class P5 { x: int }

@M6(method = HttpMethod.Get, path: "/api/search")
class P6 { x: int }

function main() {
    test("D121 R1-A — positional single → value", () => {
        const r = comptime {
            let acc = ""
            for (a in P1.annotations) { acc = a.args.get("value") }
            return acc
        }
        assertEqual(r, "positional-single")
    })
    test("D121 R1-A — positional multi → 0/1/2", () => {
        const r = comptime {
            let acc = ""
            for (a in P2.annotations) {
                acc = a.args.get("0") + "|" + a.args.get("1") + "|" + a.args.get("2")
            }
            return acc
        }
        assertEqual(r, "a|b|c")
    })
    test("D121 R2-A COLON — named via :", () => {
        const r = comptime {
            let acc = ""
            for (a in P3.annotations) { acc = a.args.get("key") }
            return acc
        }
        assertEqual(r, "via-colon")
    })
    test("D121 R2-B ASSIGN — named via =", () => {
        const r = comptime {
            let acc = ""
            for (a in P4.annotations) {
                acc = a.args.get("key") + "|" + a.args.get("k2")
            }
            return acc
        }
        assertEqual(r, "via-assign|second")
    })
    test("D121 — INT/BOOL value generalization", () => {
        const r = comptime {
            let acc = ""
            for (a in P5.annotations) {
                acc = a.args.get("n") + "|" + a.args.get("flag")
            }
            return acc
        }
        assertEqual(r, "42|true")
    })
    test("D121 — enum MEMBER_ACCESS value (Spring Boot path)", () => {
        const r = comptime {
            let acc = ""
            for (a in P6.annotations) {
                acc = a.args.get("method") + "|" + a.args.get("path")
            }
            return acc
        }
        assertEqual(r, "GET|/api/search")
    })
    test("D121 — Map for-in values iteration (d097/d096 兼容镜像)", () => {
        const r = comptime {
            let acc = ""
            for (a in P2.annotations) {
                for (v in a.args) {
                    acc = acc + v + ";"
                }
            }
            return acc
        }
        assertEqual(r, "a;b;c;")
    })
}
