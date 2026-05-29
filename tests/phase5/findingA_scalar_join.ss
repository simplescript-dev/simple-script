import { assertEq } from "./import/asserts"

// ════════════════════════════════════════════════════════════════════════
// finding A(D171 收口验收 oracle 发现) — runtime scalar 数组 .join(sep) 段错根因修复回归
//
// RED(修复前):`let a=[1,2,3]; a.join("-")` → Segmentation fault(exit 139)。
//   int/double/bool 数组全崩,string 正常;comptime 同式正确 "1-2-3"(oracle 反转)。
// 根因(双层):
//   R1 结构错位 — array.join 错置 genStringMethod(无类型信息)被 dispatch 截胡,
//      无条件 _ss_join(List<string>) 把 scalar 位值当 String* 解引用 → 段错。
//   R1b 推断路径 — inferArrayElemType 不处理 ARRAY_LIT,`let a=[1,2,3]` varType
//      退化为 "ptr" 丢元素类型(显式 Array<int> 标注路径不受影响)。
// 修复:join 归位 dispatch type-dependent 区(持 objId 按 inferArrayElemType 分派
//   typed prelude 变体 _ss_joinInt/Double/Bool)+ inferArrayElemType 补 ARRAY_LIT 首元素推断。
//
// bool 显示 "1"/"0" 而非 "true"/"false" = genExprAsString bool 分支既有缺陷(模板插值
//   `${true}` 同样输出 "1"),先于 join 存在,非阻挡本段段错核心 → 独立立项 I033。
// ════════════════════════════════════════════════════════════════════════

function main() {
    // ── 推断路径(let x=[字面量] 无标注)= RED 的精确复现路径 ──
    let ai = [1, 2, 3]
    assertEq(ai.join("-"), "1-2-3", "int arr join (inferred)")

    let ad = [1.5, 2.5]
    assertEq(ad.join("-"), "1.5-2.5", "double arr join (inferred)")

    // bool: 字面量推断为 int(TRUE_LIT inferType="int")→ ss_joinInt → "1"/"0"(R2/I033)
    let ab = [true, false]
    assertEq(ab.join("-"), "1-0", "bool arr join (inferred, R2 1/0 — I033)")

    // string 回归保护(元素本是 ptr,_ss_join 默认路径)
    let as = ["x", "y", "z"]
    assertEq(as.join("-"), "x-y-z", "string arr join (inferred)")

    // ── 边界:单元素 / 空数组 ──
    let one = [7]
    assertEq(one.join("-"), "7", "single int elem")

    let emptyArr: Array<int> = []
    assertEq(emptyArr.join("-"), "", "empty arr → empty string")

    // ── 显式标注路径(let x: Array<T> = [...]) ──
    let bi: Array<int> = [4, 5, 6]
    assertEq(bi.join(","), "4,5,6", "int arr join (annotated)")

    let bd: Array<double> = [0.5, 1.25]
    assertEq(bd.join("|"), "0.5|1.25", "double arr join (annotated)")

    // ── 多字符分隔符 + 单元素无分隔 ──
    assertEq([10, 20].join(", "), "10, 20", "multi-char sep")

    // ── comptime/runtime parity(oracle 一致) ──
    assertEq(comptime { return [1, 2, 3].join("-") }, ai.join("-"), "comptime==runtime parity (int)")

    println("findingA_scalar_join: all pass")
}
