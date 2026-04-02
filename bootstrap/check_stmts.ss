// check_stmts.ss — Statement and expression checking + return path analysis
// Used by checker.ss via textual import.

import { editDistance, collectVisibleNames, findSuggestion } from "./check_suggest"

// ── Return path analysis ─────────────────────────────────────

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
        if (blockAlwaysReturns(nGetI1(id)) == 1 && blockAlwaysReturns(nGetI2(id)) == 1) { return 1 }
        return 0
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

// ── Statement checking ────────────────────────────────────────

function checkStmt(id: int) {
    const kind = nGetKind(id)
    if (kind == "FUNC_DECL") {
        pushScope()
        const paramList = nGetList(id)
        checkParamList(paramList)
        const bodyId = nGetI1(id)
        // Track return type and type params for RETURN statement type checking
        const prevFuncRetType = currentFuncRetType
        const prevTypeParams = currentTypeParams
        currentFuncRetType = nGetS2(id)
        currentTypeParams = nGetS3(id)
        checkBlock(bodyId)
        currentFuncRetType = prevFuncRetType
        currentTypeParams = prevTypeParams
        popScope()
        // Return path analysis: non-void functions must return on all paths
        const retType = nGetS2(id)
        if (retType != "" && retType != "void") {
            if (blockAlwaysReturns(bodyId) == 0) {
                checkerError(`function '${nGetS1(id)}' with return type '${retType}' does not return on all paths`, nGetLine(id), nGetCol(id))
            }
        }
        return
    }
    if (kind == "CLASS_DECL") {
        const className = nGetS1(id)
        const implList = nGetS3(id)
        const methodsBlockId = nGetI2(id)
        // Collect class method names
        let classMethods = ","
        if (methodsBlockId > 0) {
            const ml = nGetList(methodsBlockId)
            if (ml != "") {
                const ms = ml.split(",")
                for (m in ms) {
                    const mId = parseInt(m)
                    if (mId > 0 && nGetKind(mId) == "FUNC_DECL") {
                        classMethods = `${classMethods}${nGetS1(mId)},`
                    }
                }
            }
        }
        // Verify interface implementations (uses contains to avoid i64/ptr bootstrap issue)
        if (implList != "") {
            checkInterfaceImpl(id, className, implList, classMethods)
        }
        // Check method bodies (with class context for this.method() resolution)
        const prevClass = currentCheckerClass
        currentCheckerClass = className
        if (methodsBlockId > 0) {
            const methodList = nGetList(methodsBlockId)
            checkStmtList(methodList)
        }
        currentCheckerClass = prevClass
        return
    }
    if (kind == "VAR_DECL") {
        const name = nGetS1(id)
        const varKind = nGetS2(id)
        let typeAnn = nGetS3(id)
        const initId = nGetI1(id)
        if (initId > 0) { checkExpr(initId) }
        if (typeAnn == "") { typeAnn = "auto" }
        // Infer class type from new expression initializer
        if (typeAnn == "auto" && initId > 0 && nGetKind(initId) == "NEW_EXPR") {
            typeAnn = nGetS1(initId)
        }
        // Type check: annotation vs initializer
        if (typeAnn != "auto" && initId > 0) {
            const initType = checkerInferType(initId)
            if (initType != "" && isTypeCompatible(typeAnn, initType) == 0) {
                checkerError(`type mismatch: cannot assign '${initType}' to variable '${name}' of type '${typeAnn}'`, nGetLine(id), nGetCol(id))
            }
        }
        if (varKind == "CONST") {
            defineVar(name, typeAnn, 1)
        } else {
            defineVar(name, typeAnn, 0)
        }
        return
    }
    if (kind == "DESTRUCTURE_ARRAY") {
        const initId = nGetI1(id)
        if (initId > 0) { checkExpr(initId) }
        const names = nGetS1(id)
        const varKind = nGetS2(id)
        const isConst = varKind == "CONST" ? 1 : 0
        const parts = names.split(",")
        for (n in parts) {
            if (n.startsWith("...") == 1) {
                const restName = n.substring(3, n.length() - 3)
                defineVar(restName, "auto", isConst)
            } else {
                defineVar(n, "auto", isConst)
            }
        }
        return
    }
    if (kind == "DESTRUCTURE_OBJECT") {
        const initId = nGetI1(id)
        if (initId > 0) { checkExpr(initId) }
        const names = nGetS1(id)
        const varKind = nGetS2(id)
        const isConst = varKind == "CONST" ? 1 : 0
        const objClass = inferCheckerClass(initId)
        const parts = names.split(",")
        for (n in parts) {
            let fieldName = n
            let varName = n
            const colonIdx = n.indexOf(":")
            if (colonIdx >= 0) {
                fieldName = n.substring(0, colonIdx)
                varName = n.substring(colonIdx + 1, n.length() - colonIdx - 1)
            }
            if (objClass != "" && checkerClassFields.has(objClass) == 1) {
                let fieldExists = 0
                const fieldsSplit = checkerClassFields.getString(objClass).split(",")
                for (f in fieldsSplit) {
                    if (f == fieldName) { fieldExists = 1 }
                }
                if (fieldExists == 0) {
                    checkerError(`'${fieldName}' is not a field of class '${objClass}'`, nGetLine(id), nGetCol(id))
                }
            }
            let vType = "auto"
            const ftKey = `${objClass}.${fieldName}`
            if (objClass != "" && checkerFieldTypes.has(ftKey) == 1) {
                vType = checkerFieldTypes.getString(ftKey)
            }
            defineVar(varName, vType, isConst)
        }
        return
    }
    if (kind == "ASSIGN") {
        const name = nGetS1(id)
        if (lookupVar(name) == "") {
            checkerError(`undefined variable '${name}'`, nGetLine(id), nGetCol(id), findSuggestion(name))
        }
        if (isVarConst(name) == 1) {
            checkerError(`cannot reassign const variable '${name}'`, nGetLine(id), nGetCol(id))
        }
        const valId = nGetI1(id)
        if (valId > 0) { checkExpr(valId) }
        // Type check: variable type vs RHS (simple assignment only)
        if (nGetS2(id) == "ASSIGN") {
            const varType = lookupVar(name)
            if (varType != "" && varType != "auto" && valId > 0) {
                const rhsType = checkerInferType(valId)
                if (rhsType != "" && isTypeCompatible(varType, rhsType) == 0) {
                    checkerError(`type mismatch: cannot assign '${rhsType}' to variable '${name}' of type '${varType}'`, nGetLine(id), nGetCol(id))
                }
            }
        }
        return
    }
    if (kind == "MEMBER_ASSIGN") {
        const objExpr = nGetI1(id)
        const fieldName = nGetS1(id)
        const valId = nGetI2(id)
        if (objExpr > 0) { checkExpr(objExpr) }
        if (valId > 0) { checkExpr(valId) }
        // Check if field is const
        const objClass = inferCheckerClass(objExpr)
        if (objClass != "") {
            const fieldKey = `${objClass}.${fieldName}`
            if (constFields.has(fieldKey) == 1) {
                checkerError(`cannot assign to const field '${fieldName}' of class '${objClass}'`, nGetLine(id), nGetCol(id))
            }
            // Type check: field type vs assigned value
            if (nGetS2(id) == "ASSIGN" && checkerFieldTypes.has(fieldKey) == 1 && valId > 0) {
                const fType = checkerFieldTypes.getString(fieldKey)
                const vType = checkerInferType(valId)
                if (vType != "" && isTypeCompatible(fType, vType) == 0) {
                    checkerError(`type mismatch: cannot assign '${vType}' to field '${fieldName}' of type '${fType}'`, nGetLine(id), nGetCol(id))
                }
            }
        }
        return
    }
    if (kind == "INDEX_ASSIGN") {
        const indexId = nGetI1(id)
        const valId = nGetI2(id)
        if (indexId > 0) { checkExpr(indexId) }
        if (valId > 0) { checkExpr(valId) }
        return
    }
    if (kind == "EXPR_STMT") {
        const exprId = nGetI1(id)
        if (exprId > 0) { checkExpr(exprId) }
        return
    }
    if (kind == "RETURN") {
        const valId = nGetI1(id)
        if (valId > 0) { checkExpr(valId) }
        // Type check: return value type vs function return type
        if (currentFuncRetType != "" && currentFuncRetType != "void" && valId > 0) {
            const retValType = checkerInferType(valId)
            if (retValType != "" && isTypeCompatible(currentFuncRetType, retValType) == 0) {
                checkerError(`type mismatch: cannot return '${retValType}' from function with return type '${currentFuncRetType}'`, nGetLine(id), nGetCol(id))
            }
        }
        return
    }
    if (kind == "IF") {
        checkExpr(nGetI1(id))
        pushScope()
        checkBlock(nGetI2(id))
        popScope()
        const elseId = nGetI3(id)
        if (elseId > 0) {
            pushScope()
            checkBlock(elseId)
            popScope()
        }
        return
    }
    if (kind == "FOR") {
        pushScope()
        checkStmt(nGetI1(id))
        checkExpr(nGetI2(id))
        checkStmt(nGetI3(id))
        checkBlock(nGetI4(id))
        popScope()
        return
    }
    if (kind == "FOR_IN" || kind == "FOR_OF") {
        pushScope()
        checkExpr(nGetI1(id))
        defineVar(nGetS1(id), "auto", 0)
        checkBlock(nGetI2(id))
        popScope()
        return
    }
    if (kind == "WHILE") {
        checkExpr(nGetI1(id))
        pushScope()
        checkBlock(nGetI2(id))
        popScope()
        return
    }
    if (kind == "DO_WHILE") {
        pushScope()
        checkBlock(nGetI1(id))
        popScope()
        checkExpr(nGetI2(id))
        return
    }
    if (kind == "SWITCH") {
        checkExpr(nGetI1(id))
        const caseList = nGetList(id)
        checkStmtList(caseList)
        const defId = nGetI2(id)
        if (defId > 0) { checkBlock(defId) }
        return
    }
    if (kind == "SWITCH_CASE") {
        checkBlock(nGetI2(id))
        return
    }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { checkExpr(id); return }
    if (kind == "TRY") {
        pushScope()
        checkBlock(nGetI1(id))
        popScope()
        pushScope()
        defineVar(nGetS1(id), "string", 0)
        checkBlock(nGetI2(id))
        popScope()
        return
    }
    if (kind == "THROW") {
        checkExpr(nGetI1(id))
        return
    }
    // IMPORT, INTERFACE_DECL, ENUM_DECL, BREAK, CONTINUE — no checks needed
}

