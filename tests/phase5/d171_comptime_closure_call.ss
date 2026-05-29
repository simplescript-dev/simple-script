// D171 Phase 1: 闭包 / arrow 在 comptime 可调用(含外层变量捕获)。
// RED(改前): `[comptime] unknown function: add` → 静默返 0;GREEN(改后): 正确求值。
// 走 D093 统一 evalExpr 产出的 fn-value,调用端消费(不新开 ct* 注册表)。

function main() {
    // 1) 最简调用 — D171 §Phase 1 RED 的 canonical case(add(3,4) 改前静默返 0)
    const simple = comptime {
        const add = (a: int, b: int) => a + b
        return add(3, 4)
    }
    if (simple != 7) { exit(1) }

    // 2) 外层变量捕获 — arrow 引用外层 comptime 变量,沿 ctVars 作用域链解析
    const captured = comptime {
        const base = 100
        const f = (x: int) => x + base
        return f(5)
    }
    if (captured != 105) { exit(1) }

    // 3) 多变量捕获
    const multi = comptime {
        const a = 3
        const b = 7
        const sum = (x: int) => x + a + b
        return sum(10)
    }
    if (multi != 20) { exit(1) }

    // 4) 嵌套调用(arrow 调用作为另一 arrow 调用的实参)
    const nested = comptime {
        const mul = (a: int, b: int) => a * b
        const inc = (n: int) => n + 1
        return inc(mul(6, 7))
    }
    if (nested != 43) { exit(1) }

    println("d171 comptime closure call: ok")
}
