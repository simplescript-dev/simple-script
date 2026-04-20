// check_return.ss — D007 return-path analysis (pure AST-shape walk).
// No checker state access.

function blockAlwaysReturns(blockId: int): int {
    if (blockId <= 0) { return 0 }
    if (nGetKind(blockId) != "BLOCK") { return 0 }
    const stmtList = nGetList(blockId)
    if (stmtList == "") { return 0 }
    const parts = stmtList.split(",")
    for (p in parts) {
        const sid = parseInt(p)
        if (sid > 0 && stmtAlwaysReturns(sid) == 1) { return 1 }
    }
    return 0
}

function stmtAlwaysReturns(id: int): int {
    if (id <= 0) { return 0 }
    const kind = nGetKind(id)
    if (kind == "RETURN") { return 1 }
    if (kind == "THROW") { return 1 }
    // exit() is noreturn
    if (kind == "EXPR_STMT") {
        const inner = nGetI1(id)
        if (inner > 0 && nGetKind(inner) == "CALL" && nGetS1(inner) == "exit") { return 1 }
        return 0
    }
    if (kind == "IF") {
        const elseId = nGetI3(id)
        if (elseId <= 0) { return 0 }
        if (blockAlwaysReturns(nGetI2(id)) == 1 && blockAlwaysReturns(elseId) == 1) { return 1 }
        return 0
    }
    if (kind == "TRY") {
        if (blockAlwaysReturns(nGetI1(id)) == 0) { return 0 }
        // All catch clauses must also always return
        const cl = nGetList(id)
        if (cl == "") { return 0 }
        const cps = cl.split(",")
        for (cp2 in cps) {
            const cc = parseInt(cp2)
            if (cc > 0 && blockAlwaysReturns(nGetI1(cc)) == 0) { return 0 }
        }
        return 1
    }
    if (kind == "SWITCH") {
        const defId = nGetI2(id)
        if (defId <= 0) { return 0 }
        if (blockAlwaysReturns(defId) == 0) { return 0 }
        const caseList = nGetList(id)
        if (caseList == "") { return 0 }
        const cases = caseList.split(",")
        for (c in cases) {
            const caseId = parseInt(c)
            if (caseId > 0 && nGetKind(caseId) == "SWITCH_CASE") {
                if (blockAlwaysReturns(nGetI2(caseId)) == 0) { return 0 }
            }
        }
        return 1
    }
    if (kind == "BLOCK") { return blockAlwaysReturns(id) }
    return 0
}
