// Test: D095 Stage B — @methodOf + cls.name + cls.fields + this[f] 组合
//
// 验证 Lombok @ToString canonical pattern 端到端:
//   1. handler 内 @methodOf(cls) 注入方法到 class
//   2. @methodOf body 内 cls 被 fold 成 string literal
//   3. cls.name → 类名字符串
//   4. cls.fields → 编译期展开 for-in
//   5. this[f] → 编译期常量展开的 bracket 访问
//   6. 单 handler 内多个 @methodOf 独立展开无干扰

import { assertEqual } from "@/lib/test"

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

function DataLike(cls: string) {
    @methodOf(cls) function dataStr(): string {
        let parts = ""
        for (f in cls.fields) {
            if (parts != "") { parts = parts + ", " }
            parts = parts + f.name + "=" + this[f.name]
        }
        return cls.name + "{" + parts + "}"
    }
    @methodOf(cls) function describe(): string {
        let s = ""
        for (f in cls.fields) {
            s = s + "f=" + f.name + ";"
        }
        return s
    }
}

@ToString
class Point {
    x: int
    y: int
}

@DataLike
class Pair {
    a: int
    b: int
}

function main() {
    test("D095 Stage B — @ToString canonical", () => {
        const p = new Point(x: 1, y: 2)
        assertEqual(p.toString(), "Point(x=1, y=2)")
    })

    test("D095 — dual @methodOf in single handler, both iterate cls.fields", () => {
        const pr = new Pair(a: 10, b: 20)
        assertEqual(pr.dataStr(), "Pair{a=10, b=20}")
        assertEqual(pr.describe(), "f=a;f=b;")
    })
}
