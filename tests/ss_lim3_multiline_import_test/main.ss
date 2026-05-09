// SS-LIM-3 spike: multi-line import (D167).
// Repro: `import {\n    Foo,\n    Bar,\n    Baz\n} from "..."` was parse error.
// Verifies resolveImports multi-line block accumulation + parser skipNL inside `{}`.

import {
    Foo,
    Bar,
    Baz,
} from "./import/mod"

function main() {
    let f: Foo = new Foo()
    let b: Bar = new Bar()
    let z: Baz = new Baz()
    if (f.greet() != "foo") { exit(1) }
    if (b.greet() != "bar") { exit(2) }
    if (z.greet() != "baz") { exit(3) }
    println("ss-lim-3 multi-line import: ok")
}
