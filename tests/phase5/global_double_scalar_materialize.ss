import { assertEq, assertApprox } from "./import/asserts"

// ════════════════════════════════════════════════════════════════════════
// global_double_scalar_materialize (I036) — 全局非字面量 double 标量物化 parity 回归
//
// RED(修复前):全局 `let g=1.5+2.5` 等非字面量 double 初值 → gen_decls.ss genGlobalVar
//   else 分支 realType=double 落最终 else `@g = global ptr null` + emitGlobalInits
//   `store ptr <doubleval>` → llc "floating point constant invalid for type" 硬失败
//   (实测 `store ptr 0x4010000000000000, ptr @g`,0x4010..=4.0 的 IEEE754 位)。
// 根因(单文件 2 站点,gen_decls.ss 全局物化接口边界,与 int/bool 完全同构仅类型差):
//   A. genGlobalVar else 分支:realType=double 缺分支 → 物化 ptr slot(值是 double)。补 global double 0.0。
//   B. emitGlobalInits:gVarType=double 缺分支 → store ptr <doubleval>。对称补 store double。
//   读取侧 genIdent 经 getVarType→ssTypeToLLVM 自动 load double(COMPTIME_EXPR double 全局
//   gen_decls.ss:260 + 局部 alloca double 已验此路径)。
// double 值来源恒合法 LLVM double 操作数:折叠常量 `0x<16hex>` 精确位(interp_value.ss:39)/
//   算术 fadd double 寄存器 / array-get bitcast i64→double 寄存器 / call double 寄存器。
// 与 global_scalar_materialize(int/bool 物化)+ I035(元素类型传播)同函数,接口层根因同族;
//   全局 int/bool/double 标量物化 3 类型对称。
// ════════════════════════════════════════════════════════════════════════

function dfn(): double { return 3.14 }

// ── 全局非字面量 double 初值(RED:全部 llc 硬失败)──
let gAdd = 1.5 + 2.5         // arithmetic add → 4.0(整数值 double,显示 "4")
let gSub = 10.0 - 3.5        // arithmetic sub → 6.5
let gMul = 2.0 * 3.0         // arithmetic mul → 6.0(显示 "6")
let gDiv = 7.5 / 2.5         // arithmetic div → 3.0(显示 "3")
let gBase = 2.0              // literal double(对照,本就工作)
let gScaled = gBase * 3.0    // 引用其他全局 double → 6.0
let gNeg = 1.0 - 4.5         // → -3.5(负值,符号位往返)

// ── 无标注全局 double 数组 array-get(I035 后元素类型已传播 Array<double>,崩在物化侧)──
let gArr = [1.5, 2.5, 3.5]
let gIdx = gArr[1]           // unannotated array-get → double 2.5

// ── 全局 double 函数调用 ──
let gCall = dfn()            // double fn-call → 3.14

function main() {
    // ── 算术显示 parity(整数值 double 显 "4"/"6"/"3",非整 "6.5"/"-3.5") ──
    assertEq(`${gAdd}`, "4", "global double add 1.5+2.5 → 4")
    assertEq(`${gSub}`, "6.5", "global double sub 10.0-3.5 → 6.5")
    assertEq(`${gMul}`, "6", "global double mul 2.0*3.0 → 6")
    assertEq(`${gDiv}`, "3", "global double div 7.5/2.5 → 3")
    assertEq(`${gScaled}`, "6", "global double ref-other-global gBase*3.0 → 6")
    assertEq(`${gNeg}`, "-3.5", "global double negative 1.0-4.5 → -3.5")

    // ── array-get / fn-call 显示 parity ──
    assertEq(`${gIdx}`, "2.5", "unannotated global double array-get gArr[1] → 2.5")
    assertEq(`${gCall}`, "3.14", "global double fn-call dfn() → 3.14")

    // ── 直接 double 值断言(assertApprox,证类型自洽 load double 非 ptr 位泄露)──
    assertApprox(gAdd, 4.0, "global double add value")
    assertApprox(gSub, 6.5, "global double sub value")
    assertApprox(gScaled, 6.0, "global double ref-other-global value")
    assertApprox(gNeg, -3.5, "global double negative value")
    assertApprox(gIdx, 2.5, "unannotated global double array-get value")
    assertApprox(gCall, 3.14, "global double fn-call value")

    // ── 全局 double 参与局部表达式(证类型流过全链,非 ptr 位)──
    let combined = gAdd + gIdx       // 4.0 + 2.5 → 6.5
    assertApprox(combined, 6.5, "global double consumed in local expr")

    // ── comptime==runtime parity(comptime double oracle 一致)──
    assertApprox(gAdd, comptime { return 1.5 + 2.5 }, "comptime==runtime double add parity")
    assertApprox(gIdx, comptime { let ca = [1.5, 2.5, 3.5]; return ca[1] }, "comptime==runtime double array-get parity")

    // ── 局部无标注 double(working-reference;证 global/local 物化对称)──
    let lAdd = 1.5 + 2.5
    let lArr = [1.5, 2.5, 3.5]
    let lIdx = lArr[1]
    assertApprox(lAdd, 4.0, "local double arithmetic (symmetry with global)")
    assertApprox(lIdx, 2.5, "local double array-get (symmetry with global)")

    println("global_double_scalar_materialize: all pass")
}
