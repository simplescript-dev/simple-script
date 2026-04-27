// D144 Phase 3 — H4 class 实例 ternary + D067 nullable 分配路径复用
// callee `takesNullableUser(u: User?): string` 多字段 class + 显式 ctor
// → ternary `(cond) ? null : new User("X", 18)` 反推 branchType="User?" 后 phi=ptr 统一
// 验证多字段 class 实例 ternary 反推不破
import { assertEqual } from "@/lib/test"

class User {
    name: string
    age: int
}

function takesNullableUser(u: User?): string {
    if (u == null) {
        return "(null)"
    }
    return `${u.name}:${u.age}`
}

function main() {
    let x = 5
    let r1 = takesNullableUser((x > 0) ? null : new User("X", 18))
    assertEqual(r1, "(null)")
    let y = -5
    let r2 = takesNullableUser((y > 0) ? null : new User("Y", 20))
    assertEqual(r2, "Y:20")
}
