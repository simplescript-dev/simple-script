// D144 Phase 3 — H1 反推 nullable + H2 两分支类型 widen
// callee `takesNullableUser(u: User?): string` 结构化签名 → ternary `(cond) ? null : new User("X")`
// 节点 nSetS2 反推回填 "User?" + null 分支按 D067 nullable 类型化 + new User 分支 ptr
// → IR phi llType=ptr 统一 GREEN
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
    let r1 = takesNullableUser((x > 0) ? null : new User("X"))
    assertEqual(r1, "(null)")
    let y = -5
    let r2 = takesNullableUser((y > 0) ? null : new User("Y"))
    assertEqual(r2, "Y")
}
