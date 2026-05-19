// D168 §C.11 — emitReleaseVarList 收口回归测试
// codegen-local RC 全栈 magic 分派(ss_*_any)+ isRcManaged 门。
// 覆盖 spike 三轮各自的崩溃形态:
//   轮 1 — return localVar.method()(method-call 返回式 inferType 不精确)
//   轮 2 — Ref 局部(第三类 calloc'd 对象,ss_release_any 不可施用)
//   轮 3 — string/Array/Map 局部真实释放 + Map update/delete

import { assert } from "./import/asserts"

// method-call 返回式:返回一份拷贝
function copyArr(x: Array<int>): Array<int> {
    return x.slice(0, x.length())
}

// spike 轮 1 崩溃形态:let local = call(); return local.method()
function buildAndReverse(a: Array<int>): Array<int> {
    let sorted = copyArr(a)
    return sorted.reverse()
}

// borrowed binding-retain + return
function tailStr(p: string): string {
    let q = p
    return q
}

function main() {
    // string 局部 + 重赋值(genAssign ASSIGN)
    let s = "ab" + "cd"
    assert(s == "abcd", "string concat")
    s = "xy" + "zw"
    assert(s == "xyzw", "string reassign releases old")

    // return localVar.method() — spike 轮 1 over-release UAF 形态
    let base = [3, 1, 2]
    let rev = buildAndReverse(base)
    assert(rev.length() == 3, "return localVar.reverse() length")

    // borrowed binding + return
    let t = tailStr("hello")
    assert(t == "hello", "borrowed binding return")

    // Map get / set-update / delete — §C.10-map → §C.11 真实 release
    let m: Map<string, string> = Map()
    m.set("k", "v1")
    let got = m.get("k")
    assert(got == "v1", "map.get")
    m.set("k", "v2")
    assert(m.get("k") == "v2", "map.set update releases old value")
    m.delete("k")
    assert(m.has("k") == 0, "map.delete releases value")

    // Ref 局部 — 第三类对象,emitReleaseVarList 经 isRcManaged 跳过(spike 轮 2 形态)
    let cell = ref(7)
    assert(cell.value == 7, "Ref local skipped by isRcManaged")
    cell.value = 9
    assert(cell.value == 9, "Ref still valid after scope RC")

    println("c11_release_varlist: all passed")
}
