import { assertEq } from "./import/asserts"

// ════════════════════════════════════════════════════════════════════════
// comptime-scalar bool-return 折叠(D171 §收口验收 I033 残余 backlog 兑现)— 回归
//
// RED(修复前):`comptime { return true }` 经 gen_types.ss:324 inferType(COMPTIME_EXPR)
//   把 interpType=="bool" 的返回值折叠成 "int" 类型字符串 → ${b}/拼接/join 三显示 sink
//   经 inferType 拿不到 "bool" → 落 ss_int_to_string 出 "1"/"0",偏离 comptime oracle
//   interpToStr("true"/"false")+ JS String(true)。是 I033 runtime 字面量折叠的镜像同根。
// 根因(两站点,单一概念根 = gen 层把 comptime bool-return 折叠成 int):
//   A. gen_types.ss inferType COMPTIME_EXPR:ceType=="bool" 原 set/return "int" → 改 "bool"
//      (literal 仍 tvIntOf=1/0 不变,bool@IR=i32 无 ABI break)→ bool 类型流过三 sink。
//   B. gen_decls.ss 全局物化路径补 bool case → global i32(防站点 A 改后落 else→ptr null regression)。
// 显示侧 genExprAsString bool 分支(exprs_str_conv.ss:35)+ ss_joinBool I033 已建,复用零新 IR。
// ════════════════════════════════════════════════════════════════════════

// ── 全局 scope comptime bool-return(站点 B:防 global ptr null regression) ──
let gtrue = comptime { return true }
let gfalse = comptime { return false }

function main() {
    // ── sink 1 模板插值:function-local comptime bool-return(RED 主) ──
    let bt = comptime { return true }
    assertEq(`${bt}`, "true", "tmpl local comptime{return true}")
    let bf = comptime { return false }
    assertEq(`${bf}`, "false", "tmpl local comptime{return false}")

    // ── 全局 scope(站点 B) ──
    assertEq(`${gtrue}`, "true", "tmpl global comptime{return true}")
    assertEq(`${gfalse}`, "false", "tmpl global comptime{return false}")

    // ── comparison comptime-return(interpNewBool → 站点 A) ──
    let lt = comptime { return 1 < 2 }
    assertEq(`${lt}`, "true", "tmpl comptime 1<2")
    let gt = comptime { return 5 > 9 }
    assertEq(`${gt}`, "false", "tmpl comptime 5>9")
    let eq = comptime { return 3 == 3 }
    assertEq(`${eq}`, "true", "tmpl comptime 3==3")

    // ── logical comptime-return(short_circuit → bool tv) ──
    let andF = comptime { return true && false }
    assertEq(`${andF}`, "false", "tmpl comptime true&&false")
    let orT = comptime { return true || false }
    assertEq(`${orT}`, "true", "tmpl comptime true||false")
    let andSc = comptime { return false && true }
    assertEq(`${andSc}`, "false", "tmpl comptime false&&true (短路)")

    // ── sink 2 字符串拼接(+) ──
    assertEq("v=" + bt, "v=true", "concat string + comptime bool")
    assertEq(bf + "!", "false!", "concat comptime bool + string")

    // ── 多片段模板 ──
    assertEq(`${bt}-${bf}`, "true-false", "multi-frag tmpl comptime bool")

    // ── sink 3 数组 join(comptime bool var 元素 → ss_joinBool) ──
    assertEq([bt, bf].join("-"), "true-false", "join comptime bool vars")
    assertEq([bt, bt, bf].join("|"), "true|true|false", "join 3 comptime bool")

    // ── comptime==runtime parity(同值显示一致 = 零偏离) ──
    let rt = true
    let rf = false
    assertEq(`${bt}`, `${rt}`, "parity: comptime true == runtime true 显示")
    assertEq(`${bf}`, `${rf}`, "parity: comptime false == runtime false 显示")
    assertEq([bt, bf].join("-"), [rt, rf].join("-"), "parity: join comptime == runtime")
}
