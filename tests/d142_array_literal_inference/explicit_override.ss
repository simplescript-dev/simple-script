// D142 Phase 3 — H6 显式注解 > 推断
// 用户写 `let arr: Array<int> = [1,2,3]; takesArr(arr)` 显式 var decl 注解
// → RHS [1,2,3] 走 gen_decls.ss:566-571 既有 setVarType 路径(arr varType="Array<int>")
// fn 实参传 arr 是 IDENT(非 ARRAY_LIT)→ 反推 skip,既有显式路径不破
import { assertEqual } from "@/lib/test"

function takesArr(arr: Array<int>): int {
    let sum = 0
    for (x in arr) { sum = sum + x }
    return sum
}

function main() {
    let arr: Array<int> = [1, 2, 3]
    const r = takesArr(arr)
    assertEqual(r, 6)
}
