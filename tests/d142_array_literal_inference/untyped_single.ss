// D142 Phase 3 — H1 单元素反推
// callee `takesArr(arr: Array<int>): int` 结构化签名 → ARRAY_LIT `[1]`
// 节点 nSetS2 反推回填 "int" → ss_newArray(i32 1) + i64 box 路径 GREEN
import { assertEqual } from "@/lib/test"

function takesArr(arr: Array<int>): int {
    let sum = 0
    for (x in arr) { sum = sum + x }
    return sum
}

function main() {
    const r = takesArr([1])
    assertEqual(r, 1)
}
