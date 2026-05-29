// D171 Phase 2: spread 数组字面量 [...a, x] 在 comptime 求值 + .length 读长度。
// RED(改前): `[...a, 3].length` 静默返 0(应 3)。最小隔离证明:spread 展平本就工作
// (b[0..2] 正确),断流在 .length —— 旧路径经 interpAsStr(读 tvS1,数组恒空)split(",")
// 对任何 ct 数组恒返 0。改走权威 interpArrayLen(tvI2)。走 D093 统一 evalExpr,不新开 ct* 注册表。

function main() {
    // 1) Phase 2 RED canonical case:spread 后 .length(改前静默返 0,应 3)
    const lenSpread = comptime {
        const a = [1, 2]
        const b = [...a, 3]
        return b.length
    }
    if (lenSpread != 3) { exit(1) }

    // 2) spread 元素值正确(展平把 a 的元素 + 字面量按序入 arr)
    const e0 = comptime { const a = [1, 2]; const b = [...a, 3]; return b[0] }
    const e1 = comptime { const a = [1, 2]; const b = [...a, 3]; return b[1] }
    const e2 = comptime { const a = [1, 2]; const b = [...a, 3]; return b[2] }
    if (e0 != 1) { exit(1) }
    if (e1 != 2) { exit(1) }
    if (e2 != 3) { exit(1) }

    // 3) spread 在中间:[1, ...a, 9](混合位置展平)
    const lenMid = comptime {
        const a = [2, 3]
        const b = [1, ...a, 9]
        return b.length
    }
    if (lenMid != 4) { exit(1) }

    // 4) 多个 spread:[...a, ...a]
    const lenDouble = comptime {
        const a = [5, 6]
        const b = [...a, ...a]
        return b.length
    }
    if (lenDouble != 4) { exit(1) }

    // 5) 普通(非 spread)数组 .length 同根因被一起修好(改前亦静默返 0)
    const lenPlain = comptime {
        const a = [10, 20, 30]
        return a.length
    }
    if (lenPlain != 3) { exit(1) }

    println("d171 comptime spread array: ok")
}
