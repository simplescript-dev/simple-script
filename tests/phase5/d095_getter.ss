// Test: D095 Stage E — @Getter 按字段生成不同方法名
//
// 依赖:
//   (1) AST clone - handler for-in 迭代内每次独立 FUNC_DECL
//   (2) function [expr]() - computed method name (ES6 风格)
//   (3) foldComptimeIdentsInTree 不污染后续迭代
//
// 方法名风格: get_${f.name} (下划线),首字母大写留给后续 (comptime capitalize 另议)

import { Getter } from "@/lib/lombok"
import { assertEqual } from "@/lib/test"

@Getter
class Point {
    x: int
    y: int
}

function main() {
    test("D095 — @Getter per-field methods", () => {
        const p = new Point(x: 10, y: 20)
        assertEqual(p.get_x(), 10)
        assertEqual(p.get_y(), 20)
    })
}