function checkBlock(blockId: int) {
    if (blockId <= 0) { return }
    const kind = nGetKind(blockId)
    if (kind != "BLOCK") { return }
    const stmtList = nGetList(blockId)
    checkStmtList(stmtList)
}

function checkStmtList(listStr: string) {
    if (listStr == "") { return }
    const parts = listStr.split(",")
    for (p in parts) {
        const childId = parseInt(p)
        if (childId > 0) {
            checkStmt(childId)
        }
    }
}

function checkParamList(listStr: string) {
    if (listStr == "") { return }
    const parts = listStr.split(",")
    for (p in parts) {
        const paramId = parseInt(p)
        if (paramId > 0) {
            const pk = nGetKind(paramId)
            if (pk == "PARAM") {
                defineVar(nGetS1(paramId), nGetS2(paramId), 0)
            }
        }
    }
}

// ── Expression checking ───────────────────────────────────────

function checkExpr(id: int) {
    if (id <= 0) { return }
    const kind = nGetKind(id)
    if (kind == "INT_LIT" || kind == "DOUBLE_LIT" || kind == "STRING_LIT") { return }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT" || kind == "NULL_LIT") { return }
    if (kind == "THIS") { return }
    if (kind == "IDENT") {
        const name = nGetS1(id)
        if (lookupVar(name) == "" && lookupFunc(name) == 0) {
            checkerError(`undefined variable '${name}'`, nGetLine(id), nGetCol(id), findSuggestion(name))
        }
        return
    }
    if (kind == "BINARY") {
        checkExpr(nGetI1(id))
        checkExpr(nGetI2(id))
        return
    }
    if (kind == "UNARY") {
        checkExpr(nGetI1(id))
        return
    }
    if (kind == "CALL") {
        const callee = nGetS1(id)
        if (lookupFunc(callee) == 0 && lookupVar(callee) == "") {
            checkerError(`undefined function '${callee}'`, nGetLine(id), nGetCol(id), findSuggestion(callee))
        }
        const callArgList = nGetList(id)
        const argCount = countArgs(callArgList)
        const hasSpread = hasSpreadArg(callArgList)
        if (funcParamMin.has(callee) == 1 && hasSpread == 0) {
            checkArgCount("function", callee, argCount, parseInt(funcParamMin.getString(callee)), parseInt(funcParamMax.getString(callee)), nGetLine(id), nGetCol(id))
        }
        // Check argument types (non-overloaded user functions only)
        if (funcOverloaded.has(callee) == 0 && hasSpread == 0) {
            if (callArgList != "") {
                const callArgs = callArgList.split(",")
                let callArgIdx = 0
                for (ca in callArgs) {
                    const caId = parseInt(ca)
                    if (caId <= 0) { continue }
                    if (nGetKind(caId) == "NAMED_ARG" || nGetKind(caId) == "SPREAD_ELEM") {
                        callArgIdx = callArgIdx + 1
                        continue
                    }
                    const ptKey = `${callee}:${callArgIdx}`
                    if (funcParamTypes.has(ptKey) == 1) {
                        const expectedType = funcParamTypes.getString(ptKey)
                        const actualType = checkerInferType(caId)
                        if (actualType != "" && isTypeCompatible(expectedType, actualType) == 0) {
                            checkerError(`argument ${callArgIdx + 1} of '${callee}': expected '${expectedType}', got '${actualType}'`, nGetLine(caId), nGetCol(caId))
                        }
                    }
                    callArgIdx = callArgIdx + 1
                }
            }
        }
        checkArgList(nGetList(id))
        return
    }
    if (kind == "METHOD_CALL") {
        checkExpr(nGetI1(id))
        const methodName = nGetS1(id)
        const objId = nGetI1(id)
        const argCount = countArgs(nGetList(id))
        // Resolve receiver class (inferCheckerClass handles base type normalization)
        let recvClass = ""
        if (objId > 0) {
            recvClass = inferCheckerClass(objId)
            // Namespace fallback (Math.sqrt() → "Math" IDENT has type "namespace")
            if (classConsMin.has(recvClass) == 0 && nGetKind(objId) == "IDENT" && classConsMin.has(nGetS1(objId)) == 1) {
                recvClass = nGetS1(objId)
            }
        }
        // Check method arg count if receiver class is known
        if (recvClass != "") {
            const mParams = lookupMethodParams(recvClass, methodName)
            if (mParams != "") {
                const commaIdx = mParams.indexOf(",")
                const mMin = parseInt(mParams.substring(0, commaIdx))
                const mMax = parseInt(mParams.substring(commaIdx + 1, mParams.length() - commaIdx - 1))
                checkArgCount("method", methodName, argCount, mMin, mMax, nGetLine(id), nGetCol(id))
            }
        }
        // Check argument types (when receiver class is known)
        if (recvClass != "") {
            const mcArgList = nGetList(id)
            if (hasSpreadArg(mcArgList) == 0 && mcArgList != "") {
                const mcArgs = mcArgList.split(",")
                let mcArgIdx = 0
                for (mca in mcArgs) {
                    const mcaId = parseInt(mca)
                    if (mcaId <= 0) { continue }
                    if (nGetKind(mcaId) == "NAMED_ARG" || nGetKind(mcaId) == "SPREAD_ELEM") {
                        mcArgIdx = mcArgIdx + 1
                        continue
                    }
                    const mcExpType = lookupMethodParamType(recvClass, methodName, mcArgIdx)
                    if (mcExpType != "") {
                        const mcActType = checkerInferType(mcaId)
                        if (mcActType != "" && isTypeCompatible(mcExpType, mcActType) == 0) {
                            checkerError(`argument ${mcArgIdx + 1} of method '${methodName}': expected '${mcExpType}', got '${mcActType}'`, nGetLine(mcaId), nGetCol(mcaId))
                        }
                    }
                    mcArgIdx = mcArgIdx + 1
                }
            }
        }
        checkArgList(nGetList(id))
        return
    }
    if (kind == "MEMBER_ACCESS") {
        checkExpr(nGetI1(id))
        return
    }
    if (kind == "INDEX_ACCESS") {
        checkExpr(nGetI1(id))
        checkExpr(nGetI2(id))
        return
    }
    if (kind == "NEW_EXPR") {
        const className = nGetS1(id)
        const argList = nGetList(id)
        // Check if args contain NAMED_ARG nodes
        let hasNamed = 0
        if (argList != "") {
            const ci = argList.indexOf(",")
            const firstId = parseInt(ci >= 0 ? argList.substring(0, ci) : argList)
            if (firstId > 0 && nGetKind(firstId) == "NAMED_ARG") { hasNamed = 1 }
        }
        if (hasNamed == 1) {
            checkNamedConstructorArgs(className, argList, nGetLine(id), nGetCol(id))
        } else {
            const argCount = countArgs(argList)
            if (classConsMin.has(className) == 1) {
                const consTotal = totalConstructorParams(className)
                const ctComma = consTotal.indexOf(",")
                checkArgCount("constructor", className, argCount, parseInt(consTotal.substring(0, ctComma)), parseInt(consTotal.substring(ctComma + 1, consTotal.length() - ctComma - 1)), nGetLine(id), nGetCol(id))
            }
        }
        checkArgList(argList)
        return
    }
    if (kind == "ARRAY_LIT") {
        checkArgList(nGetList(id))
        return
    }
    if (kind == "TERNARY") {
        checkExpr(nGetI1(id))
        checkExpr(nGetI2(id))
        checkExpr(nGetI3(id))
        return
    }
    if (kind == "GROUPING") {
        checkExpr(nGetI1(id))
        return
    }
    if (kind == "TEMPLATE_LIT") {
        const fragList = nGetList(id)
        if (fragList != "") {
            const parts = fragList.split(",")
            for (p in parts) {
                const fragId = parseInt(p)
                if (fragId > 0) {
                    const fk = nGetKind(fragId)
                    if (fk == "TMPL_FRAG_EXPR") {
                        checkExpr(nGetI1(fragId))
                    }
                }
            }
        }
        return
    }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") {
        const name = nGetS1(id)
        if (lookupVar(name) == "") {
            checkerError(`undefined variable '${name}'`, nGetLine(id), nGetCol(id), findSuggestion(name))
        }
        return
    }
}

