// D096 Phase 4 L2ι — cls.methods 方法反射
// handler 内 for (m in cls.methods) 展开方法名。覆盖:(a) 多普通方法 +
// handler 自生成方法 (b) 无用户方法仅 handler 方法 (c) 带 get/set
// accessor 的类(accessor 名字也进 classMethods)。

import { assertEqual } from "@/lib/test"

function ListMethods(cls: string) {
    @methodOf(cls) function listAll(): string {
        let acc = ""
        for (m in cls.methods) {
            acc = acc + m.name + ";"
        }
        return acc
    }
}

@ListMethods
class Multi {
    x: int
    function foo(): int { return 1 }
    function bar(): string { return "b" }
}

@ListMethods
class Empty {
    x: int
}

@ListMethods
class WithAccessor {
    _x: int
    get x(): int { return this._x }
    set x(v: int) { this._x = v }
}

function main() {
    test("L2ι — 多方法 + handler 自见", () => {
        const m = new Multi(x: 1)
        // foo, bar (user-declared) + listAll (handler-generated)
        assertEqual(m.listAll(), "foo;bar;listAll;")
    })
    test("L2ι — 仅 handler 方法", () => {
        const e = new Empty(x: 2)
        assertEqual(e.listAll(), "listAll;")
    })
    test("L2ι — accessor 名可见", () => {
        const w = new WithAccessor(_x: 3)
        // getter 名 + setter 名 + handler listAll;accessor mangling 之前的
        // 声明名(x)进 classMethods。get 和 set 都叫 x。
        assertEqual(w.listAll(), "x;x;listAll;")
    })
}
