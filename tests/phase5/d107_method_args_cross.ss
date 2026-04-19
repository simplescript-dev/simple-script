// D107 §新张力 1 验证: METHOD_CALL 迁 evalMethodCall 后 args 跨 evalExpr
// 边界 scope 一致性 — 5 场景覆盖顶层 / 嵌套 CALL / 嵌套 MEMBER / named / optional

class Inner {
    v: int
    function show(): int { return this.v * 10 }
}

class Box {
    n: int
    inner: Inner
    function m1(a: int, b: int, c: int): int { return a + b + c }
    function m2(x: int): int { return x * 2 }
    function m3(name: string, age: int): int { return age + 1 }
}

function identity(n: int): int { return n }
function wrap(n: int): int { return identity(n) + 1 }

function main() {
    // (a) 顶层 method call: obj.m(a, b, c)
    const inner = new Inner(7)
    const b = new Box(0, inner)
    const r1 = b.m1(1, 2, 3)
    if (r1 != 6) { exit(1) }

    // (b) 嵌套 CALL args: obj.m(f(g(x))) — 跨 evalExpr 边界保持 callPreRegs 正确
    const r2 = b.m2(wrap(identity(10)))
    if (r2 != 22) { exit(1) }

    // (c) 链式 MEMBER_ACCESS + 嵌套 method call: obj.m(obj2.inner.show())
    // 混合 IDENT(已迁) + MEMBER_ACCESS(已迁) + METHOD_CALL(本轮迁)跨 evalExpr
    const r3 = b.m1(b.n, b.inner.v, b.inner.show())
    if (r3 != 77) { exit(1) }

    // (d) named args: obj.m(name: "x", age: y)
    const y = 42
    const r4 = b.m3(name: "foo", age: y)
    if (r4 != 43) { exit(1) }

    // (e) optional chain + chained member access in args: obj?.m(k: x.v)
    b.inner.v = 77
    const r5 = b?.m2(b.inner.v)
    if (r5 != 154) { exit(1) }
}
