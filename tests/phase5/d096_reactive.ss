// D096 Phase 3 — reactive stdlib PoC。
// 验证 ref + effect + accessor-driven trigger 端到端工作。
import { rxRef, effect } from "@/lib/reactive"

let lastSeen = 0

function main() {
    const count = rxRef(0)
    effect(() => {
        lastSeen = count.value
        println(`effect saw ${lastSeen}`)
    })
    count.value = 1
    count.value = 2
    count.value = 3
    println(`final ${lastSeen}`)
}
