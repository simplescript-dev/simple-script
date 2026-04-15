// D092 §Q1 最小例子 — SEMA 架构下 comptime dispatcher 能跑 BINARY 常量折叠
// 验证 Zig 路线 §核心验证 Q1 "有新 SS 语法能在 comptime 里跑了吗"
function main() {
    const x = comptime { return 1 + 2 }
    if (x != 3) { throw("comptime int add fold failed") }

    const y = comptime { return 10 - 3 }
    if (y != 7) { throw("comptime int sub fold failed") }

    const z = comptime { return 4 * 5 }
    if (z != 20) { throw("comptime int mul fold failed") }

    const w = comptime { return 20 / 4 }
    if (w != 5) { throw("comptime int div fold failed") }

    const m = comptime { return 10 % 3 }
    if (m != 1) { throw("comptime int mod fold failed") }

    const s = comptime { return "hello" }
    if (s != "hello") { throw("comptime string literal failed") }

    const b = comptime { return 1 < 2 }
    if (!b) { throw("comptime int compare fold failed") }
}
