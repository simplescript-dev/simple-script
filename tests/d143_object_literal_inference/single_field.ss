// D143 Phase 3 — H1 单字段反推
// callee `takesUser(u: User): string` 结构化签名 → OBJ_LITERAL `{ name: "X" }`
// 节点 nSetS2 反推回填 "User" + nKind→NEW_EXPR + nSetS1="User"
// → IR `call ptr @User_new(ptr @.str.N)` GREEN
import { assertEqual } from "@/lib/test"

class User {
    name: string
}

function takesUser(u: User): string {
    return u.name
}

function main() {
    const r = takesUser({ name: "X" })
    assertEqual(r, "X")
}
