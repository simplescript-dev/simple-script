// D161 Phase 1 unit test — parser parseInterfaceDecl EXTENDS clause + INTERFACE_DECL nSetS2 父接口名 slot
//
// Validates D161 §核心目标 1 (parser EXTENDS 子句解析) + §A.2 H1 (parser EXTENDS 解析与 class extends 同形)
// + §核心原则 5 子接口签名 override 范式延续。Parser 节点 nGetS2 = 父接口名是
// 内部 AST slot (无法从用户层 SS 程序直接读取),故本文件以"程序成功编译 + 运行 exit 0"
// 作 parser 节点 slot 落地的间接验证 — Case 2-5 任一编译失败即说明 nSetS2(id, extendsName)
// 或 EXTENDS 子句解析未落地,Case 1 编译失败即说明既有 interface 向后兼容被破。
//
// Phase 1 scope:仅 parser 层落地 EXTENDS 子句解析 + INTERFACE_DECL 节点 nSetS2 slot。
// 编译器 codegen 层 (gen_iface.ss registerInterface walk parent chain merge methodNames /
// ifaceMethodSigs / ifaceMethodRets / ifaceMethodPars) 留 D161 Phase 2,故 Phase 1 的
// `class X : ChildIface` 只需实现 ChildIface own method (parent method 自动继承留 Phase 2)。
//
// Negative case (Case 4 multi-extends rejection) 在 D161 §N §4 边界 验证锚:
//   echo 'interface MultiExt extends A extends B { } function main() { }' | bin/ss build /dev/stdin -o /tmp/_out
//   → exit != 0 + stderr 含 "expected LBRACE" (parser pExpect("LBRACE") 在 parseTypeAnn 后
//   遇到第二个 EXTENDS token 退出,与 multi-extends `interface A extends B, C` 同形拒绝路径)。
//   Parser 错误调用 exit(1) 不可被 try/catch 捕获,故不在本运行时测试中包含;由提交时
//   shell 验证锚锁定 (D161 §N §4)。

import { test, assertEqual, assertTrue } from "@/lib/test"

// Case 1 — 无 extends 向后兼容:既有 interface 不带 extends 仍能 declare + impl + dispatch
interface IfaceNoExt {
    function pingNoExt(): int
}
class ImplNoExt : IfaceNoExt {
    function pingNoExt(): int { return 1 }
}

// Case 2 — 单继承 + 父子皆 empty:parser EXTENDS 子句被解析,nSetS2(id, extendsName="ParentEmpty") 落 slot
interface ParentEmpty {
}
interface ChildEmpty extends ParentEmpty {
}
class ImplChildEmpty : ChildEmpty {
}

// Case 3 — 单继承 + 子接口 own method:parser 节点 nSetS2 + nSetList(methods) 同时落
interface ParentB {
}
interface ChildC extends ParentB {
    function fooC(): int
}
class ImplChildC : ChildC {
    function fooC(): int { return 42 }
}

// Case 4 — 父子接口各 own method,Phase 1 codegen 仅要求子接口 own method 实现
// (验证 Phase 1 nSetS2 已落但 Phase 2 walk parent chain merge 尚未启动 — 否则
// ImplChildD 会被 D025 vtable 强制实现 parentDMethod 编译失败)。Phase 2 落地后此 case
// 转 phase2_codegen_spike_test.ss 验证 parentDMethod 自动继承 + ImplChildD 必须实现父子两 method。
interface ParentD {
    function parentDMethod(): int
}
interface ChildD extends ParentD {
    function childDMethod(): int
}
class ImplChildD : ChildD {
    function childDMethod(): int { return 7 }
}

// Case 5 — implementor class 同 SS 文件内 parse 通过 + 子接口 type 位置 upcast 可用
// (验证 INTERFACE_DECL 节点完整性 — type 系统 / dispatch 路径 / D025 vtable check 全 backward compat)
interface ParentE {
}
interface ChildE extends ParentE {
    function pingE(): int
}
class ImplChildE : ChildE {
    function pingE(): int { return 100 }
}

function main() {
    test("Case 1: backward compat — interface without extends still declares + impl + dispatches", () => {
        const impl = new ImplNoExt()
        assertEqual(impl.pingNoExt(), 1)
    })

    test("Case 2: single extends, both empty — parser stores nSetS2(id, extendsName) without breaking codegen", () => {
        const impl = new ImplChildEmpty()
        // 编译 + 运行成功即证 parser 接受 EXTENDS 子句 + INTERFACE_DECL nSetS2 slot 落地不破 codegen
        assertTrue(1)
    })

    test("Case 3: single extends + child own method — parser stores both nSetS2 + nSetList(methods)", () => {
        const impl = new ImplChildC()
        assertEqual(impl.fooC(), 42)
    })

    test("Case 4: Phase 1 codegen only requires child own method — parent merge is Phase 2 (validates nSetS2 落 slot 但未触发 walk parent chain merge)", () => {
        const impl = new ImplChildD()
        assertEqual(impl.childDMethod(), 7)
    })

    test("Case 5: child interface used in upcast type position — INTERFACE_DECL fully usable downstream", () => {
        let e: ChildE = new ImplChildE()
        assertEqual(e.pingE(), 100)
    })
}
