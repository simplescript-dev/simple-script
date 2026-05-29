import { assertEq } from "./import/asserts"

// ════════════════════════════════════════════════════════════════════════
// I034 — runtime comparison/logical→bool 推断残留(D171 §收口验收 行为级穷举 parity 零偏离 兑现)— 回归
//
// RED(修复前):comparison(Eq/Ne/Lt/Gt/Le/Ge)+ logical(And/Or)BINOP 经 gen_types.ss:376-378
//   inferType(BINARY) 折叠成 "int" → `let b=1<2` 传播 int / `[1<2,3>4]` dispatch ss_joinInt /
//   `${b}`、拼接、join 三 sink 落 ss_int_to_string 出 "1"/"0",偏离 comptime interpNewBool
//   (interp_op.ss:50-55 含短路)+ JS String(1<2)="true"。是 I033 字面量(line 278)/
//   comptime-bool-return(line 324)同族第三折叠站点。
// 根因(单站点 A + 假设破裂闭合,gen_types.ss only,零新 runtime IR):
//   站点 A. gen_types.ss:377 comparison/logical/instanceof BINOP return "int" → "bool"
//     (bool@IR=i32,各 cmp/短路/instanceof 出口 zext i1→i32 无 ABI break)→ bool 类型流过
//     var 传播 / 数组 join dispatch / 显示全链 / Not-unary。
//   假设破裂闭合. gen_types.ss:383 算术/位运算 fallthrough binLt=="bool"→"int"(JS bool→number
//     强制;防 `(a<b)+1` 误显 "true",附带闭合 I033-latent `true+1` 漏)。
// 显示侧 genExprAsString bool 分支(exprs_str_conv.ss:35)+ ss_joinBool(gen_methods.ss:544)
//   + Not-unary 委派(gen_types.ss:586)I033/findingA 已建,复用零新 IR/函数。
// ════════════════════════════════════════════════════════════════════════

class Animal { name: string = "a" }
class Dog { tag: int = 1 }

function main() {
    // 变量操作数(走 runtime 路径,非 const-fold)
    let a = 5
    let b = 3

    // ── sink 1 模板插值:comparison 全 6 运算符(inferred var)──
    let lt = a < b
    assertEq(`${lt}`, "false", "tmpl a<b")
    let gt = a > b
    assertEq(`${gt}`, "true", "tmpl a>b")
    let le = a <= b
    assertEq(`${le}`, "false", "tmpl a<=b")
    let ge = a >= b
    assertEq(`${ge}`, "true", "tmpl a>=b")
    let eq = a == b
    assertEq(`${eq}`, "false", "tmpl a==b")
    let ne = a != b
    assertEq(`${ne}`, "true", "tmpl a!=b")

    // ── logical &&/||(含短路)──
    let andT = (a > b) && (b < a)
    assertEq(`${andT}`, "true", "tmpl && both true")
    let andF = (a < b) && (b < a)
    assertEq(`${andF}`, "false", "tmpl && short-circuit false")
    let orT = (a < b) || (b < a)
    assertEq(`${orT}`, "true", "tmpl || one true")
    let orF = (a < b) || (a == b)
    assertEq(`${orF}`, "false", "tmpl || both false")

    // ── Not-unary !(comparison)(委派站点 A 自动得 bool)──
    let notLt = !(a < b)
    assertEq(`${notLt}`, "true", "tmpl !(a<b)")

    // ── sink 2 字符串拼接(+)──
    assertEq("v=" + (a < b), "v=false", "concat string + comparison")
    assertEq((a > b) + "!", "true!", "concat comparison + string")

    // ── 多片段模板 ──
    assertEq(`${lt}-${gt}`, "false-true", "multi-frag tmpl comparison")

    // ── sink 3 数组 join(comparison var/inline 元素 → ss_joinBool)──
    assertEq([lt, gt].join("-"), "false-true", "join comparison vars")
    assertEq([a < b, a > b, a == b].join("|"), "false|true|false", "join inline comparison")

    // ── 假设破裂闭合:算术/位运算 bool 操作数 → int(非 bool)──
    let arith = (a < b) + 1          // false(0)+1 = 1,int 非 "true"
    assertEq(`${arith}`, "1", "arith (a<b)+1 → int(假设破裂闭合)")
    let arith2 = (a > b) + 10        // true(1)+10 = 11
    assertEq(`${arith2}`, "11", "arith (a>b)+10 → int")
    let boolLit = true + 1           // I033-latent:bool 字面量算术 → int 2
    assertEq(`${boolLit}`, "2", "arith true+1 → int(I033-latent 闭合)")

    // ── instanceof(同 line 376 sibling;JS String(x instanceof Y)→bool;无 comptime oracle)──
    let an = new Animal()
    let isAn = an instanceof Animal
    assertEq(`${isAn}`, "true", "tmpl instanceof match")
    let isDog = an instanceof Dog
    assertEq(`${isDog}`, "false", "tmpl instanceof no-match")

    // ── comptime==runtime parity(同值显示一致 = 零偏离)──
    let ct_lt = comptime { return 5 < 3 }
    assertEq(`${lt}`, `${ct_lt}`, "parity: runtime a<b == comptime 5<3")
    let ct_and = comptime { return (5 > 3) && (3 < 5) }
    assertEq(`${andT}`, `${ct_and}`, "parity: runtime && == comptime &&")
    let ct_join = comptime { let z = [5 < 3, 5 > 3]; return z.join("-") }
    assertEq([lt, gt].join("-"), ct_join, "parity: runtime join == comptime join")
}
