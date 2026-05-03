// D149 §F1 spike form 1: Tuple literal contextual typing — callee param Tuple 反推
// 验证 D148 bidirectional (commit 729b6f1) 落地后是否自然接管
// callee param `t: [int, string]` 反推内层 array literal `[1, "a"]` 为 Tuple<int, string>
// spike GREEN → F1 unnecessary 入 D148 §A.3
// spike RED → 起 D149 sub-D 主体设计 Tuple 独立反推 case

function takeTuple(t: [int, string]) {
    if (t[0] != 1) { exit(1) }
    if (t[1] != "a") { exit(2) }
}

function main() {
    // form 1: callee param Tuple<int, string> + 内层 array literal `[1, "a"]` 反推
    takeTuple([1, "a"])
    println("d149 F1 spike form 1 GREEN")
}
