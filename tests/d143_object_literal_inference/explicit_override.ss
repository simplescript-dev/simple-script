// D143 Phase 3 — H6 显式注解 > 推断
// 用户写 `let u: User = { name: "Z", age: 25 }; takesUser(u)` 显式 var decl 注解
// → RHS OBJ_LITERAL 走 D084 rewrite 既有路径(check_stmts.ss:112-113 typeAnn != "" 触发 + gen_decls.ss:512-513)
// fn 实参传 u 是 IDENT(非 OBJ_LITERAL)→ 反推 skip,既有显式路径不破
import { assertEqual } from "@/lib/test"

class User {
    name: string
    age: int
}

function takesUser(u: User): string {
    return `${u.name}:${u.age}`
}

function main() {
    let u: User = { name: "Z", age: 25 }
    const r = takesUser(u)
    assertEqual(r, "Z:25")
}
