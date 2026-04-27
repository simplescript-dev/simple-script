// D144 Phase 3 — H3 嵌套 + null 多层 ternary
// callee `takesNullableUser(u: User?): string` + 内外两层 null `(cond1) ? null : ((cond2) ? null : new User("X"))`
// 验证嵌套 ternary 多 null 分支 + 单值分支反推路径全 GREEN
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
    // 外层 null → (null)
    let x = 1
    let y = 1
    let r1 = takesNullableUser((x > 0) ? null : ((y > 0) ? null : new User("X")))
    assertEqual(r1, "(null)")

    // 外层不 null,内层 null → (null)
    let z = -1
    let w = 1
    let r2 = takesNullableUser((z > 0) ? null : ((w > 0) ? null : new User("Y")))
    assertEqual(r2, "(null)")

    // 外层不 null,内层不 null → "Z"
    let p = -1
    let q = -1
    let r3 = takesNullableUser((p > 0) ? null : ((q > 0) ? null : new User("Z")))
    assertEqual(r3, "Z")
}
