// check_thread.ss — D082 Phase 3 Thread closure capture validation.
// Entry (checkThreadClosureCaptures) + let detection (checkLetCapture) +
// recursive AST walk (checkThreadCapturesRec).
// State read via global scope: lookupVar / isVarConst / checkerError.

function checkThreadClosureCaptures(arrowId: int) {
    const params = Map()
    const paramList = nGetList(arrowId)
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                params.set(nGetS1(pId), "1")
            }
        }
    }
    const seen = Map()
    checkThreadCapturesRec(nGetI1(arrowId), params, seen)
}

function checkLetCapture(nodeId: int, params: Map, seen: Map) {
    const name = nGetS1(nodeId)
    if (name == "" || name == "this") { return }
    if (params.has(name) == 1 || seen.has(name) == 1) { return }
    if (lookupVar(name) != "" && isVarConst(name) == 0) {
        seen.set(name, "1")
        checkerError(`let variable '${name}' cannot be captured by thread closures; use const or ref()`, nGetLine(nodeId), nGetCol(nodeId))
    }
}

function checkThreadCapturesRec(nodeId: int, params: Map, seen: Map) {
    if (nodeId <= 0) { return }
    const kind = nGetKind(nodeId)
    if (kind == "") { return }
    if (kind == "ARROW_FUNC") { return }

    if (kind == "IDENT") {
        checkLetCapture(nodeId, params, seen)
        return
    }

    if (kind == "CALL") {
        checkLetCapture(nodeId, params, seen)
        const cArgList = nGetList(nodeId)
        if (cArgList != "") {
            const cParts = cArgList.split(",")
            for (cp in cParts) {
                checkThreadCapturesRec(parseInt(cp), params, seen)
            }
        }
        return
    }

    checkThreadCapturesRec(nGetI1(nodeId), params, seen)
    checkThreadCapturesRec(nGetI2(nodeId), params, seen)
    checkThreadCapturesRec(nGetI3(nodeId), params, seen)
    const lst = nGetList(nodeId)
    if (lst != "") {
        const lParts = lst.split(",")
        for (lp in lParts) {
            checkThreadCapturesRec(parseInt(lp), params, seen)
        }
    }
}
