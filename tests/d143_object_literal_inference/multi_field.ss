// D143 Phase 3 — H2 多字段同质反推
// callee `takesUser(u: User): string` → OBJ_LITERAL `{ name: "Y", age: 18 }`
// 节点 nSetS2 反推回填 "User" + nKind→NEW_EXPR
// → IR `call ptr @User_new(ptr @.str.N, i32 18)` GREEN
import { assertEqual } from "@/lib/test"

class User {
    name: string
    age: int
}

function takesUser(u: User): string {
    return `${u.name}:${u.age}`
}

function main() {
    const r = takesUser({ name: "Y", age: 18 })
    assertEqual(r, "Y:18")
}
