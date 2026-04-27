// D144 Phase 3 — H3 嵌套 ternary 反推 capture 链
// callee `takesNullableUser(u: User?): string` → 外层 `(c1) ? null : ((c2) ? null : new User("Z"))`
// 外层 nSetS2 反推回填 "User?" + propagateTernaryBranchType 递归回填 内层 nSetS2 = "User?"
// 内层 ternary 也走 phi llType=ptr / 两分支 widen 路径 GREEN
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
    let x = 1
    let y = 1
    let r1 = takesNullableUser((x > 0) ? ((y > 0) ? null : new User("Z")) : new User("A"))
    assertEqual(r1, "(null)")
    let z = 1
    let w = -1
    let r2 = takesNullableUser((z > 0) ? ((w > 0) ? null : new User("Z")) : new User("A"))
    assertEqual(r2, "Z")
    let p = -1
    let q = -1
    let r3 = takesNullableUser((p > 0) ? ((q > 0) ? null : new User("Z")) : new User("A"))
    assertEqual(r3, "A")
}
