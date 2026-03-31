// Test: Set<T> type (Map wrapper, D021)

function main() {
    // Basic add/has/size
    let s = new Set()
    s.add("hello")
    s.add("world")
    s.add("hello")
    if (s.size() != 2) { exit(1) }
    if (s.has("hello") != 1) { exit(1) }
    if (s.has("missing") != 0) { exit(1) }

    // Remove
    s.remove("hello")
    if (s.has("hello") != 0) { exit(1) }
    if (s.size() != 1) { exit(1) }

    // Values returns all elements (as newline-separated string via Map.keys)
    s.add("a")
    s.add("b")
    const v = s.values()
    if (v == "") { exit(1) }

    // Type annotation
    let typed: Set<string> = new Set()
    typed.add("x")
    if (typed.size() != 1) { exit(1) }

    println("set_type: all passed")
}
