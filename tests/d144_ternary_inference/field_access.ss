// D144 Phase 3 — X4-1 字段访问 GREEN(Phase 2 resolveObjClass GROUPING/TERNARY case 修复入口)
// `((cond) ? u1 : u2).name` 字段访问通过 resolveObjClass 拿到 "User" → classFieldTypes["User.name"]="string"
// IR phi llType=ptr / GEP offset 0 取 .name 路径全通 — Phase 1 LLC RED 形态修复实证
import { assertEqual } from "@/lib/test"

class User {
    name: string
    age: int
}

function main() {
    let x = 5
    let u1 = new User("Alice", 18)
    let u2 = new User("Bob", 20)
    let n1 = ((x > 0) ? u1 : u2).name
    assertEqual(n1, "Alice")
    let a1 = ((x > 0) ? u1 : u2).age
    assertEqual(a1, 18)

    let y = -5
    let n2 = ((y > 0) ? u1 : u2).name
    assertEqual(n2, "Bob")
    let a2 = ((y > 0) ? u1 : u2).age
    assertEqual(a2, 20)
}
