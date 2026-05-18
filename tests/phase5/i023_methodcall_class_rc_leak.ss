// I023 — METHOD_CALL 返 user class 的 over-retain (A) + chain-temp (B) RC 泄漏 leak-观测 RED。
//
// SS-LIM-6 功能测试只断言返值,GREEN 前后观测不到泄漏(泄漏不产生错值)。本测试用大循环
// 把泄漏放大到数百 MB,由外部探针量化(编译 → 后台运行 → 采样 /proc/<pid>/status 的
// VmHWM 峰值 RSS,VmHWM 单调故末次采样 ≈ 真峰值):
//
//   当前编译器(A/B 未修):峰值 RSS ≈ 275 MB(3M 迭代 × 每轮 ~3 个 Cell 泄漏)。
//   A+B 修复后:retain/release 平衡 → 对象复用/释放 → 峰值 RSS 有界(实测对照 ≈ 0.4 MB)。
//   对照:同结构循环改 new Cell() 直接分配(NEW_EXPR,isOwnedExpr 已正确判 owned)实测
//         峰值 RSS = 404 KB —— 证明循环脚手架本身有界,275 MB 全系 METHOD_CALL 泄漏。
//
// 泄漏模式必须放进 helper 函数:main 不跑 PIR(gen_decls.ss:129 `if (name != "main")`),
// main 的 class 局部走非-PIR 释放路径会混入无关噪声;helper 函数 pirActive=1,PIR 正确
// 管理 class 局部 → 干净隔离 I023 的 A/B 泄漏。
//
// 每次 leakRound 调用的泄漏(当前编译器):
//   A over-retain —— `const x = box.make()`:METHOD_CALL 返 owned user class,
//     isOwnedExpr 误判 borrowed → caller 再 ss_retain 一次 → rc 永 >= 1 → 永不 free。
//   B chain-temp —— `box.make().fresh()`:链式 receiver `box.make()` 是 owned Cell temp,
//     被 .fresh() 借用后无人 ss_release → 每轮泄漏一个 mimalloc block。
//   (`box.make().fresh()` 同时再触一次 A:结果 y 被 over-retain。)
//
// 作为测试套件成员:修复后大循环内存有界 → 正常完成 exit 0(冒烟)。泄漏量化判据是
// 外部 VmHWM 采样,见 docs/4-issues/I023-methodcall-class-rc-leak.md §待补验收。

class Cell {
    n: int
    // B: Cell 方法返新 user class —— 链式 receiver 场景。
    function fresh(): Cell {
        return new Cell(this.n + 1)
    }
}

class Box {
    base: int
    // A: user 方法返新分配 user class(owned)—— caller over-retain 入口。
    function make(): Cell {
        return new Cell(this.base)
    }
}

// helper(pirActive=1):泄漏模式在此隔离,PIR 正确调度 retain/release。
function leakRound(box: Box): int {
    // A: METHOD_CALL 返 Cell —— caller over-retain。
    const x = box.make()
    // B: box.make() 是 .fresh() 的链式 owned temp receiver(+ y 再触一次 A)。
    const y = box.make().fresh()
    return x.n + y.n
}

function main() {
    const box = new Box(7)
    let sink = 0
    let i = 0
    const N = 3000000
    while (i < N) {
        sink = sink + leakRound(box)
        i = i + 1
    }
    println("i023 leak probe: completed N iterations")
    if (sink == 0) { exit(1) }
}
