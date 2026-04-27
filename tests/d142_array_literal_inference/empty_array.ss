// D142 Phase 3 — H4 空数组反推(无元素来源,反推机制兜底)
// callee `takesArr(arr: Array<int>): int` → ARRAY_LIT `[]`
// 节点 nSetS2 反推回填 "int"(callee 直接取 elemType,不依赖元素 inferType)
// → ss_newArray(i32 0) 路径 GREEN(反推前 silent fallback scalar 走错)
import { assertEqual } from "@/lib/test"

function takesArr(arr: Array<int>): int {
    let sum = 0
    for (x in arr) { sum = sum + x }
    return sum
}

function main() {
    const r = takesArr([])
    assertEqual(r, 0)
}
