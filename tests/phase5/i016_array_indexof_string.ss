// I016 — Array<string>.indexOf 元素语义 RED → GREEN 最小测试
// 修前:string 分支误走 ss_indexOf (strstr substring 搜索), Array<string> 元素存在也返 -1
// 修后:objType+argType 双维分派, string 元素走 ss_arrayIndexOfStr (strcmp 元素比较)

function main() {
    // Array<string>.indexOf — 核心 RED 场景
    let sa: Array<string> = []
    sa = sa.push("foo")
    sa = sa.push("bar")
    sa = sa.push("baz")
    if (sa.indexOf("foo") != 0) { exit(1) }
    if (sa.indexOf("bar") != 1) { exit(2) }
    if (sa.indexOf("baz") != 2) { exit(3) }
    if (sa.indexOf("missing") != -1) { exit(4) }

    // 动态构造 string (不同 ptr 同内容) — 覆盖 d_doc_index_linter 场景
    let dyn: Array<string> = []
    dyn = dyn.push("D001")
    dyn = dyn.push("D002")
    const probe = "D00" + "1"
    if (dyn.indexOf(probe) != 0) { exit(5) }

    // Array<int>.indexOf — 原有 int 分支不回归
    let ia: Array<int> = []
    ia = ia.push(10)
    ia = ia.push(20)
    ia = ia.push(30)
    if (ia.indexOf(20) != 1) { exit(6) }
    if (ia.indexOf(99) != -1) { exit(7) }

    // string.indexOf (substring 搜索) — 非数组分支不回归
    const s = "hello world"
    if (s.indexOf("world") != 6) { exit(8) }
    if (s.indexOf("zzz") != -1) { exit(9) }
}
