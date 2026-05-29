import { assertEq } from "./import/asserts"

// ════════════════════════════════════════════════════════════════════════
// global_array_elem_infer (I035) — 无标注全局数组 var 元素类型传播 parity 回归
//
// RED(修复前):无标注全局 `let a=[10,20,30]; let m=a[1]` → genGlobalVar 不传播 `a`
//   的元素类型(varType 退 "ptr")→ inferType(a[1]) 退化返 i64 → @m=global ptr null +
//   emitGlobalInits store ptr <i64> → llc "'%N' defined with type 'i64' but expected 'ptr'" 硬失败。
// 根因(接口层,gen_decls.ss var-decl 元素类型传播契约不对称):genVarDecl(局部,:587-593)
//   honors `typeAnn=="" && initType=="ptr"` → inferArrayElemType → setVarType(Array<elem>);
//   genGlobalVar(全局)原缺此传播。
// 修复:genGlobalVar else 分支补 `realType=="ptr"` → inferArrayElemType → gType=Array<elem>
//   (镜像 genVarDecl:587-593,SSoT 化 local/global var decl 元素类型传播契约,不在 array-get
//   物化点补回查 workaround)。
// 范围外(独立根因,不混入):全局非字面量 **double** 标量物化(`let g=1.5+2.5` / double
//   array-get 同崩 = materialization 侧 ptr slot store double,非 propagation 侧)→ 立项 I036。
// ════════════════════════════════════════════════════════════════════════

// ── 无标注全局 int 数组(RED:整组 llc 硬失败)──
let gIntArr = [10, 20, 30]
let gI0 = gIntArr[0]                 // → 10
let gI1 = gIntArr[1]                 // → 20
let gI2 = gIntArr[2]                 // → 30
let gSum = gIntArr[0] + gIntArr[2]   // → 40(array-get 值入算术,证元素类型 i32 自洽)

// ── 无标注全局 string 数组(元素类型传播对 string 同样生效:ptr slot + store ptr)──
let gStrArr = ["alpha", "beta", "gamma"]
let gS1 = gStrArr[1]                 // → "beta"

// ── 无标注全局 bool 数组(元素类型 bool → i32 物化 + "true"/"false" 显示)──
let gBoolArr = [true, false, true]
let gB0 = gBoolArr[0]                // → true

function main() {
    // ── int array-get 显示 + 直接值 parity(证 @gI*=global i32 + store i32 类型自洽)──
    assertEq(`${gI0}`, "10", "unannotated global int array [0] display")
    assertEq(`${gI1}`, "20", "unannotated global int array [1] display")
    assertEq(`${gI2}`, "30", "unannotated global int array [2] display")
    assertEq(gI1, 20, "unannotated global int array [1] direct value")
    assertEq(gSum, 40, "unannotated global int array-get into arithmetic")

    // ── string array-get(元素类型 string 传播 → ptr slot,显示 + 值)──
    assertEq(gS1, "beta", "unannotated global string array [1] value")
    assertEq(`${gS1}`, "beta", "unannotated global string array [1] display")

    // ── bool array-get(元素类型 bool 传播 → "true" 显示,非 "1")──
    assertEq(`${gB0}`, "true", "unannotated global bool array [0] display")

    // ── comptime==runtime parity:runtime 全局 array-get == comptime 数组求值 oracle ──
    assertEq(gI1, comptime { let ca = [10, 20, 30]; return ca[1] }, "comptime==runtime parity: array-get")

    // ── 局部无标注 array-get(working-reference;证 global/local 元素类型传播对称)──
    let lArr = [100, 200, 300]
    let lM = lArr[1]
    assertEq(lM, 200, "local unannotated array-get (symmetry with global)")

    println("global_array_elem_infer: all pass")
}
