// D127 §A.3 I001 验收 — annotation 命名参 ASSIGN 单形(COLON 已废)
// 对齐 Java @RequestMapping(value = "/x", method = RequestMethod.GET)

import { assertEqual } from "@/lib/test"

@Foo(a = "x", b = "y")
class Bar { n: int }

@Single(k = "only")
class S { n: int }

function main() {
    test("D127 §A.3 — 两命名参 ASSIGN", () => {
        const r = comptime {
            let acc = ""
            for (a in Bar.annotations) {
                acc = a.args.get("a") + "|" + a.args.get("b")
            }
            return acc
        }
        assertEqual(r, "x|y")
    })
    test("D127 §A.3 — 单命名参 ASSIGN", () => {
        const r = comptime {
            let acc = ""
            for (a in S.annotations) { acc = a.args.get("k") }
            return acc
        }
        assertEqual(r, "only")
    })
}
