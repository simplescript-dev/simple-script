// D143 Phase 3 — H5 class 字段类型混合反推(string + int + double 异质)
// callee `takesItem(i: Item): string` → OBJ_LITERAL `{ name: "Apple", count: 3, price: 1.5 }`
// 节点 nSetS2 反推回填 "Item" → NEW_EXPR + 字段值各自 inferType("string"/"int"/"double")
// 与 ctor PARAM 类型一致 → IR ctor args 各 box 路径正确 GREEN
// 注:Array<T> / Map<K,V> 字段反推 OOD scope(D143 §Followup F4 + D142 §F7 同模式锚 — NEW_EXPR ctor 实参反推扩 sub-D)
import { assertEqual } from "@/lib/test"

class Item {
    name: string
    count: int
    price: double
}

function takesItem(i: Item): string {
    return `${i.name}:${i.count}:${i.price}`
}

function main() {
    const r = takesItem({ name: "Apple", count: 3, price: 1.5 })
    assertEqual(r, "Apple:3:1.5")
}
