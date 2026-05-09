// D163 Phase 1 codegen bug 复现 spike — extends + iface impl + iface-typed own field write
//
// 实测 RED-as-spike 范式:本 spike 现状 assertEqual 失败,Phase 2 编译器层修法落地后重跑全 GREEN。
// 起首:D160 §F9 docker 在线 8 case wire 真值实测发现根因 — 子类 own method 内
// `this.ifaceField = newVal` 写入 OK 但后续读 `this.ifaceField.method()` 返默认值 0
// 而非 newVal.method() 真值。Minimum repro `/tmp/d160_min_repro.ss` 实测输出:
//   local newBox.fetch=99
//   after assign this.box.fetch=0    ← BUG
//   go() = 0                         ← BUG
//
// **Phase 1 LLVM IR inspect 实测真根因**(推翻 D163 §A.2 H1 "GEP offset 错位" 假设):
// `bin/ss build /tmp/d160_min_repro.ss --emit-ir` 显示:
//   - WRITE 路径(this.box = newBox)— GEP offset 与 RC retain/release 全正确
//       %12 = getelementptr %Child, ptr %11, i32 0, i32 4   ; 正确 offset(parent fields + own idx)
//       call void @ss_retain(ptr %8)
//       store ptr %8, ptr %12, align 8
//       call void @ss_release(ptr %13)
//   - READ + method call 路径(this.box.fetch())— GEP offset 也正确,method dispatch IR 缺失
//       %18 = getelementptr %Child, ptr %17, i32 0, i32 4   ; offset 正确
//       %19 = load ptr, ptr %18, align 8                     ; load 出 box ptr
//       ; TODO: method call .fetch                          ; ← BUG: emit TODO 注释占位
//       %20 = call ptr @ss_int_to_string(i32 0)             ; ← BUG: 0 字面量替代 fetch() 返值
//
// **真根因 file:line**(对比 local var newBox.fetch() 走 `__iface_Box_fetch` GREEN 通路):
//   1. bootstrap/gen/gen_types.ss:248-249 resolveObjClass MEMBER_ACCESS 分支
//      只检 `classFields.has(fType) == 1` 漏检 `ifaceMethodsCG.has(fType) == 1`
//      → MEMBER_ACCESS 节点 this.box (field type Box=interface) → resolveObjClass 返 ""
//   2. bootstrap/gen/methods/gen_methods.ss:497 interface dispatch 入口
//      `objClass != "" && ifaceMethodsCG.has(objClass) == 1` 因 objClass="" 第一项失败不进
//   3. bootstrap/gen/methods/gen_methods.ss:565 fallback emit `; TODO: method call .${method}`
//      + return "0" 替代 method call IR(read 路径全断链)
//
// **Phase 2 修法 target file:line list**(LOC 极小 +1 行,与 D162 §F7 修法系列同源 corner case):
//   - PRIMARY: bootstrap/gen/gen_types.ss:249 加一行
//       `if (fType != "" && ifaceMethodsCG.has(fType) == 1) { return fType }`
//     复用范式见同文件 line 167(IDENT 分支)/ 200-201(METHOD_CALL)/ 211-212(INDEX_ACCESS)/
//     224-225(TERNARY)— 全部已用 `ifaceMethodsCG.has` 双检 ifaceType return field type,
//     仅 MEMBER_ACCESS 分支漏 — 一处补齐对称
//   - 守护:./build.sh bootstrap 三阶段固定点 stage2==stage3 + 14 reflection 指标 no regression
//
// **D163 §A.2 H1 假设修正**:从 "GEP offset 错位" 修为 "MEMBER_ACCESS 接口字段 type
// resolver 漏检 ifaceMethodsCG → method call fall through 到 TODO fallback"。Phase 2 落档前
// 写入 D163.md 通过 §F 一条远期 followup 锚收关(本 Phase 1 不动 D163 §A.2 假设)。
//
// 3 case 覆盖:
//   Case 1 单 iface field write — minimum repro 移植主复现(extends Parent + : Iface + own ifaceField)
//   Case 2 多 iface field write — 多 own ifaceField 同形 复现
//   Case 3 nested extends + iface impl — 三层 chain Grandchild → Child → Parent 同形复现

import { test, assertEqual, assertTrue } from "@/lib/test"

// ── 共享接口和工具 class ──

interface BoxD163 {
    function fetch(): int
}

class StubBoxD163 : BoxD163 {
    z: int
    function fetch(): int { return 0 }
}

class RealBoxD163 : BoxD163 {
    v: int
    function fetch(): int { return this.v }
}

interface TriggerD163 {
    function go(): int
}

// ── Case 1: 单 iface-typed own field write/read(minimum repro 移植主形态) ──

class ParentD163 {
    p1: int
}

class ChildD163 extends ParentD163 : TriggerD163 {
    box: BoxD163

    function go(): int {
        const newBox: BoxD163 = new RealBoxD163(99)
        this.box = newBox
        return this.box.fetch()
    }
}

// ── Case 2: 多 iface-typed own field write/read(box1 + box2) ──

class Child2D163 extends ParentD163 : TriggerD163 {
    box1: BoxD163
    box2: BoxD163

    function go(): int {
        const newBox1: BoxD163 = new RealBoxD163(10)
        const newBox2: BoxD163 = new RealBoxD163(20)
        this.box1 = newBox1
        this.box2 = newBox2
        return this.box1.fetch() + this.box2.fetch()
    }
}

// ── Case 3: nested 三层 extends + iface impl 同形(Grandchild own iface field) ──

class GrandparentD163 {
    g1: int
}

class MiddleD163 extends GrandparentD163 {
    m1: int
}

class GrandchildD163 extends MiddleD163 : TriggerD163 {
    box: BoxD163

    function go(): int {
        const newBox: BoxD163 = new RealBoxD163(77)
        this.box = newBox
        return this.box.fetch()
    }
}

function main() {
    test("D163 Case 1 — single iface-typed own field write/read", () => {
        const stub: BoxD163 = new StubBoxD163(0)
        const c = new ChildD163(0, stub)
        const r = c.go()
        // Phase 1 RED:r=0(gen_types.ss:248-249 漏 ifaceMethodsCG.has → fallback emit TODO + 0)
        // Phase 2 修法后 GREEN:r=99
        assertEqual(r, 99)
    })

    test("D163 Case 2 — multi iface-typed own field write/read", () => {
        const stub1: BoxD163 = new StubBoxD163(0)
        const stub2: BoxD163 = new StubBoxD163(0)
        const c = new Child2D163(0, stub1, stub2)
        const r = c.go()
        // Phase 1 RED:r=0;Phase 2 修法后 GREEN:r=30(10+20 — 多 iface field 同形复现)
        assertEqual(r, 30)
    })

    test("D163 Case 3 — nested extends + iface impl + own iface field same form", () => {
        const stub: BoxD163 = new StubBoxD163(0)
        const gc = new GrandchildD163(0, 0, stub)
        const r = gc.go()
        // Phase 1 RED:r=0;Phase 2 修法后 GREEN:r=77(三层 chain 形态同根因复现)
        assertEqual(r, 77)
    })
}
