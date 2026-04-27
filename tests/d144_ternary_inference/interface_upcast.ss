// D144 Phase 3 — H5 interface upcast via vtable indirect dispatch
// callee `takesShape(s: IShape): double` + ternary `(cond) ? new Circle(1.0) : new Square(2.0)`
// 反推 branchType="IShape" 后两分支 class 实例走 D025 vtable indirect dispatch
// → 既有 NEW_EXPR + interface vtable 路径不破(零破坏既有)
import { assertEqual } from "@/lib/test"

interface IShape {
    function area(): double
}

class Circle : IShape {
    radius: double
    function area(): double {
        return this.radius * this.radius * 3
    }
}

class Square : IShape {
    side: double
    function area(): double {
        return this.side * this.side
    }
}

function takesShape(s: IShape): double {
    return s.area()
}

function main() {
    let x = 5
    let r1 = takesShape((x > 0) ? new Circle(1.0) : new Square(2.0))
    assertEqual(r1, 3.0)
    let y = -5
    let r2 = takesShape((y > 0) ? new Circle(1.0) : new Square(2.0))
    assertEqual(r2, 4.0)
}
