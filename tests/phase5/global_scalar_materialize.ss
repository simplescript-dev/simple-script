import { assertEq } from "./import/asserts"

// ════════════════════════════════════════════════════════════════════════
// global_scalar_materialize(D171 §收口验收 comparison-area finding) —
// 全局非字面量 int/bool 初值物化 parity 回归
//
// RED(修复前):全局 `let g=1<2` 等非字面量 int/bool 初值 → gen_decls.ss genGlobalVar
//   else 分支无条件 `@g = global ptr null` + emitGlobalInits `store ptr <i32val>` →
//   llc "integer constant must have integer type" 硬失败(整类不可编译)。
// 根因(单文件 2 站点,gen_decls.ss 全局物化接口边界):
//   A. genGlobalVar else 分支:realType=int/bool 物化 ptr slot(值是 i32)。改 global i32 0。
//   B. emitGlobalInits:store ptr <i32val>。对称改 store i32。
//   读取侧 genIdent 经 getVarType→ssTypeToLLVM 自动 load i32(literal int 全局已验此路径)。
// bool@IR 仍 i32(ssTypeToLLVM/mangling 不变,无 ABI break);与 I033/I034 接口层根因同族。
// ════════════════════════════════════════════════════════════════════════

function gfn(): int { return 7 }

// ── 全局非字面量 int/bool 初值(RED:全部 llc 硬失败)──
let gCmpLt = 1 < 2            // comparison → bool true
let gCmpGt = 5 > 9           // comparison → bool false
let gEq = 3 == 3             // comparison → bool true
let gNe = 3 != 4             // comparison → bool true
let gAnd = true && false     // logical → bool false
let gOr = false || true      // logical → bool true
let gA = 3                   // literal int(对照,本就工作)
let gB = 4
let gArith = gA + gB         // arithmetic → int 7
let gArrA: Array<int> = [10, 20, 30]
let gIdx = gArrA[1]          // array-get(标注 Array<int> → 推断成功)→ int 20
let gCall = gfn()            // int function call → int 7
// 注:无标注 `let a=[..]; let m=a[1]` 全局 array-get 失败 = 独立根因(全局数组
// 元素类型推断未传播,非标量物化)→ 立项 I035,不混入本 finding。

function main() {
    // ── comparison/逻辑 显示 parity(comptime/JS oracle "true"/"false") ──
    assertEq(`${gCmpLt}`, "true", "global comparison 1<2 → true")
    assertEq(`${gCmpGt}`, "false", "global comparison 5>9 → false")
    assertEq(`${gEq}`, "true", "global comparison 3==3 → true")
    assertEq(`${gNe}`, "true", "global comparison 3!=4 → true")
    assertEq(`${gAnd}`, "false", "global logical && → false")
    assertEq(`${gOr}`, "true", "global logical || → true")

    // ── int 算术/array-get/函数调用 显示数值 ──
    assertEq(`${gArith}`, "7", "global arithmetic gA+gB → 7")
    assertEq(`${gIdx}`, "20", "global array-get gArr[1] → 20")
    assertEq(`${gCall}`, "7", "global int fn-call gfn() → 7")

    // ── 直接值断言(非仅显示,证类型自洽 load i32)──
    assertEq(gArith, 7, "global arithmetic value")
    assertEq(gIdx, 20, "global array-get value")
    assertEq(gCall, 7, "global int fn-call value")

    // ── 全局 bool 参与表达式(局部消费,证类型流过全链)──
    let combined = gCmpLt && gOr        // true && true → true
    assertEq(`${combined}`, "true", "global bool consumed in local expr")

    // ── comptime==runtime parity(oracle 一致,bool@IR=i32 值比对)──
    assertEq(gCmpLt, comptime { return 1 < 2 }, "comptime==runtime comparison value parity")
    assertEq(gArith, comptime { return 3 + 4 }, "comptime==runtime arithmetic value parity")

    println("global_scalar_materialize: all pass")
}
