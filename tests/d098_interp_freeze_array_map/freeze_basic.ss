// D098 §决策 2 §Phase C — Array/Map 入 InternPool dedup(sibling 61 Execute)
// 4 关键性质 SS test:同值同 id / 空 Array dedup / 嵌套 dedup / 反向不等
// 通过条件:编译 OK + 运行 exit 0
// 验证机制:array Eq/Ne ct path 走 interpValEquals(lid==rid?1:0),
// dedup 生效 → 同值 array 拿同 frozen tvId → arr1==arr2 返 true;dedup 失败 → 不同 tvId → false
//
// 测试 scope 选 global const = comptime { return ... } 而非 function 内 const —— 因 inner comptime
// block 切 currentFunc=__comptime__,看不到 function 内 ctVar(主 fn 内 const),但全局 :name
// 跨层可见(evalIdent.ss L26-30 ctGlobalKey fallback)。

const arr1 = comptime { return [1, 2, 3] }
const arr2 = comptime { return [1, 2, 3] }
const empty1 = comptime { return [] }
const empty2 = comptime { return [] }
const nested1 = comptime { return [[1], [2]] }
const nested2 = comptime { return [[1], [2]] }
const diff1 = comptime { return [1, 2, 3] }
const diff2 = comptime { return [1, 2, 4] }

function main() {
    // 性质 1:同值同 id
    const eq1 = comptime { return arr1 == arr2 }
    if (eq1 != true) { exit(1) }

    // 性质 2:空 Array dedup
    const eq2 = comptime { return empty1 == empty2 }
    if (eq2 != true) { exit(2) }

    // 性质 3:嵌套 dedup 递归 child 级联
    const eq3 = comptime { return nested1 == nested2 }
    if (eq3 != true) { exit(3) }

    // 性质 4:反向 — 不同值不 dedup
    const ne1 = comptime { return diff1 != diff2 }
    if (ne1 != true) { exit(4) }

    println("D098 §Phase C Array/Map InternPool dedup GREEN (4 性质 PASS)")
}
