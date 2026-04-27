// D142 Phase 3 — H5 Array<IShape> interface upcast vtable indirect dispatch
// callee `takesShapes(arr: Array<IShape>): double` → ARRAY_LIT `[new Square(2.0), new Circle(3.0)]`
// 节点 nSetS2 反推回填 "IShape" → ss_newArrayPtr + arr.area() 走 D025 vtable indirect GREEN
import { assertEqual } from "@/lib/test"

interface IShape {
    function area(): double
}

class Square : IShape {
    side: double
    function area(): double {
        return this.side * this.side
    }
}

class Circle : IShape {
    radius: double
    function area(): double {
        return 3.14 * this.radius * this.radius
    }
}

function takesShapes(arr: Array<IShape>): double {
    let total = 0.0
    for (s in arr) { total = total + s.area() }
    return total
}

function main() {
    const r = takesShapes([new Square(2.0), new Circle(3.0)])
    // 4.0 (Square 2x2) + 28.26 (Circle pi*3*3) = 32.26
    assertEqual(r, 32.26)
}
