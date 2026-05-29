import { assertEq } from "./import/asserts"

// ════════════════════════════════════════════════════════════════════════
// finding B (D171 §收口验收) — runtime Array.slice 负 start/end 归一 + 单参支持
//
// 根因:runtime ss_arraySlice (gen_rt_array.ss) 原仅 end>len 上界 clamp,缺负索引
// 归一 (s<0→len+s / e<0→len+e) + s 下界 clamp,致 slice(1,-1) 返空、slice(-3,-1)
// 越界垃圾、负 start 读未初始化内存,偏离 comptime ctArrayMethod slice
// (exprs_ct_builtin.ss:156-159) + JS slice 语义。
//
// 修复 = runtime 函数边界归一(单一真相源)+ codegen 单参缺省 sentinel + checker (1,2)。
// 本套件锁 GREEN 全用例 + runtime==comptime parity,永久封堵负索引 slice 双轨回归。
// ════════════════════════════════════════════════════════════════════════

function main() {
    let a = [10, 20, 30, 40]

    // ── 负 end 归一(RED 主用例) ──
    assertEq(a.slice(1, -1).join("-"), "20-30", "slice(1,-1) 负 end")
    // ── 单参负 start ──
    assertEq(a.slice(-2).join("-"), "30-40", "slice(-2) 单参负 start")
    // ── 双负 ──
    assertEq(a.slice(-3, -1).join("-"), "20-30", "slice(-3,-1) 双负")
    // ── 单参正 ──
    assertEq(a.slice(1).join("-"), "20-30-40", "slice(1) 单参正")
    assertEq(a.slice(2).join("-"), "30-40", "slice(2) 单参正")
    // ── 越界负 start clamp 下界 0 ──
    assertEq(a.slice(-10, 2).join("-"), "10-20", "slice(-10,2) 越界负 start clamp 0")
    // ── 越界负 end → 空 ──
    assertEq(a.slice(0, -100).join("-"), "", "slice(0,-100) 越界负 end 空")
    // ── 正索引 sanity(无回归) ──
    assertEq(a.slice(0, 2).join("-"), "10-20", "slice(0,2) 正索引无回归")
    assertEq(a.slice(1, 100).join("-"), "20-30-40", "slice(1,100) 越界正 end clamp")
    // ── 变量负 end:证明 runtime 归一(非 codegen 字面量 hack) ──
    let neg = 0 - 1
    assertEq(a.slice(1, neg).join("-"), "20-30", "slice(1, 变量 -1) runtime 归一")
    // ── 非变异:slice 不改原数组 ──
    assertEq(a.length(), 4, "slice 非变异原数组")
    // ── length() 走归一后长度 ──
    assertEq(a.slice(1, -1).length(), 2, "slice(1,-1).length()")

    // ── runtime == comptime parity(oracle 对称,A/B 中 comptime 更正确) ──
    assertEq(a.slice(1, -1).join("-"), comptime { return [10, 20, 30, 40].slice(1, 0 - 1).join("-") }, "parity slice(1,-1)")
    assertEq(a.slice(-3, -1).join("-"), comptime { return [10, 20, 30, 40].slice(0 - 3, 0 - 1).join("-") }, "parity slice(-3,-1)")
    assertEq(a.slice(-10, 2).join("-"), comptime { return [10, 20, 30, 40].slice(0 - 10, 2).join("-") }, "parity slice(-10,2)")
    assertEq(a.slice(0, -100).join("-"), comptime { return [10, 20, 30, 40].slice(0, 0 - 100).join("-") }, "parity slice(0,-100) 空")

    println("findingB_slice_negative_end: all pass")
}
