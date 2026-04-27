// D143 Phase 3 — H3 嵌套 OBJ_LITERAL 反推 capture 链
// callee `takesProfile(p: Profile): string` → OBJ_LITERAL `{ user: { name: "Z", age: 20 }, addr: "Earth" }`
// 外层 nSetS2 反推回填 "Profile" → NEW_EXPR + classFieldTypes["Profile.user"]="User"
// 内层 OBJ_LITERAL 也需反推回填 "User" → NEW_EXPR(class/class_method.ss:genNamedConstructorArgs)
// 嵌套 capture 链 GREEN
import { assertEqual } from "@/lib/test"

class User {
    name: string
    age: int
}

class Profile {
    user: User
    addr: string
}

function takesProfile(p: Profile): string {
    return `${p.user.name}@${p.addr}`
}

function main() {
    const r = takesProfile({ user: { name: "Z", age: 20 }, addr: "Earth" })
    assertEqual(r, "Z@Earth")
}
