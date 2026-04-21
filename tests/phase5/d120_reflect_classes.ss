// D120 Execute 1 Phase 1 — reflect.classes() comptime 全局类枚举。
// 在 comptime block 内迭代所有已声明 class 的 ClassMeta,字典序稳定输出;
// 依赖 stmts_loop_forin.ss 通用 ct-array unroll + exprs_ct_reflect.ss 工厂。

import { assertEqual } from "@/lib/test"

class Alpha { a: int }
class Beta  { b: int }
class Gamma { g: int }

function main() {
    test("D120 — reflect.classes() enumerates user classes in dictionary order", () => {
        const names = comptime {
            let acc = ""
            for (c in reflect.classes()) {
                if (c.name == "Alpha" || c.name == "Beta" || c.name == "Gamma") {
                    acc = acc + c.name + ";"
                }
            }
            return acc
        }
        assertEqual(names, "Alpha;Beta;Gamma;")
    })
}
