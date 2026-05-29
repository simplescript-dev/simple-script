// D171 Phase 3: super / 继承方法在 comptime 可调用。
// RED(改前): `[comptime] no method 'speak' on class Dog` — 顶层(runtime)class 的方法在
//   comptime 整体断流。根因 = 注册表不对称:interpFindMethod / resolveSuperParent 只查 comptime
//   声明 class 的注册表(interpClasses / interpClassParents),顶层 class 的权威源
//   (classNodeIds / classParents)被忽略。§最小变量隔离实证:连非继承的顶层 Animal.speak() 都断流。
// GREEN(改后): 两处走 consult-both 对称 helper(interpResolveClassNode / interpResolveParent,
//   comptime 表优先 → 顶层表 fallback),继承方法 / super / 多级继承 / 继承字段构造在 comptime 跑通。
// 走 D093 统一 evalExpr / interpFindMethod,不新开 ct* 注册表(D171 §拒绝准则 / D088 §反模式)。

class Animal { function speak(): string { return "generic" } }
class Dog extends Animal {}                                              // 空子类,纯继承(RED canonical)
class Cat extends Animal { function speak(): string { return super.speak() } }     // super 显式透传
class Loud extends Animal { function speak(): string { return super.speak() + "!" } } // super 增强
class Fox extends Animal { function speak(): string { return "ring-ding" } }       // 完全 override

class A2 { function tag(): string { return "A" } }
class B2 extends A2 {}
class C2 extends B2 {}                                                   // 多级继承(祖父方法)

class Base { tag: string = "base" }
class Derived extends Base {}                                            // 继承字段构造

function main() {
    // 1) RED canonical — 顶层空子类继承父类方法(d.speak() 改前 loud error `no method 'speak'`)
    const c1 = comptime { const d = new Dog(); return d.speak() }
    if (c1 != "generic") { exit(1) }

    // 2) super.speak() 显式透传到父类(resolveSuperParent comptime 分支走 classParents fallback)
    const c2 = comptime { const c = new Cat(); return c.speak() }
    if (c2 != "generic") { exit(1) }

    // 3) override 调 super 增强(子类 + 父类方法各执行一次,字符串拼接)
    const c3 = comptime { const l = new Loud(); return l.speak() }
    if (c3 != "generic!") { exit(1) }

    // 4) 完全 override — 子类同名方法 shadow 父类(interpFindMethod 在父类前先命中 cur 自身方法)
    const c4 = comptime { const f = new Fox(); return f.speak() }
    if (c4 != "ring-ding") { exit(1) }

    // 5) 多级继承 — C2 → B2 → A2,祖父方法 tag() 经两级 parent walk 命中
    const c5 = comptime { const c = new C2(); return c.tag() }
    if (c5 != "A") { exit(1) }

    // 6) 继承字段构造 — Derived 空子类,父类 Base.tag 默认值在 comptime new 时被 prepend 收集
    //    (改前 ctNewExprDispatch parent walk 断在第一层漏父字段 → d.tag 返 0/null;改后 = "base")
    const c6 = comptime { const d = new Derived(); return d.tag }
    if (c6 != "base") { exit(1) }

    // 7) 继承字段反射 — comptime 块内声明的子类 extends 顶层 class,.fields() 须含顶层父类字段
    //    (interpBuildTypeInfo parent walk 第四处 consult-both;改前漏顶层父字段 fields 数 1,改后 2)
    const c7 = comptime {
        class Pup extends Base { age: int = 0 }
        const p = new Pup()
        return p.fields().length()
    }
    if (c7 != 2) { exit(1) }

    println("d171 comptime super / inherited: ok")
}
