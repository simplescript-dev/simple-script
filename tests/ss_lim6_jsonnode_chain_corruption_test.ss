// SS-LIM-6 spike: JsonNode chain + class allocation cross-iteration corruption.
// Repro: const arr = data.get("items"); while { class_alloc; arr.get(k).asString() }
// 第 3+ iter arr.get(k).asString() 返 "",甚至 mimalloc free-list corruption。

import { JsonNode, JSON_parse } from "@/lib/json"

abstract class N {
    abstract function k(): int
}

class T extends N {
    content: string
    override function k(): int { return 1 }
}

class E extends N {
    tag: string
    children: Array<N>
    override function k(): int { return 0 }
}

function cloneE(e: E): E {
    let kids: Array<N> = []
    let i = 0
    while (i < e.children.length()) {
        const c = e.children[i]
        if (c instanceof T) { kids = kids.push(new T((c as T).content)) }
        i = i + 1
    }
    return new E(e.tag, kids)
}

function expand(elem: E, data: JsonNode, out: Array<N>) {
    const arr = data.get("items")
    const sz = arr.size()
    let k = 0
    while (k < sz) {
        out.push(cloneE(elem))
        const v = arr.get(k).asString()
        println("k=" + `${k}` + " v='" + v + "'")
        if (v == "") { exit(1) }
        k = k + 1
    }
}

function main() {
    let kids: Array<N> = []
    kids = kids.push(new T("X"))
    const original = new E("p", kids)
    const data = JSON_parse(`{"items":["a","b","c","d"]}`)
    let out: Array<N> = []
    expand(original, data, out)
    println("SS-LIM-6 spike: chain + class-alloc GREEN")
}
