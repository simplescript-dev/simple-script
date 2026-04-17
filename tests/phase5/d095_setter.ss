// Test: D095 Stage E — @Setter per-field methods
//
// 机制: @methodOf in handler for-in (C 轮落地) + this[f.name] = v bracket write
// (D088 落地) 天然组合,probe 直接 GREEN 即为本测试前身。
// 持久化作为 Stage E 对外接口闭环的一块证据。

import { Setter, Getter } from "@/lib/lombok"
import { assertEqual } from "@/lib/test"

@Getter
@Setter
class Point {
    x: int
    y: int
}

function main() {
    test("D095 — @Setter per-field writes", () => {
        const p = new Point(x: 1, y: 2)
        p.set_x(99)
        p.set_y(77)
        assertEqual(p.get_x(), 99)
        assertEqual(p.get_y(), 77)
    })
}
