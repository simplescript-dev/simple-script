// Lombok-style annotation handlers for SimpleScript.
//
// D095 Stage E — 对外接口证据：这些 handler 通过 `import { X } from "@/lib/lombok"`
// 引入后,必须能在 class 前作为 `@X class Foo` 使用。行为与 Java Lombok 对齐。
//
// 当前阶段 cls 参数类型为 string (类名),未来升级为 ClassMeta (D095 §差距清单 第 1 条)。

function ToString(cls: string) {
    @methodOf(cls) function toString(): string {
        let parts = ""
        for (f in cls.fields) {
            if (parts != "") { parts = parts + ", " }
            parts = parts + f.name + "=" + this[f.name]
        }
        return cls.name + "(" + parts + ")"
    }
}

// Per-field accessor methods. Naming convention: get_<field> (underscore).
// Camel-case `getX` awaits comptime capitalize (future).
function Getter(cls: string) {
    for (f in cls.fields) {
        @methodOf(cls) function [`get_${f.name}`](): int {
            return this[f.name]
        }
    }
}
