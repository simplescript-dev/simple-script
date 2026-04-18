// @Setter per-field mutators — regression guard for @methodOf for-in +
// bracket-write composition.

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
