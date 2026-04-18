// @Getter inference: retType derived from body's first RETURN expression.
// Regression guard: string fields previously failed llc with
// type mismatch 'ptr' vs 'i32' when (): int was missing.

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
