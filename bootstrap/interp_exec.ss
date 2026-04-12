// interp_exec.ss — Statement execution for the AST interpreter
//
// Handles interpExec: block, var/func/class decl, control flow
// (if/while/for/for-in/do-while), assignment, break/continue/return.
// Forward-references interpEval from interp_eval.ss
// and value/scope/class helpers from interp.ss.

// ── Statement Execution ───────────────────────────────────────

function interpExec(nodeId: int) {
    if (nodeId <= 0) { return }
    const kind = nGetKind(nodeId)

    if (kind == "BLOCK") {
        interpPushScope()
        const list = nGetList(nodeId)
        if (list != "") {
            const stmts = list.split(",")
            let i = 0
            while (i < stmts.length()) {
                interpExec(parseInt(stmts[i]))
                if (interpShouldStop() == 1) { break }
                i = i + 1
            }
        }
        interpPopScope()
        return
    }

    if (kind == "VAR_DECL") {
        const name = nGetS1(nodeId)
        const initId = nGetI1(nodeId)
        let val = interpNewNull()
        if (initId > 0) { val = interpEval(initId) }
        interpSetVar(name, val)
        return
    }

    if (kind == "FUNC_DECL") {
        const name = nGetS1(nodeId)
        interpSetVar(name, interpNewVal("fn", `${nodeId}`))
        return
    }

    if (kind == "CLASS_DECL") {
        const className = nGetS1(nodeId)
        interpClasses.set(className, `${nodeId}`)
        const parentName = nGetS2(nodeId)
        if (parentName != "") {
            interpClassParents.set(className, parentName)
        }
        return
    }

    if (kind == "EXPR_STMT") {
        if (nGetI1(nodeId) > 0) { interpEval(nGetI1(nodeId)) }
        return
    }

    if (kind == "IF") {
        const cond = interpEval(nGetI1(nodeId))
        if (interpTruthy(cond) == 1) {
            interpExec(nGetI2(nodeId))
        } else if (nGetI3(nodeId) > 0) {
            interpExec(nGetI3(nodeId))
        }
        return
    }

    if (kind == "WHILE") {
        while (true) {
            const cond = interpEval(nGetI1(nodeId))
            if (interpTruthy(cond) == 0) { break }
            interpExec(nGetI2(nodeId))
            if (interpCheckLoopExit() == 1) { break }
        }
        return
    }

    if (kind == "DO_WHILE") {
        while (true) {
            interpExec(nGetI1(nodeId))
            if (interpCheckLoopExit() == 1) { break }
            const cond = interpEval(nGetI2(nodeId))
            if (interpTruthy(cond) == 0) { break }
        }
        return
    }

    if (kind == "FOR") {
        interpPushScope()
        if (nGetI1(nodeId) > 0) { interpExec(nGetI1(nodeId)) }
        while (true) {
            if (nGetI2(nodeId) > 0) {
                const cond = interpEval(nGetI2(nodeId))
                if (interpTruthy(cond) == 0) { break }
            }
            interpExec(nGetI4(nodeId))
            if (interpCheckLoopExit() == 1) { break }
            if (nGetI3(nodeId) > 0) { interpExec(nGetI3(nodeId)) }
        }
        interpPopScope()
        return
    }

    if (kind == "FOR_IN" || kind == "FOR_OF") {
        const iterVal = interpEval(nGetI1(nodeId))
        if (interpType(iterVal) == "array") {
            const items = interpAsStr(iterVal)
            if (items != "") {
                const parts = items.split(",")
                interpPushScope()
                let fi = 0
                while (fi < parts.length()) {
                    interpSetVar(nGetS1(nodeId), parseInt(parts[fi]))
                    interpExec(nGetI2(nodeId))
                    if (interpCheckLoopExit() == 1) { break }
                    fi = fi + 1
                }
                interpPopScope()
            }
        }
        return
    }

    if (kind == "BREAK") {
        interpBreakFlag = 1
        return
    }

    if (kind == "CONTINUE") {
        interpContinueFlag = 1
        return
    }

    if (kind == "RETURN") {
        if (nGetI1(nodeId) > 0) {
            interpReturnVal = interpEval(nGetI1(nodeId))
        } else {
            interpReturnVal = interpNewNull()
        }
        interpReturnFlag = 1
        return
    }

    if (kind == "ASSIGN") {
        const name = nGetS1(nodeId)
        const op = nGetS2(nodeId)
        const rhs = interpEval(nGetI1(nodeId))
        if (op == "ASSIGN") {
            interpUpdateVar(name, rhs)
        } else {
            const old = interpGetVar(name)
            interpUpdateVar(name, interpCompoundOp(op, old, rhs))
        }
        return
    }

    if (kind == "MEMBER_ASSIGN") {
        const objVal = interpEval(nGetI1(nodeId))
        const fieldName = nGetS1(nodeId)
        const op = nGetS2(nodeId)
        const rhs = interpEval(nGetI2(nodeId))
        if (interpType(objVal) == "object") {
            if (op == "ASSIGN") {
                interpSetField(objVal, fieldName, rhs)
            } else {
                const old = interpGetField(objVal, fieldName)
                interpSetField(objVal, fieldName, interpCompoundOp(op, old, rhs))
            }
        }
        return
    }

    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") {
        interpEval(nodeId)
        return
    }

    if (kind == "INDEX_ASSIGN") {
        const arrName = nGetS1(nodeId)
        const idxVal = interpEval(nGetI1(nodeId))
        const rhs = interpEval(nGetI2(nodeId))
        const arrId = interpGetVar(arrName)
        if (interpType(arrId) == "array") {
            const items = interpAsStr(arrId)
            if (items != "") {
                const parts = items.split(",")
                const idx = interpAsInt(idxVal)
                if (idx >= 0 && idx < parts.length()) {
                    let newItems = ""
                    let ni = 0
                    while (ni < parts.length()) {
                        if (ni > 0) { newItems = `${newItems},` }
                        if (ni == idx) {
                            newItems = `${newItems}${rhs}`
                        } else {
                            newItems = `${newItems}${parts[ni]}`
                        }
                        ni = ni + 1
                    }
                    interpUpdateVar(arrName, interpNewArray(newItems))
                }
            }
        }
        return
    }

    println(`[interp] unsupported stmt: ${kind}`)
}
