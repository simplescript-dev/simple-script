// I011 — annotation double arg comptime materialize 回归守护
// D127 §A.1 I003 收尾发现的 pre-existing bug:getDouble 在 evalAnnotationArg 已实装
// (DOUBLE_LIT → interpNewDouble),但 comptime materialize 侧曾取 tvS1(string slot)而非
// double exact-bits → `return double_tv` 产错 IR / llc 崩(i003 测试头注释点名 gen_types.ss:261)。
// 根因由 D171 finding C + I032 修复:materialize()(interp_value.ss:39)改走 exact-bits hex
// `0x<16hex>` + gen_types COMPTIME_EXPR double 分支补齐,消除"取错 slot"+"%g 丢精"双根。
// 本测试钉住 I011 范围:正 double annotation arg + getDouble + comptime return 物化 bit-exact。
// (负 double 字面量 `-2.5` 是 UNARY,evalAnnotationArg 缺该分支 → 立项 I039,不在本测试范围。)
import { assertEqual } from "@/lib/test"

@M(pi = 3.14, half = 1.5, tenth = 0.1, big = 3.14159)
class P { x: int }

function main() {
    test("I011 — getDouble 整洁 double comptime return 物化", () => {
        const r = comptime {
            let acc = 0.0
            for (a in P.annotations) { acc = a.args.getDouble("pi") }
            return acc
        }
        assertEqual(r, 3.14)
    })
    test("I011 — getDouble 非精确可表示 0.1 bit-exact(无 %g 丢精)", () => {
        const r = comptime {
            let acc = 0.0
            for (a in P.annotations) { acc = a.args.getDouble("tenth") }
            return acc
        }
        assertEqual(r, 0.1)
    })
    test("I011 — getDouble 多位有效数字 3.14159 不截断", () => {
        const r = comptime {
            let acc = 0.0
            for (a in P.annotations) { acc = a.args.getDouble("big") }
            return acc
        }
        assertEqual(r, 3.14159)
    })
    test("I011 — getDouble 进算术中间值不丢精 + comptime==runtime parity", () => {
        const sum = comptime {
            let acc = 0.0
            for (a in P.annotations) { acc = a.args.getDouble("half") + a.args.getDouble("tenth") }
            return acc
        }
        assertEqual(sum, 1.6)
        // runtime oracle 对照:同算术非 comptime,bit-exact 相等证 comptime 物化忠实
        let h = 1.5
        let t = 0.1
        assertEqual(sum, h + t)
    })
}
