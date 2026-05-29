import { assertEq } from "./import/asserts"

// ════════════════════════════════════════════════════════════════════════
// D171 Phase 5 — comptime 解释器语言覆盖度回归套件
//
// §张力 4「完整语言」终点代理判据:"comptime 块里能跑的 SS 子集 = 整个 SS 语言"
// 无法穷举 grep,本套件以 breadth 实测作可观测代理 —— 每个 SS 主构造在 comptime
// 块内跑通并 assertEq,锁定 D171 Phase 1-5 全部能力增长(闭包/spread/super/try/catch
// + 既有 enum/class/destructure/loop/generic/builtin-method),防回归。
//
// 配套负向 loud-gate(未覆盖构造必 loud comptimeError 非静默返 0,D088 §Phase 8):
//   tests/phase5/d171_comptime_loud_*.ss.txt(commit-time shell verify)
// ════════════════════════════════════════════════════════════════════════

enum Color { Red, Green, Blue }

function identity<T>(x: T): T { return x }
function gadd<T>(a: T, b: T): T { return a + b }

class Animal {
    name: string
    function speak(): string { return `${this.name} makes a sound` }
}
class Dog extends Animal {
    function speak(): string { return `${super.speak()} (woof)` }
}

function main() {
    // ── 1. 字面量 + 算术 + pow + 一元 + 三元 ──
    assertEq(comptime { return 10 + 3 * 4 }, 22, "binary precedence")
    assertEq(comptime { return 2 ** 10 }, 1024, "pow")
    assertEq(comptime { return 0 - (5) }, 0 - 5, "unary neg")
    assertEq(comptime { return ~0 }, 0 - 1, "bitnot")
    assertEq(comptime { const b = true; return b ? 7 : 9 }, 7, "ternary")
    assertEq(comptime { const x = 5; return !(x > 3) ? 1 : 0 }, 0, "unary not")

    // ── 2. 字符串方法 ──
    assertEq(comptime { return "hello".length() }, 5, "str length")
    assertEq(comptime { return "Hi".toUpperCase() }, "HI", "str upper")
    assertEq(comptime { return "a,b,c".split(",").length() }, 3, "str split→array len")
    assertEq(comptime { return "hello".substring(0, 3) }, "hel", "str substring (start,len)")
    assertEq(comptime { return "hello".indexOf("ll") }, 2, "str indexOf")
    // D171 收口验收硬化:补全 grep-站点审计漏的 8 string 方法盲区(.map bug 同族)+ 语义/边界锁
    assertEq(comptime { return "  hi  ".trim() }, "hi", "str trim")
    assertEq(comptime { return "Hi There".toLowerCase() }, "hi there", "str toLowerCase")
    assertEq(comptime { return "a-b-c".replace("-", "+") }, "a+b+c", "str replace")
    assertEq(comptime { return "hello".startsWith("he") ? 1 : 0 }, 1, "str startsWith")
    assertEq(comptime { return "hello".endsWith("lo") ? 1 : 0 }, 1, "str endsWith")
    assertEq(comptime { return "hello".charAt(1) }, "e", "str charAt")
    assertEq(comptime { return "hello".includes("ell") ? 1 : 0 }, 1, "str includes")
    assertEq(comptime { return "ab".repeat(3) }, "ababab", "str repeat")
    assertEq(comptime { return "hello".substring(1, 3) }, "ell", "str substring (start,len) 语义锁(非 end)")
    assertEq(comptime { return "hello".indexOf("z") }, 0 - 1, "str indexOf not-found = -1")

    // ── 3. 数组方法(含 map/filter/reduce 高阶) ──
    assertEq(comptime { return [1, 2, 3, 4].length() }, 4, "arr length")
    assertEq(comptime { return [10, 20, 30].indexOf(20) }, 1, "arr indexOf")
    assertEq(comptime { return [1, 2, 3].join("-") }, "1-2-3", "arr join")
    assertEq(comptime { return [1, 2, 3, 4].slice(1, 3).length() }, 2, "arr slice")
    assertEq(comptime {
        const a = [1, 2, 3]
        return a.map((x: int) => x * 2)[2]
    }, 6, "arr map")
    assertEq(comptime {
        const a = [1, 2, 3, 4]
        return a.filter((x: int) => x > 2).length()
    }, 2, "arr filter")
    assertEq(comptime {
        const a = [1, 2, 3, 4]
        return a.reduce((s: int, x: int) => s + x, 0)
    }, 10, "arr reduce")
    // D171 收口验收硬化:补 push storeback / forEach 外层捕获变异 / indexOf 边界 / slice 负 end
    assertEq(comptime { let a = [1, 2]; a.push(3); return a.length() }, 3, "arr push storeback")
    assertEq(comptime {
        let s = 0
        [1, 2, 3, 4].forEach((x: int) => { s = s + x })
        return s
    }, 10, "arr forEach 外层捕获变异")
    assertEq(comptime { return [1, 2, 3].indexOf(9) }, 0 - 1, "arr indexOf not-found = -1")
    assertEq(comptime { return ["a", "b", "c"].indexOf("b") }, 1, "arr indexOf string elem")
    // slice 负 end:comptime 正确处理(end<0 → len+end),runtime 范围外(收口验收发现 B)
    assertEq(comptime { return [1, 2, 3, 4].slice(1, 0 - 1).length() }, 2, "arr slice 负 end(comptime 正确)")

    // ── 4. Map 方法 ──
    assertEq(comptime {
        const m = new Map()
        m.set("k", 42)
        return m.get("k")
    }, 42, "map get")
    assertEq(comptime {
        const m = new Map()
        m.set("a", 1)
        return m.has("a")
    }, 1, "map has")
    assertEq(comptime {
        const m = new Map()
        m.set("a", 1)
        m.set("b", 2)
        return m.size()
    }, 2, "map size")
    assertEq(comptime {
        const m = new Map()
        m.set("s", "v")
        return m.getString("s")
    }, "v", "map getString")
    // D171 收口验收硬化:补 getBool / delete / keys(getInt/getDouble 仍 deferred I003b,见 D171 §160)
    assertEq(comptime { const m = new Map(); m.set("b", true); return m.getBool("b") ? 1 : 0 }, 1, "map getBool")
    assertEq(comptime { const m = new Map(); m.set("k", 1); m.delete("k"); return m.has("k") ? 1 : 0 }, 0, "map delete")
    assertEq(comptime { const m = new Map(); m.set("a", 1); m.set("b", 2); return m.keys().length() }, 2, "map keys length")

    // ── 5. 闭包 / arrow + 外层捕获(Phase 1) ──
    assertEq(comptime {
        const add = (a: int, b: int) => a + b
        return add(3, 4)
    }, 7, "closure call")
    assertEq(comptime {
        const base = 100
        const f = (x: int) => x + base
        return f(5)
    }, 105, "closure capture")
    // 注:嵌套闭包返回闭包(inner arrow 捕获 outer arrow 形参)超出 ctVars 平坦作用域链
    // 能力(D171 §张力 1),正确 loud comptimeError 非静默 — 见 d171_comptime_loud_*.ss.txt。

    // ── 6. spread:数组字面量(Phase 2)+ 中段 spread ──
    assertEq(comptime {
        const a = [1, 2]
        const b = [...a, 3, 4]
        return b.length()
    }, 4, "spread array lit")
    assertEq(comptime {
        const a = [10, 20]
        const b = [0, ...a]
        return b[2]
    }, 20, "spread mid")

    // ── 7. enum ──
    assertEq(comptime { return Color.Blue }, 2, "enum value")

    // ── 8. class 实例化 + 字段 + 方法 + 继承 + super(Phase 3) ──
    assertEq(comptime {
        class P { x: int; y: int }
        const p = new P(3, 4)
        return p.x + p.y
    }, 7, "ct class field")
    assertEq(comptime {
        class Base { v: int; function get(): int { return this.v } }
        class Child extends Base { function get(): int { return super.get() + 100 } }
        return new Child(42).get()
    }, 142, "ct super.method")
    // 顶层继承类(走权威对称注册表,Phase 3 翻案根因)
    assertEq(comptime {
        const d = new Dog("Rex")
        return d.speak().length()
    }, "Rex makes a sound (woof)".length(), "toplevel inherited+super")

    // ── 9. try / catch / throw / finally(Phase 4) ──
    assertEq(comptime {
        try { throw("boom") } catch (e) { return e.length() }
        return 0
    }, 4, "try/catch value")
    assertEq(comptime {
        let acc = 0
        try {
            acc = 1
            throw("x")
        } catch (e) {
            acc = acc + 10
        } finally {
            acc = acc + 100
        }
        return acc
    }, 111, "try/catch/finally order")

    // ── 10. 解构:数组 + rest + 对象 ──
    assertEq(comptime {
        const [a, b] = [11, 22]
        return a + b
    }, 33, "array destructure")
    assertEq(comptime {
        const [first, ...rest] = [1, 2, 3, 4]
        return rest.length()
    }, 3, "rest destructure")
    assertEq(comptime {
        class Pt { x: int; y: int }
        const p = new Pt(5, 6)
        const { x, y } = p
        return x + y
    }, 11, "object destructure")

    // ── 11. 循环:while / for / do-while / for-in ──
    assertEq(comptime {
        let i = 0
        let s = 0
        while (i < 5) { s = s + i; i = i + 1 }
        return s
    }, 10, "while")
    assertEq(comptime {
        let s = 0
        for (let i = 1; i <= 4; i = i + 1) { s = s + i }
        return s
    }, 10, "for")
    assertEq(comptime {
        let i = 0
        let s = 0
        do { s = s + 1; i = i + 1 } while (i < 3)
        return s
    }, 3, "do-while")
    assertEq(comptime {
        let s = 0
        for (x in [1, 2, 3, 4]) { s = s + x }
        return s
    }, 10, "for-in")

    // ── 12. 泛型函数调用 ──
    assertEq(comptime { return identity(99) }, 99, "generic identity")
    assertEq(comptime { return gadd(10, 20) }, 30, "generic add")

    println("D171 Phase 5 comptime coverage — all constructs GREEN")
}
