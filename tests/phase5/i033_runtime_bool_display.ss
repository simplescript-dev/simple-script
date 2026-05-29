import { assertEq } from "./import/asserts"

// ════════════════════════════════════════════════════════════════════════
// I033(D171 收口验收 finding A 衍生) — runtime bool→string 显示 parity 修复回归
//
// RED(修复前):runtime bool 经 genExprAsString 落到 ss_int_to_string → "1"/"0",
//   偏离 comptime oracle(interpToStr → "true"/"false")+ JS(String(true)="true")。
// 根因(两站点,单一概念根 = gen 层把 bool 折叠成 int 丢失类型):
//   A. gen_types.ss inferType:TRUE_LIT/FALSE_LIT 原返 "int" → `let b=true` var 传播 int +
//      `[true,false]` 元素 dispatch ss_joinInt → 显示路径永远拿不到 "bool"。改返 "bool"。
//   B. genExprAsString(exprs_str_conv.ss)无 bool 分支 → 任何 bool 值落 ss_int_to_string。
//      补 `if(vType=="bool") → ss_bool_to_string`(单一真相源,惠及模板/拼接/join/println)。
// bool@IR 仍是 i32(ssTypeToLLVM/mangling 不变,无 ABI break);仅显示 + 数组 join dispatch 变。
// ════════════════════════════════════════════════════════════════════════

function main() {
    // ── 模板插值:inferred + annotated(RED a:均曾输出 "1"/"0") ──
    let bi = true
    assertEq(`${bi}`, "true", "tmpl inferred let b=true")

    let bf = false
    assertEq(`${bf}`, "false", "tmpl inferred let b=false")

    let ba: bool = true
    assertEq(`${ba}`, "true", "tmpl annotated b:bool")

    // ── 字符串拼接(+) ──
    assertEq("v=" + bi, "v=true", "concat string + bool")
    assertEq(bf + "!", "false!", "concat bool + string")

    // ── 多片段模板 ──
    assertEq(`${bi}-${bf}`, "true-false", "multi-frag tmpl bool")

    // ── 数组 join:inferred(RED b:曾 ss_joinInt → "1-0") + annotated ──
    let arr = [true, false, true]
    assertEq(arr.join("-"), "true-false-true", "arr<bool> join (inferred)")

    let arr2: Array<bool> = [false, false]
    assertEq(arr2.join(","), "false,false", "arr<bool> join (annotated)")

    // ── comptime/runtime parity(oracle 一致) ──
    assertEq(comptime { return [true, false].join("-") }, "true-false", "comptime join oracle = true-false")
    assertEq(comptime { return [true, false].join("-") }, [true, false].join("-"), "comptime==runtime parity (bool)")

    println("i033_runtime_bool_display: all pass")
}