function checkArgList(listStr: string) {
    if (listStr == "") { return }
    const parts = listStr.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0) {
            if (nGetKind(argId) == "NAMED_ARG") {
                checkExpr(nGetI1(argId))
            } else if (nGetKind(argId) == "SPREAD_ELEM") {
                checkExpr(nGetI1(argId))
            } else {
                checkExpr(argId)
            }
        }
    }
}

// Validate named constructor arguments: all names must be valid fields, no duplicates
function checkNamedConstructorArgs(className: string, argList: string, line: int, col: int) {
    if (argList == "") { return }
    // Resolve full field list including parent fields
    let fullFields = ""
    let cls = className
    while (cls != "") {
        if (checkerClassFields.has(cls) == 1) {
            const ownFields = checkerClassFields.getString(cls)
            if (ownFields != "") {
                if (fullFields == "") { fullFields = ownFields }
                else { fullFields = `${ownFields},${fullFields}` }
            }
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    let seen = Map()
    let namedCount = 0
    const fieldsSplit = fullFields != "" ? fullFields.split(",") : "".split(",")
    const parts = argList.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId <= 0) { continue }
        if (nGetKind(argId) != "NAMED_ARG") {
            checkerError("cannot mix positional and named arguments in constructor", line, col)
            return
        }
        const argName = nGetS1(argId)
        namedCount = namedCount + 1
        // Check duplicate
        if (seen.has(argName) == 1) {
            checkerError(`duplicate named argument '${argName}' in constructor '${className}'`, nGetLine(argId), nGetCol(argId))
            continue
        }
        seen.set(argName, "1")
        // Check field exists
        let found = 0
        for (f in fieldsSplit) {
            if (f == argName) { found = 1 }
        }
        if (found == 0) {
            checkerError(`'${argName}' is not a field of class '${className}'`, nGetLine(argId), nGetCol(argId))
        }
    }
    // Check all required fields are provided
    for (f in fieldsSplit) {
        if (f == "" ) { continue }
        if (seen.has(f) == 0) {
            checkerError(`missing field '${f}' in named constructor for '${className}'`, line, col)
        }
    }
}
