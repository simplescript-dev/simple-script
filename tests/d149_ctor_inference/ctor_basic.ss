// D149 §F2 spike form 1: NEW_EXPR ctor 实参子节点反推 — bidirectional 自然解度验证
// 验证 D148 bidirectional (commit 729b6f1) 落地后 NEW_EXPR ctor 实参子节点是否自然接管反推
// new ArrayHolder([1, 2, 3]) — ctor PARAM `arr: Array<int>` 反推内层 array literal `[1, 2, 3]` elemType=int
// spike GREEN → F2 unnecessary 入 D148 §A.3 + §Followup F2 标 + §A.2 H13 进一步 PASS 实证
// spike RED → 起 D149 sub-D 主体设计 NEW_EXPR ctor 独立反推 case + Phase 0-N 计划

class ArrayHolder {
    arr: Array<int>
}

function main() {
    // form 1: ctor PARAM (arr: Array<int>) + 实参子节点 array literal `[1, 2, 3]` 反推 elemType=int
    let h = new ArrayHolder([1, 2, 3])
    if (h.arr[0] != 1) { exit(1) }
    if (h.arr[1] != 2) { exit(2) }
    if (h.arr[2] != 3) { exit(3) }
    println("d149 F2 spike form 1 GREEN")
}
