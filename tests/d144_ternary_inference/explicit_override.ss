// D144 Phase 3 — H6 显式注解 > 推断
// 用户写 `let n: User? = (cond) ? null : new User("X"); takesNullableUser(n)` 显式 var decl 注解
// → RHS ternary 走 D084 rewrite + D067 既有路径(check_stmts.ss typeAnn != "" 触发)
// fn 实参传 n 是 IDENT(非 TERNARY)→ 反推 skip,既有显式路径不破
import { assertEqual } from "@/lib/test"

class User {
    name: string
}

function takesNullableUser(u: User?): string {
    if (u == null) {
        return "(null)"
    }
    return u.name
}

function main() {
    let x = 5
    let n: User? = (x > 0) ? null : new User("X")
    let r1 = takesNullableUser(n)
    assertEqual(r1, "(null)")

    let y = -5
    let m: User? = (y > 0) ? null : new User("Y")
    let r2 = takesNullableUser(m)
    assertEqual(r2, "Y")
}
