// D162 Phase 1 unit test — parser parseClassDecl 验证 EXTENDS + COLON 组合子句
// (CLASS_DECL 节点 nSetS2 父类名 + nSetS3 implList 双 slot 全填)
//
// Validates D162 §核心目标 2 (parser 组合语法范式锚定 — line 427-441 已支持组合,本 D
// 仓内首次系统性使用) + §A.2 H1 (parser EXTENDS + COLON 双子句解析与现有 class extends
// + interface impl 同形)。Parser 节点 nGetS2 = 父类名 / nGetS3 = implList 是内部 AST
// slot (无法从用户层 SS 程序直接读取),故本文件以"程序成功编译 + 运行 exit 0"作 parser
// 节点 slot 落地的间接验证 — Case 1-3 任一编译失败即说明 EXTENDS / COLON 子句解析失败
// 或 nSetS2 / nSetS3 slot 落地失败,Case 3 编译失败即说明 extends-only 兼容路径被破。
//
// Phase 1 scope:仅 parser 层 spike test 验证 EXTENDS + COLON 双子句解析。Phase 1
// binary 下 D025 vtable check 不 walk classParents,故 Case 1-2 子类必须 re-declare
// interface methods 满足 D025 vtable check (Phase 2 walk classParents 修法落地后,
// 子类不必 re-declare 即可走父类 method 满足 vtable — D162 §核心目标 5)。
//
// Negative case (Phase 2 binary 下 walk classParents 仍缺 method 走 D025 真错路径) 在
// D162 §A.2 H4 / Phase 2 §收关锚 _negative_phase2_d025.ss.txt 验证,本 Phase 1 不验证
// D025 假阳消除 — 留 Phase 2 codegen spike (≥6 case + negative anchor)。

import { test, assertEqual, assertTrue } from "@/lib/test"

// Case 1 — 双 slot 全填 (extends + : interface 同时存在):
// nGetS2(TestChildD162) = "TestParentD162" (extendsName)
// nGetS3(TestChildD162) = "TestIfaceD162" (implList)
// Phase 1 binary 子类 re-declare ifaceMethod 满足 D025 vtable
class TestParentD162 {
    function parentMethodA(): int { return 1 }
}
interface TestIfaceD162 {
    function ifaceMethodA(): int
}
class TestChildD162 extends TestParentD162 : TestIfaceD162 {
    function ifaceMethodA(): int { return 2 }
}

// Case 2 — extends + : 多 interface impl (implList comma 分割):
// nGetS3(TestChildD162B) = "TestIfaceD162B,TestIfaceD162C"
// nGetS2(TestChildD162B) = "TestParentD162B"
// Phase 1 binary 子类 re-declare 双 interface own method 满足 D025 vtable
class TestParentD162B {
    function parentMethodB(): int { return 10 }
}
interface TestIfaceD162B {
    function ifaceB(): int
}
interface TestIfaceD162C {
    function ifaceC(): int
}
class TestChildD162B extends TestParentD162B : TestIfaceD162B, TestIfaceD162C {
    function ifaceB(): int { return 20 }
    function ifaceC(): int { return 30 }
}

// Case 3 — 仅 extends 无 implList (兼容路径):
// nGetS2(TestChildD162C) = "TestParentD162C"
// nGetS3(TestChildD162C) = "" (empty implList)
// Phase 1 binary 不触发 D025 vtable check (无 implList),仅验证 extends 子句单独解析不破
class TestParentD162C {
    function parentMethodC(): int { return 100 }
}
class TestChildD162C extends TestParentD162C {
    function ownMethodC(): int { return 200 }
}

function main() {
    test("Case 1: extends + : single interface — dual-slot full-fill (extendsName + implList)", () => {
        const child = new TestChildD162()
        assertEqual(child.parentMethodA(), 1)
        assertEqual(child.ifaceMethodA(), 2)
    })

    test("Case 2: extends + : multi-interface — implList comma-split (TestIfaceD162B,TestIfaceD162C)", () => {
        const childB = new TestChildD162B()
        assertEqual(childB.parentMethodB(), 10)
        assertEqual(childB.ifaceB(), 20)
        assertEqual(childB.ifaceC(), 30)
    })

    test("Case 3: extends-only (no implList) — backward-compat path (parser EXTENDS clause not breaking when COLON absent)", () => {
        const childC = new TestChildD162C()
        assertEqual(childC.parentMethodC(), 100)
        assertEqual(childC.ownMethodC(), 200)
    })
}
