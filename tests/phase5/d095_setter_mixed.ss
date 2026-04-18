// @Setter per-field mutators across mixed field types.
// Verifies type-position `${f.type}` interpolation in lib/lombok.ss Setter:
// int fields → set_x(v: int), string fields → set_name(v: string).

import { Setter, Getter } from "@/lib/lombok"
import { assertEqual } from "@/lib/test"

@Getter
@Setter
class Person {
    name: string
    age: int
}

function main() {
    test("D095 — @Setter mixed-type writes", () => {
        const p = new Person(name: "Alice", age: 30)
        p.set_name("Bob")
        p.set_age(42)
        assertEqual(p.get_name(), "Bob")
        assertEqual(p.get_age(), 42)
    })
}
