// SS-LIM-4 spike — alloca-not-dominate-all-uses verifier crash
//
// Two complementary triggers in one file:
//
// Trigger A (structural — preserved from earlier spike): nested while + if
//   instanceof + as cast + multi const + tail recursion. Produces alloca in
//   if.then / cast.ok / while.body BBs. LLVM verifier accepts both pre-fix
//   and post-fix (uses stay within sub-CFG); evidences the alloca-placement
//   count delta (RED 48 → GREEN 15) at IR-shape level.
//
// Trigger B (behavioral — D139 §F10 path, this Phase): outer try/catch
//   (e: T) returns out → main-flow reachable only via try-no-throw path →
//   arrow on main-flow captures outer `e` (SS closure free-var detection
//   bug) → without SS-LIM-4 fix, outer e alloca lives in catch.body BB and
//   the closure build at try.end emits `load %e` not dominated by
//   catch.body → llc rejects "Instruction does not dominate all uses!"
//   With SS-LIM-4 fix, outer e alloca is hoisted to entry → all uses
//   dominated → llc accepts.
//
// Trigger B is wrapped in `f10TriggerScenario` which is COMPILED but never
// CALLED — IR-level llc verifier still examines its body. main() runs only
// Trigger A path so the post-fix binary executes cleanly (exit 0). This
// gives §N §3 reverse validation hard evidence (stash fix → llc rejects)
// without dragging runtime semantics of an unused-trigger function.
//
// Stash-and-rebuild reverse validation:
//   git stash push <SS-LIM-4 files>; ./build.sh bootstrap
//   bin/ss build tests/phase5/ss_lim4_alloca_hoist_test.ss -o /tmp/lim4
//   → llc reports: "Instruction does not dominate all uses!"
//   git stash pop; ./build.sh bootstrap
//   bin/ss build tests/phase5/ss_lim4_alloca_hoist_test.ss -o /tmp/lim4
//   → exit 0; /tmp/lim4 → exit 0

class Node {
    tag: string
}

class Add extends Node {
    lhs: int
    rhs: int
}

class Mul extends Node {
    lhs: int
    rhs: int
}

class Lit extends Node {
    val: int
}

class WrapErr {
    message: string
}

function probe(): int {
    return 1
}

function runWith(label: string, fn: fn(): int): int {
    return fn()
}

function evalNode(n: Node, depth: int): int {
    if (depth > 50) { return 0 }
    let acc = 0
    let i = 0
    while (i < 3) {
        let j = 0
        while (j < 3) {
            if (n instanceof Add) {
                const ceA = n as Add
                const lvA = ceA.lhs
                const rvA = ceA.rhs
                const sumA = lvA + rvA
                acc = acc + sumA
            } else if (n instanceof Mul) {
                const ceM = n as Mul
                const lvM = ceM.lhs
                const rvM = ceM.rhs
                const prodM = lvM * rvM
                acc = acc + prodM
            } else if (n instanceof Lit) {
                const ceL = n as Lit
                const vL = ceL.val
                acc = acc + vL
            }
            j = j + 1
        }
        i = i + 1
    }
    if (depth < 5) {
        return acc + evalNode(n, depth + 1)
    }
    return acc
}

// Trigger B — compiled (llc-verified) but never called at runtime.
function f10TriggerScenario(): int {
    try {
        if (probe() == 0) {
            throw(new WrapErr(message: "probe-failed"))
        }
    } catch (e: WrapErr) {
        // null-coalesce in catch path (one of the listed forms)
        println(e.message ?? "no-msg")
        return 0
    }

    // main-flow past outer catch — closure build references outer e alloca
    // because SS free-var detection captures `e` from the inner catch shadow.
    return runWith("inner", () => {
        try {
            throw(new WrapErr(message: "inner"))
        } catch (e: WrapErr) {
            return e.message.length()
        }
        return 0
    })
}

function main() {
    const a = new Add(tag: "+", lhs: 2, rhs: 3)
    const m = new Mul(tag: "*", lhs: 4, rhs: 5)
    const l = new Lit(tag: "v", val: 7)
    let total = 0
    total = total + evalNode(a, 0)
    total = total + evalNode(m, 0)
    total = total + evalNode(l, 0)
    if (total <= 0) { exit(1) }
}
