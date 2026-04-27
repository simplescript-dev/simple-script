// D142 Phase 3 — H3 嵌套 Array<Array<int>> 反推 capture 链
// callee `takesNested(arr: Array<Array<int>>): int` → ARRAY_LIT `[[1,2],[3,4]]`
// 外层 nSetS2 反推回填 "Array<int>" → ss_newArrayPtr(i32 2)
// 内层 ARRAY_LIT 也需反推回填 "int" → ss_newArray(i32 2) + i64 box 递归 GREEN
import { assertEqual } from "@/lib/test"

function takesNested(arr: Array<Array<int>>): int {
    let sum = 0
    for (inner in arr) {
        for (x in inner) { sum = sum + x }
    }
    return sum
}

function main() {
    const r = takesNested([[1, 2], [3, 4]])
    assertEqual(r, 10)
}
