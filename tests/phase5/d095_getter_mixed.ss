// Test: D095 Stage E — @Getter 返回类型从 body return expr 推断
//
// 机制: emitClassComptimeMethods 在 FUNC_DECL.S2 (retType) 为空时扫描 body
// 首个 RETURN 语句,inferType(retExpr) 结果写回并注册 funcRetTypes。
// 使 @Getter 无需写死 (): int,自动适配任意字段类型。
//
// RED 证据: 此改动前 lib/lombok.ss Getter 若省略 (): int,string 字段 get_name()
// 挂 llc error '%3' defined with type 'ptr' but expected 'i32'。

import { Getter } from "@/lib/lombok"
import { assertEqual } from "@/lib/test"

@Getter
class Person {
    name: string
    age: int
}

function main() {
    test("D095 — @Getter mixed-type inference", () => {
        const p = new Person(name: "Alice", age: 30)
        assertEqual(p.get_name(), "Alice")
        assertEqual(p.get_age(), 30)
    })
}
