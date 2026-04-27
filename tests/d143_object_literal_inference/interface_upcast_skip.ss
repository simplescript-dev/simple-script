// D143 Phase 3 — H5b interface upcast OOD scope
// object literal `{ side: 2.0 }` 不能直接 implements interface IShape — 反推 className=IShape 后 D084 rewrite NEW_EXPR IShape 不可达(interface 不可 instantiate)
// 用户必须显式 `new Square(2.0)` 构造 → 走 D025 vtable indirect dispatch(`__iface_IShape_area`)
// 本测试证明:OBJ_LITERAL 反推机制不破坏既有 NEW_EXPR + interface vtable 路径(零破坏既有)
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

function takesShape(s: IShape): double {
    return s.area()
}

function main() {
    const r = takesShape(new Square(2.0))
    assertEqual(r, 4.0)
}
