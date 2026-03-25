function sideEffect(label: string): int {
    print(label + " ")
    return 1
}

function main() {
    // && short-circuit: right side should NOT execute when left is false
    println("=== && short-circuit ===")
    print("true && true: ")
    if (sideEffect("L") == 1 && sideEffect("R") == 1) { println("-> yes") }

    print("false && true: ")
    if (0 == 1 && sideEffect("R") == 1) {
        println("-> yes")
    } else {
        println("-> no (R should NOT appear)")
    }

    // || short-circuit: right side should NOT execute when left is true
    println("")
    println("=== || short-circuit ===")
    print("true || true: ")
    if (sideEffect("L") == 1 || sideEffect("R") == 1) { println("-> yes (R should NOT appear)") }

    print("false || true: ")
    if (0 == 1 || sideEffect("R") == 1) { println("-> yes") }

    // Nested
    println("")
    println("=== nested ===")
    const a = 5
    const b = 10
    if (a > 0 && b > 0 && a < b) {
        println("all true")
    }
    if (a > 100 || b > 100 || a + b == 15) {
        println("last true")
    }
}
