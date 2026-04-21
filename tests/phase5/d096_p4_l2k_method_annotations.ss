// D096 Phase 4 L2κ — 方法级注解反射
// for (a in m.annotations) 在 @methodOf 内 unroll 方法头部注解名。
// 覆盖:(a) 单注解 (b) 多注解 (c) 无注解方法(空 CSV) (d) handler
// 自生成方法(无注解)。
// 注:accessor (get/set 同名)本阶段按 key=`Cls.name` 聚合,get 与 set
// 的 annotation 共享 key,区分留待后续阶段(需 method 索引 sidecar)。

import { assertEqual } from "@/lib/test"

function ListMethodAnnotations(cls: string) {
    @methodOf(cls) function listAll(): string {
        let acc = ""
        for (m in cls.methods) {
            acc = acc + m.name + ":"
            for (a in m.annotations) {
                acc = acc + a.name + ";"
            }
            acc = acc + "|"
        }
        return acc
    }
}

@ListMethodAnnotations
class Svc {
    x: int
    @Log function foo(): int { return 1 }
    @Cache @Log function bar(): int { return 2 }
    function plain(): int { return 3 }
}

function main() {
    test("L2κ — 单注解 + 多注解 + 无注解", () => {
        const s = new Svc(x: 0)
        // foo: @Log → "Log;"
        // bar: @Cache @Log → "Cache;Log;"
        // plain: 无 → ""
        // listAll: handler 自生成 → 无注解
        assertEqual(s.listAll(), "foo:Log;|bar:Cache;Log;|plain:|listAll:|")
    })
}
