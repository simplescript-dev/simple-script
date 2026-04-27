// D141 Phase 3 — H5 interface upcast vtable indirect dispatch
// callee `consume(cb: fn(IShape):double):double` 反推回填 ARROW_FUNC PARAM s2="IShape"
// → setVarType(s, "IShape") → s.area() 走 `__iface_IShape_area` vtable 路径(D025)
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

function consume(cb: fn(IShape):double): double {
    const sq = new Square(3.0)
    return cb(sq)
}

function main() {
    const r = consume((s) => s.area())
    assertEqual(r, 9.0)
}
