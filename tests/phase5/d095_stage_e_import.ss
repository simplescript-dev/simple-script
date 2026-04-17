// Test: D095 Stage E — import-then-annotate 对外接口
//
// 证据目标: @ToString 从 lib/lombok.ss 经 `import { X } from "@/lib/..."` 引入后,
// 作为 `@X class Foo` 使用能正常展开并生成 toString。
//
// 如果 import 的 handler 无法注册到 ctFuncNodes,@ToString 将被静默忽略,
// p.toString() 调用时会因 "unknown method" 失败。

import { ToString } from "@/lib/lombok"
import { assertEqual } from "@/lib/test"

@ToString
class Point {
    x: int
    y: int
}

function main() {
    test("D095 Stage E — @ToString imported from lib/lombok.ss", () => {
        const p = new Point(x: 1, y: 2)
        assertEqual(p.toString(), "Point(x=1, y=2)")
    })
}
