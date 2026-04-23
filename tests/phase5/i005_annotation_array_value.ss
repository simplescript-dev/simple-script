// D127 §A.1 I005 — annotation ARRAY_LIT value 递归 eval
// 方案 A:Array<AstNodeId> 递归 eval,元素可为 STRING/INT/BOOL/DOUBLE/MEMBER_ACCESS(enum);
// 禁嵌套 array(Java annotation 对齐,见 I005 §备注)。getter 走 ctMapMethod getArray
// 返 array tv,消费侧 `.length()` / `[i]` 同普通 comptime array。

import { assertEqual } from "@/lib/test"

enum Method { GET, POST }

@Route(paths = ["/a", "/b", "/c"], ports = [80, 443], flags = [true, false])
class Api { x: int }

@Mixed(methods = [Method.GET, Method.POST])
class Mix { x: int }

function main() {
    test("I005 — getArray string 元素 length", () => {
        const n = comptime {
            let len = 0
            for (a in Api.annotations) {
                if (a.args.has("paths") == 1) { len = a.args.getArray("paths").length() }
            }
            return len
        }
        assertEqual(n, 3)
    })

    test("I005 — getArray string 元素 [0] 取值", () => {
        const s = comptime {
            let first = ""
            for (a in Api.annotations) {
                if (a.args.has("paths") == 1) {
                    const arr = a.args.getArray("paths")
                    first = arr[0]
                }
            }
            return first
        }
        assertEqual(s, "/a")
    })

    test("I005 — getArray int 元素 arr[0]+arr[1] 原生算术", () => {
        const n = comptime {
            let sum = 0
            for (a in Api.annotations) {
                if (a.args.has("ports") == 1) {
                    const arr = a.args.getArray("ports")
                    sum = arr[0] + arr[1]
                }
            }
            return sum
        }
        assertEqual(n, 523)
    })

    test("I005 — getArray bool 元素 == true / == false 判定", () => {
        const n = comptime {
            let tcount = 0
            for (a in Api.annotations) {
                if (a.args.has("flags") == 1) {
                    const arr = a.args.getArray("flags")
                    if (arr[0] == true) { tcount = tcount + 1 }
                    if (arr[1] == false) { tcount = tcount + 1 }
                }
            }
            return tcount
        }
        assertEqual(n, 2)
    })

    test("I005 — getArray 元素为 enum MEMBER_ACCESS(递归 eval)", () => {
        const s = comptime {
            let first = ""
            for (a in Mix.annotations) {
                if (a.args.has("methods") == 1) {
                    const arr = a.args.getArray("methods")
                    first = arr[0]
                }
            }
            return first
        }
        assertEqual(s, "GET")
    })
}
