// D096 Phase 1 RED — class body get/set accessor 基础形态。
// 预期崩点随编译阶段而变:
//   P0 (本 commit 前,无 parser 改动):   parse error at 'get'
//   P1 (parser 改动已进 bin/ss,codegen 未改): 会跑到 check 或 codegen 崩
//   P2 完成后:                           GREEN

class Counter {
    _v: int = 0
    get value(): int { return this._v }
    set value(v: int) { this._v = v }
}

function main() {
    const c = new Counter(_v: 5)
    println(c.value)
    c.value = 42
    println(c.value)
}
