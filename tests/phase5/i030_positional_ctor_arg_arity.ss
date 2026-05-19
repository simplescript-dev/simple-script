// I030 regression — positional-partial constructor calls must pad arguments
// to the constructor's full field arity. Pre-fix, genNewExpr's positional
// branch (and genGenericNewExpr's loop) emitted only the provided args, so
// `new Holder("x")` produced `call @Holder_new` short of its declared params;
// un-provided trailing optional fields then read uninitialized ABI registers
// (garbage). An optional `fn` field's garbage value defeats a `!= 0` guard and
// invoking it jumps to a garbage address → SIGSEGV (the test_121 crash).
// Post-fix: un-provided optional fields are type-correct zero / null.

class Holder {
    name: string
    tag?: int
    cb?: fn
}

class Box<T> {
    value: T
    note?: int
    hook?: fn
}

function main() {
    // non-generic positional-partial (genNewExpr positional branch)
    const h = new Holder("only-name")
    if (h.name != "only-name") { exit(1) }
    if (h.tag != 0) { exit(1) }          // un-provided optional int → 0, not garbage
    if (h.cb != 0) { exit(1) }           // un-provided optional fn → null, not garbage

    // a second object reuses the first's freed block (mimalloc REUSE) — also clean
    const h2 = new Holder("second")
    if (h2.tag != 0) { exit(1) }
    if (h2.cb != 0) { exit(1) }

    // generic positional-partial (genGenericNewExpr)
    const b = new Box<int>(7)
    if (b.value != 7) { exit(1) }
    if (b.note != 0) { exit(1) }         // un-provided optional int → 0
    if (b.hook != 0) { exit(1) }         // un-provided optional fn → null

    println("i030: positional-partial ctor arity OK")
}
