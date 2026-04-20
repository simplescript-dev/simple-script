// check_narrow.ss — D067 Phase 2 null-narrow helpers.
// Reads/writes global narrowedTypes Map; other checker state via global scope.

function rejectPrimitiveNullable(t: string, nodeId: int) {
    if (isPrimitiveNullable(t) == 1) {
        checkerError(`primitive type '${stripNullable(t)}' cannot be nullable`, nGetLine(nodeId), nGetCol(nodeId))
    }
}

// D067 Phase 2: Extract variable name from null check condition (x == null / x != null)
// Returns "varName" if condition is a null check on a simple IDENT, else ""
function extractNullCheckVar(condId: int): string {
    if (condId <= 0) { return "" }
    if (nGetKind(condId) != "BINARY") { return "" }
    const op = nGetS1(condId)
    if (op != "Eq" && op != "Ne") { return "" }
    const left = nGetI1(condId)
    const right = nGetI2(condId)
    if (nGetKind(left) == "IDENT" && nGetKind(right) == "NULL_LIT") {
        return nGetS1(left)
    }
    if (nGetKind(right) == "IDENT" && nGetKind(left) == "NULL_LIT") {
        return nGetS1(right)
    }
    return ""
}

// D067 Phase 2: Restore narrowing to previous state
function restoreNarrowing(ncVar: string, ncOldNarrow: string) {
    if (ncOldNarrow != "") {
        narrowedTypes.set(ncVar, ncOldNarrow)
    } else {
        narrowedTypes.delete(ncVar)
    }
}
