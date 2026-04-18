// D096 Phase 2 edge coverage — getter-only / setter-only / 多 accessor /
// 同名普通方法并存 / 内部 this.accessor 调用。
class GetterOnly {
    _x: int = 7
    get x(): int { return this._x }
}

class SetterOnly {
    _y: int = 0
    set y(v: int) { this._y = v * 2 }
}

class Multi {
    _z: int = 0
    get z(): int { return this._z }
    set z(v: int) { this._z = v }
    get doubled(): int { return this.z * 2 }     // 内部走 z 的 getter
}

class MixedRegular {
    _v: int = 3
    get val(): int { return this._v }
    function val_raw(): int { return this._v }   // 同名 field-style 普通方法,加 _raw 避冲突
}

function main() {
    const g = new GetterOnly(_x: 7)
    println(g.x)                     // 7

    const s = new SetterOnly(_y: 0)
    s.y = 21
    println(s._y)                    // 42 (setter 乘 2)

    const m = new Multi(_z: 0)
    m.z = 5
    println(m.z)                     // 5
    println(m.doubled)               // 10

    const mx = new MixedRegular(_v: 3)
    println(mx.val)                  // 3 (accessor)
    println(mx.val_raw())            // 3 (普通方法)
}
