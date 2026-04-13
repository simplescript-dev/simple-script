// Test: compile-time string comparison folding (D089 Phase 5)

import { assertEqual } from "@/lib/test"

function main() {
    // String equality — comptime
    const mode = "debug"
    const isDebug = mode == "debug"
    assertEqual(isDebug, 1)

    const isRelease = mode == "release"
    assertEqual(isRelease, 0)

    // String inequality — comptime
    const notDebug = mode != "debug"
    assertEqual(notDebug, 0)

    // Direct literal comparison
    const same = "hello" == "hello"
    assertEqual(same, 1)

    const diff = "abc" != "xyz"
    assertEqual(diff, 1)

    // String ordering — comptime
    const lt = "abc" < "def"
    assertEqual(lt, 1)

    const gt = "xyz" > "abc"
    assertEqual(gt, 1)

    println("all comptime string compare tests passed")
}
