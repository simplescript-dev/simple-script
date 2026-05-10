// SS-LIM-4 RED — alloca-not-dominate-all-uses verifier crash
//
// Triggers:
//   - nested while loops
//   - if instanceof T1 / T2 / T3 dispatch (T1/T2/T3 abstract Node subclasses)
//   - const x = node as T1 / T2 / T3 inside each branch
//   - tail recursive call to self
// Expected (RED): bin/ss build emits LLVM IR where alloca for `const ce = ...`
// lives in a non-entry BB (if.then / cast.ok / while.body), and `llc` rejects
// with "Instruction does not dominate all uses!" verifier error.
// Expected (GREEN, post-fix): all alloca hoisted to entry BB; build passes.

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
