// D096 Phase 4 L2ζ — FieldMeta.annotations 反射
// f.annotations 在 comptime 展开为 annotation 名字数组,Annotation Handler
// 里 for-in 可遍历。覆盖:(a) 有/无注解混排 (b) 多注解叠加 (c) 全无注解。

import { assertEqual } from "@/lib/test"

function TagFields(cls: string) {
    @methodOf(cls) function tags(): string {
        let acc = ""
        for (f in cls.fields) {
            for (a in f.annotations) {
                acc = acc + f.name + "@" + a.name + ";"
            }
        }
        return acc
    }
}

@TagFields
class C {
    @Deprecated x: int
    y: int
    @Deprecated @Override z: string
}

@TagFields
class Bare {
    p: int
    q: int
}

function main() {
    test("L2ζ — f.annotations mixed", () => {
        const c = new C(x: 1, y: 2, z: "hi")
        // x has @Deprecated, y has none, z has @Deprecated and @Override
        assertEqual(c.tags(), "x@Deprecated;z@Deprecated;z@Override;")
    })
    test("L2ζ — f.annotations all-empty class", () => {
        const b = new Bare(p: 1, q: 2)
        assertEqual(b.tags(), "")
    })
}
