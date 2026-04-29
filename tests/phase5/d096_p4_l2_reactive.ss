// D096 Phase 4 L2 RED — reactive<T>(v) stdlib 生成 Reactive_T wrapper
// 依赖:L1 comptime class runtime 实例化 ✓,D088 Phase 4 TypeValue ✓,D094 fields()
// 预期 fail:reactive 未导出 OR comptime 里 T.fields() 展开不出 wrapper 字段
import { reactive, effect } from "@/lib/reactive"

class Counter {
    count: int = 0
}

let lastSeen = 0

function main() {
    const r = reactive(new Counter(count: 5))
    effect(() => {
        lastSeen = r.count
        println(`effect saw ${lastSeen}`)
    })
    r.count = 10
    r.count = 42
    println(`final ${lastSeen}`)
}
