// D088 Phase 4 RED — 类型作为 comptime 值最小标靶。
// 当前预期失败:`const T = comptime { return Foo }` 拿不到 class Foo 的类型值,
// 下游 `new T(x:5)` 报 "unknown class: T"。Phase 4 GREEN 后应输出 v=5。

const T = comptime {
    class Foo { x: int = 0 }
    return Foo
}

function main() {
    const v = comptime {
        const f = new T(x: 5)
        return f.x
    }
    println(`v=${v}`)
}
