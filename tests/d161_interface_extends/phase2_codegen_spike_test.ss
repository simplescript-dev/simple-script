// D161 Phase 2 codegen spike test — ifaceParents Map + registerInterface walk parent chain
// merge methodNames / ifaceMethodSigs / ifaceMethodRets / ifaceMethodPars。Case 1-6 共 6 case
// 全 PASS 即证 Phase 2 codegen 层 register-time merge 与 D025 vtable check 通路落地。
//
// Phase 2 scope:codegen + checker register-time merge(§核心原则 2);negative D025 通路验证
// 锚 tests/d161_interface_extends/_negative_phase2_d025.ss.txt(commit-time shell)。

import { test, assertEqual, assertTrue } from "@/lib/test"

// Case 1 — 单层 extends 父子皆 own method,implementor 必须实现父 + 子双 method(D025 通过)
interface ParentA {
    function pa(): int
}
interface ChildA extends ParentA {
    function ca(): int
}
class ImplChildA : ChildA {
    function pa(): int { return 1 }
    function ca(): int { return 2 }
}

// Case 2 — 多层 chain 三层全 merge:GrandParent → Parent → Child
interface GrandParent2 {
    function gp(): int
}
interface Parent2 extends GrandParent2 {
    function p2(): int
}
interface Child2 extends Parent2 {
    function c2(): int
}
class ImplChild2 : Child2 {
    function gp(): int { return 11 }
    function p2(): int { return 22 }
    function c2(): int { return 33 }
}

// Case 3 — 同名 sig override 子接口签名优先(parent foo() vs child foo() 同 0-arg sig)
interface ParentB {
    function foo3(): int
}
interface ChildB extends ParentB {
    function foo3(): int
}
class ImplChildB : ChildB {
    function foo3(): int { return 100 }
}

// Case 4 — 同名 method 不同 paramSig 自然分隔(parent bar() vs child bar(x: int))
// ifaceMethodsCG.getString("ChildC") 含 bar + bar_i 两个 mangled key,dispatch 各走对应 path
interface ParentC {
    function bar4(): int
}
interface ChildC extends ParentC {
    function bar4(x: int): int
}
class ImplChildC : ChildC {
    function bar4(): int { return 0 }
    function bar4(x: int): int { return x * 2 }
}

// Case 5 — NClob extends Clob method 集合自动 N method 继承(Phase 3 NClob 回退预演)
// FakeClob 3 method + FakeNClob extends FakeClob {} → ImplFakeNClob 必须实 FakeClob 3 method
interface FakeClob {
    function flength(): int
    function fgetSubString(): string
    function fsetString(): int
}
interface FakeNClob extends FakeClob {
}
class ImplFakeNClob : FakeNClob {
    function flength(): int { return 10 }
    function fgetSubString(): string { return "x" }
    function fsetString(): int { return 1 }
}

// Case 6 — parent type 位置 upcast dispatch:声明 ParentE 类型 var 持 ImplChildE 实例,
// 通过父接口 type 调用方法走 vtable 派发到 child 的 impl method(D025 vtable 通路 + 多态)
interface ParentE {
    function pingE(): int
}
interface ChildE6 extends ParentE {
    function pongE(): int
}
class ImplChildE6 : ChildE6 {
    function pingE(): int { return 7 }
    function pongE(): int { return 8 }
}

function main() {
    test("Case 1: single layer extends — parent method 自动继承,ImplChildA 实 pa + ca 双 method 走 D025 通路", () => {
        const impl = new ImplChildA()
        assertEqual(impl.pa(), 1)
        assertEqual(impl.ca(), 2)
        let c: ChildA = new ImplChildA()
        assertEqual(c.pa(), 1)
        assertEqual(c.ca(), 2)
    })

    test("Case 2: 3-layer chain merge — Child2 ifaceMethodsCG entry 含 GrandParent2 + Parent2 + Child2 三层 method 全集", () => {
        const impl = new ImplChild2()
        assertEqual(impl.gp(), 11)
        assertEqual(impl.p2(), 22)
        assertEqual(impl.c2(), 33)
        let c: Child2 = new ImplChild2()
        assertEqual(c.gp(), 11)
        assertEqual(c.p2(), 22)
        assertEqual(c.c2(), 33)
    })

    test("Case 3: same sig override — 子接口 redeclare 同 0-arg foo3 走 child 签名(merge dedupe + override)", () => {
        const impl = new ImplChildB()
        assertEqual(impl.foo3(), 100)
        let c: ChildB = new ImplChildB()
        assertEqual(c.foo3(), 100)
    })

    test("Case 4: different paramSig natural split — ifaceMethodsCG ChildC 含 bar4 + bar4_i 两 mangled key,dispatch 分流", () => {
        const impl = new ImplChildC()
        assertEqual(impl.bar4(), 0)
        assertEqual(impl.bar4(5), 10)
        let c: ChildC = new ImplChildC()
        assertEqual(c.bar4(), 0)
        assertEqual(c.bar4(5), 10)
    })

    test("Case 5: NClob extends Clob shape — FakeNClob 自动继承 FakeClob 3 method,ImplFakeNClob 实全集走 D025 通路", () => {
        const impl = new ImplFakeNClob()
        assertEqual(impl.flength(), 10)
        assertEqual(impl.fgetSubString(), "x")
        assertEqual(impl.fsetString(), 1)
        let n: FakeNClob = new ImplFakeNClob()
        assertEqual(n.flength(), 10)
        assertEqual(n.fgetSubString(), "x")
        assertEqual(n.fsetString(), 1)
    })

    test("Case 6: parent type upcast dispatch — let p: ParentE = new ImplChildE6() 走父接口 vtable 派发到 child impl", () => {
        const impl = new ImplChildE6()
        assertEqual(impl.pingE(), 7)
        assertEqual(impl.pongE(), 8)
        let p: ParentE = new ImplChildE6()
        assertEqual(p.pingE(), 7)
    })
}
