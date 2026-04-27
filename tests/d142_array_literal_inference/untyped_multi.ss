// D142 Phase 3 — H2 多元素同质反推
// callee `takesArr(arr: Array<int>): int` → ARRAY_LIT `[1, 2, 3]`
// 节点 nSetS2 反推回填 "int" → ss_newArray(i32 3) + 3x i64 box 路径 GREEN
import { assertEqual } from "@/lib/test"

function takesArr(arr: Array<int>): int {
    let sum = 0
    for (x in arr) { sum = sum + x }
    return sum
}

function main() {
    const r = takesArr([1, 2, 3])
    assertEqual(r, 6)
}
