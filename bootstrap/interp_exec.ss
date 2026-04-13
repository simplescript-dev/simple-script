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

    if (kind == "ENUM_DECL") {
        const eName = nGetS1(nodeId)
        const isStringEnum = nGetI1(nodeId)
        if (isStringEnum == 1) { interpEnumTypes.set(eName, "1") }
        interpEnumNodes.set(eName, `${nodeId}`)
        const vl = nGetList(nodeId)
        if (vl != "") {
            const parts = vl.split(",")
            for (p in parts) {
                const vid = parseInt(p)
                if (vid > 0 && nGetKind(vid) == "ENUM_VARIANT") {
                    const vName = nGetS1(vid)
                    if (isStringEnum == 1) {
                        interpEnumValues.set(`${eName}.${vName}`, nGetS2(vid))
                    } else {
                        interpEnumValues.set(`${eName}.${vName}`, `${nGetI1(vid)}`)
                    }
                }
            }
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

    if (kind == "THROW") {
        const throwExprId = nGetI1(nodeId)
        interpThrowVal = interpEval(throwExprId)
        interpThrowFlag = 1
        return
    }

    if (kind == "TRY") {
        const tryBodyId = nGetI1(nodeId)
        const finallyBodyId = nGetI3(nodeId)
        const catchList = nGetList(nodeId)

        // Execute try body
        interpExec(tryBodyId)

        // If throw occurred, find matching catch clause
        if (interpThrowFlag == 1) {
            interpThrowFlag = 0
            const thrownVal = interpThrowVal
            interpThrowVal = 0
            let caught = 0
            if (catchList != "") {
                const clauses = catchList.split(",")
                let ci = 0
                while (ci < clauses.length() && caught == 0) {
                    const clauseId = parseInt(clauses[ci])
                    if (clauseId > 0) {
                        const catchVarName = nGetS1(clauseId)
                        const catchBodyId = nGetI1(clauseId)
                        // Bind exception value to catch variable
                        interpPushScope()
                        if (catchVarName != "") {
                            interpSetVar(catchVarName, thrownVal)
                        }
                        interpExec(catchBodyId)
                        interpPopScope()
                        caught = 1
                    }
                    ci = ci + 1
                }
            }
            if (caught == 0) {
                // No catch matched — re-throw
                interpThrowVal = thrownVal
                interpThrowFlag = 1
            }
        }

        // Execute finally (always)
        if (finallyBodyId > 0) {
            const savedThrow = interpThrowFlag
            const savedThrowVal = interpThrowVal
            interpThrowFlag = 0
            interpExec(finallyBodyId)
            if (savedThrow == 1 && interpThrowFlag == 0) {
                interpThrowFlag = savedThrow
                interpThrowVal = savedThrowVal
            }
        }
        return
    }

    if (kind == "SWITCH") {
        const subjectVal = interpEval(nGetI1(nodeId))
        const defaultBodyId = nGetI2(nodeId)
        const caseList = nGetList(nodeId)
        let matched = 0
        if (caseList != "") {
            const cases = caseList.split(",")
            let si = 0
            while (si < cases.length() && matched == 0) {
                const caseId = parseInt(cases[si])
                if (caseId > 0) {
                    const patId = nGetI1(caseId)
                    const bodyId = nGetI2(caseId)
                    const patType = nGetS1(patId)
                    const patValue = nGetS2(patId)
                    // Compare subject with pattern value
                    let patMatch = 0
                    if (patType == "INT") {
                        patMatch = interpAsInt(subjectVal) == parseInt(patValue) ? 1 : 0
                    } else if (patType == "STRING") {
                        patMatch = interpAsStr(subjectVal) == patValue ? 1 : 0
                    } else if (patType == "BOOL") {
                        patMatch = interpAsInt(subjectVal) == parseInt(patValue) ? 1 : 0
                    } else {
                        patMatch = interpToStr(subjectVal) == patValue ? 1 : 0
                    }
                    if (patMatch == 1) {
                        interpExec(bodyId)
                        matched = 1
                    }
                }
                si = si + 1
            }
        }
        if (matched == 0 && defaultBodyId > 0) {
            interpExec(defaultBodyId)
        }
        return
    }

    println(`[interp] unsupported stmt: ${kind}`)
}
