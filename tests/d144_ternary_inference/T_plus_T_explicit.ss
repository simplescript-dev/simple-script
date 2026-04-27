// D144 Phase 3 — H6 显式两分支同类型(无反推依赖)
// callee `takesInt(n: int): int` + ternary `(cond) ? 1 : 2` 两分支显式 int
// → checker 两分支基础类型一致 PASS / nSetS2 回填 "int" / 走原 then 分支 inferType
// 验证 H6 显式优先级:既有显式同类型 ternary 路径不破
import { assertEqual } from "@/lib/test"

function takesInt(n: int): int {
    return n * 10
}

function main() {
    let x = 5
    let r1 = takesInt((x > 0) ? 1 : 2)
    assertEqual(r1, 10)
    let y = -5
    let r2 = takesInt((y > 0) ? 1 : 2)
    assertEqual(r2, 20)
}
