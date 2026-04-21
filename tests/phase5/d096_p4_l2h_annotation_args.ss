// D096 Phase 4 L2η — a.args 反射
// 嵌套循环 for (a in f.annotations) { for (v in a.args) } 在 @methodOf handler
// 里展开,v 依次取 annotation 的实参值。覆盖:(a) 无 args (b) 单 string arg
// (c) 多 string arg (d) 混合 string + int(D121 Execute 2 value kind 泛化)

import { assertEqual } from "@/lib/test"

function TagArgs(cls: string) {
    @methodOf(cls) function argsOf(): string {
        let acc = ""
        for (f in cls.fields) {
            for (a in f.annotations) {
                for (v in a.args) {
                    acc = acc + f.name + "@" + a.name + "(" + v + ");"
                }
            }
        }
        return acc
    }
}

@TagArgs
class C {
    @Deprecated x: int
    @Alias("alpha") y: string
    @Alias("a", "b", "c") z: int
}

@TagArgs
class D {
    @Mixed("keep", 42, "drop") p: int
    q: int
}

function main() {
    test("L2η — no args / single / multi", () => {
        const c = new C(x: 1, y: "hi", z: 2)
        // x: @Deprecated has no args → zero expansions
        // y: @Alias("alpha") → one expansion
        // z: @Alias("a","b","c") → three expansions
        assertEqual(c.argsOf(), "y@Alias(alpha);z@Alias(a);z@Alias(b);z@Alias(c);")
    })
    test("L2η — mixed string + int args", () => {
        const d = new D(p: 1, q: 2)
        // D121 Execute 2 value kind 泛化:INT/BOOL/enum 纳入字面化打印
        // @Mixed("keep", 42, "drop") → 三实参全部保留
        assertEqual(d.argsOf(), "p@Mixed(keep);p@Mixed(42);p@Mixed(drop);")
    })
}
