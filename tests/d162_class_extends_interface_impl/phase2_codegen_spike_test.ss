// D162 Phase 2 codegen spike — checkInterfaceImpl walk classParents 修法 wire 端验证
//
// 父类 own method 自动满足子类 interface vtable(§核心目标 5)— 子类不必 re-declare
// 父类已实现的 method 即可走 D025 通路,根因解决 D162 §核心目标。Phase 1 binary 下
// 任一 Case 1/2/3/5/6 全编译失败(子类未 re-declare ifaceMethod → checkInterfaceImpl
// classMethods.contains 假阳报错);Phase 2 修法落地后子类不必 re-declare 即 walk
// classParents 链合并 ownMethods + parentMethods 集合走 vtable check 通路 GREEN。
//
// 6 case 覆盖 D162 §A.2 H2 + H3 + H4 全形态:
//   Case 1 单层 — 父类 own method 满足子类 interface (H2 classMethodNames 已存父类)
//   Case 2 多层 chain — Grand→Child→Parent walk (H3 多层 + visited 守)
//   Case 3 子赢 override — 子类 method 同名同 sig 优先 (H4 子赢自然 fall-through)
//   Case 4 overload 不 dedupe — 同名不同 sig 父子各持 (H4 mangled key 自然分隔)
//   Case 5 multi-iface — 父类 method 同时满足 I + J 子集 (H2 + 多 interface implList)
//   Case 6 D160 mini 模型 — class C extends P : I 全 inherit + 1 own (D160 Phase 2 wire mini 锚)
//
// D025 negative anchor (父+子全集仍缺 method 必 exit=1) 在 _negative_phase2_d025.ss.txt
// commit-time shell verify;本 spike 仅验证 walk classParents 修法 GREEN 路径。

import { test, assertEqual, assertTrue } from "@/lib/test"

// ── Case 1: 单层 父类 method 满足子类 interface (H2 classMethodNames 已存父类) ──
interface IGreeterD162 {
    function greet(): string
}
class GreeterParentD162 {
    function greet(): string { return "hello-parent" }
}
class GreeterChildD162 extends GreeterParentD162 : IGreeterD162 {
}

// ── Case 2: 多层 chain Grand→Child→Parent walk (H3 多层 + visited 守) ──
interface IMixedD162 {
    function fromGrand(): int
    function fromChild(): int
    function fromParent(): int
}
class MixedParentD162 {
    function fromParent(): int { return 1 }
}
class MixedChildD162 extends MixedParentD162 {
    function fromChild(): int { return 2 }
}
class MixedGrandD162 extends MixedChildD162 : IMixedD162 {
    function fromGrand(): int { return 3 }
}

// ── Case 3: 子赢 override (H4 子赢自然 fall-through) ──
interface IOverrideD162 {
    function value(): int
}
class OverrideParentD162 {
    function value(): int { return 10 }
}
class OverrideChildD162 extends OverrideParentD162 : IOverrideD162 {
    function value(): int { return 42 }
}

// ── Case 4: overload 不 dedupe — 父子同名不同 sig 各持 (H4 mangled key 分隔) ──
interface IAddD162 {
    function add(): int
}
class AddParentD162 {
    function add(): int { return 100 }
}
class AddChildD162 extends AddParentD162 : IAddD162 {
    function add(x: int): int { return x + 1 }
}

// ── Case 5: multi-iface — 父类 method 同时满足 I + J 子集 ──
interface IFooPD162 {
    function fooP(): int
}
interface IBarQD162 {
    function barQ(): int
}
class MultiParentD162 {
    function fooP(): int { return 7 }
    function barQ(): int { return 8 }
}
class MultiChildD162 extends MultiParentD162 : IFooPD162, IBarQD162 {
}

// ── Case 6: D160 mini 模型 — class C extends P : I 全 inherit + 1 own ──
interface IPreparedMiniD162 {
    function exec(): int
    function closeStmt(): int
}
interface ICallableMiniD162 {
    function exec(): int
    function closeStmt(): int
    function callOut(): int
}
class MysqlPreparedMiniD162 : IPreparedMiniD162 {
    function exec(): int { return 200 }
    function closeStmt(): int { return 201 }
}
class MysqlCallableMiniD162 extends MysqlPreparedMiniD162 : ICallableMiniD162 {
    function callOut(): int { return 202 }
}

function main() {
    test("Case 1 单层: 父类 method 满足子类 interface (子类不 re-declare)", () => {
        const greeter = new GreeterChildD162()
        assertEqual(greeter.greet(), "hello-parent")
    })

    test("Case 2 多层 chain: Grand→Child→Parent walk all hit", () => {
        const grand = new MixedGrandD162()
        assertEqual(grand.fromParent(), 1)
        assertEqual(grand.fromChild(), 2)
        assertEqual(grand.fromGrand(), 3)
    })

    test("Case 3 子赢 override: 子类 method 优先父类 method", () => {
        const child = new OverrideChildD162()
        assertEqual(child.value(), 42)
    })

    test("Case 4 overload 不 dedupe: 父子同名不同 sig 编译通过 + walk 不破 overload mangled 分隔", () => {
        // Walk classParents 修法验证范围:父类 add() 满足接口 IAddD162.add()(D025 walk
        // classParents 通过无 missing method 假阳)+ 子类 add(x: int) overload mangled
        // key 不与父类 add() 冲突(walk 不 dedupe 真错)— 编译成功即 walk 路径 GREEN。
        // 子类 add(x: int) self-call 验证 overload codegen 通路;父类 add() inheritance
        // dispatch 走 method_call.ss(D162 不修 dispatch path,仅修 vtable check)。
        const child = new AddChildD162()
        assertEqual(child.add(5), 6)
    })

    test("Case 5 multi-iface: 父类 method 同时满足 I + J 双 interface", () => {
        const c = new MultiChildD162()
        assertEqual(c.fooP(), 7)
        assertEqual(c.barQ(), 8)
    })

    test("Case 6 D160 mini: class C extends P : I 全 inherit + 1 own (callable mini)", () => {
        const callable = new MysqlCallableMiniD162()
        assertEqual(callable.exec(), 200)
        assertEqual(callable.closeStmt(), 201)
        assertEqual(callable.callOut(), 202)
    })
}
