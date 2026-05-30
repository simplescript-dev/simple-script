// I039 — annotation arg 负数字面量(UNARY)回归守护
// `-2.5` / `-10` 在 parser 是 UNARY(op="Neg", operand=DOUBLE_LIT/INT_LIT;SS 无裸负字面量)。
// evalAnnotationArg(interp_obj.ss:170)原缺 UNARY 分支 → loud `annotation arg kind 'UNARY'
// not yet supported`。本轮补 Neg + numeric-literal 分支(镜像 INT_LIT/DOUBLE_LIT 加负号)。
// 本测试钉住负 int/double annotation arg + 正 double 不回归。
import { assertEqual } from "@/lib/test"

@M(negi = -10, negd = -2.5, negbig = -3.14159, posd = 1.5)
class P { x: int }

function main() {
    test("I039 — 负 int annotation arg getInt", () => {
        const r = comptime {
            let acc = 0
            for (a in P.annotations) { acc = a.args.getInt("negi") }
            return acc
        }
        assertEqual(r, -10)
    })
    test("I039 — 负 double annotation arg getDouble", () => {
        const r = comptime {
            let acc = 0.0
            for (a in P.annotations) { acc = a.args.getDouble("negd") }
            return acc
        }
        assertEqual(r, -2.5)
    })
    test("I039 — 负 double 多位有效数字 bit-exact + comptime==runtime parity", () => {
        const r = comptime {
            let acc = 0.0
            for (a in P.annotations) { acc = a.args.getDouble("negbig") }
            return acc
        }
        assertEqual(r, -3.14159)
        let oracle = -3.14159
        assertEqual(r, oracle)
    })
    test("I039 — 正 double 不回归(负号分支不误伤正字面量)", () => {
        const r = comptime {
            let acc = 0.0
            for (a in P.annotations) { acc = a.args.getDouble("posd") }
            return acc
        }
        assertEqual(r, 1.5)
    })
}
