// Test: builtin method return type inference (D059)
// Verifies that checker can infer return types for string/Array/Map methods,
// enabling type checking of chain calls and assignments.

function main() {
    // String method return types
    const s = "hello world"
    const ch: string = s.charAt(0)
    if (ch != "h") { exit(1) }

    const idx: int = s.indexOf("world")
    if (idx != 6) { exit(1) }

    const upper: string = s.toUpperCase()
    if (upper != "HELLO WORLD") { exit(1) }

    const parts: Array<string> = s.split(" ")
    if (parts.length() != 2) { exit(1) }

    const trimmed: string = "  hi  ".trim()
    if (trimmed != "hi") { exit(1) }

    const rep: string = "ab".repeat(3)
    if (rep != "ababab") { exit(1) }

    const sub: string = s.substring(0, 5)
    if (sub != "hello") { exit(1) }

    // String method chain: split returns Array, then join returns string
    const joined: string = "a,b,c".split(",").join("-")
    if (joined != "a-b-c") { exit(1) }

    // Array method return types
    let arr: Array<int> = [1, 2, 3]
    const len: int = arr.length()
    if (len != 3) { exit(1) }

    arr = arr.push(4)
    if (arr.length() != 4) { exit(1) }

    const sliced = arr.slice(0, 2)
    if (sliced.length() != 2) { exit(1) }

    const hasIt: int = arr.includes(3)
    if (hasIt != 1) { exit(1) }

    const pos: int = arr.indexOf(2)
    if (pos != 1) { exit(1) }

    // Map method return types
    let m = new Map()
    m.set("key", "value")
    const hasKey: int = m.has("key")
    if (hasKey != 1) { exit(1) }

    const sz: int = m.size()
    if (sz != 1) { exit(1) }

    const keys = m.keys()
    if (keys.length() != 1) { exit(1) }

    // Math method return types
    const sq: double = Math.sqrt(4.0)
    if (sq != 2.0) { exit(1) }

    const fl: double = Math.floor(3.7)
    if (fl != 3.0) { exit(1) }

    const ri: int = Math.randomInt(1)
    if (ri != 0) { exit(1) }

    // String contains/startsWith/endsWith return int
    const c1: int = "hello".contains("ell")
    if (c1 != 1) { exit(1) }

    const c2: int = "hello".startsWith("hel")
    if (c2 != 1) { exit(1) }

    const c3: int = "hello".endsWith("llo")
    if (c3 != 1) { exit(1) }

    println("builtin type check OK")
}
