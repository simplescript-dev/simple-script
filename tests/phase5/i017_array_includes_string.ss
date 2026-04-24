// I017 — Array<string>.includes 元素语义 RED → GREEN 最小测试
// 修前:string argType 误走 ss_indexOf (strstr substring 搜索, objVal 是 array 头非 C 字符串), 必 false
// 修后:objType+argType 双维分派,string 元素走 ss_arrayIndexOfStr (strcmp 元素比较)
// I016 同源对称修复:genArrayMethod 加 objType 参数,includes 分支与 genIndexOfMethod 同构

function main() {
    // Array<string>.includes — 核心 RED 场景
    let sa: Array<string> = []
    sa = sa.push("foo")
    sa = sa.push("bar")
    sa = sa.push("baz")
    if (sa.includes("foo") != 1) { exit(1) }
    if (sa.includes("bar") != 1) { exit(2) }
    if (sa.includes("baz") != 1) { exit(3) }
    if (sa.includes("missing") != 0) { exit(4) }

    // 动态构造 string (不同 ptr 同内容) — 防 ptr 相等短路
    let dyn: Array<string> = []
    dyn = dyn.push("D001")
    dyn = dyn.push("D002")
    const probe = "D00" + "1"
    if (dyn.includes(probe) != 1) { exit(5) }

    // Array<int>.includes — 原有 int 分支不回归
    let ia: Array<int> = []
    ia = ia.push(10)
    ia = ia.push(20)
    ia = ia.push(30)
    if (ia.includes(20) != 1) { exit(6) }
    if (ia.includes(99) != 0) { exit(7) }

    // string.includes (substring 搜索) — 非数组分支不回归
    const s = "hello world"
    if (s.includes("world") != 1) { exit(8) }
    if (s.includes("zzz") != 0) { exit(9) }
}
