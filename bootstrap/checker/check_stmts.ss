// check_stmts.ss — Statement and expression checking driver.
// Used by checker.ss via textual import.

import { editDistance, collectVisibleNames, findSuggestion } from "./check_suggest"
import { mangleMethodList } from "./check_types"

// Single source of truth for compile-time string-literal array detection.
// Returns csv of element string values; "" means reject (not ARRAY_LIT, empty,
// non-STRING_LIT element, or value containing ',' which would collide with the
// csv encoding reused from classFields). Checker tests emptiness to decide
// whether dynamic field names are allowed; codegen consumes the csv directly.
// One function means both passes can't drift out of sync.
function stringLitArrayCsv(id: int): string {
    if (nGetKind(id) != "ARRAY_LIT") { return "" }
    const elemList = nGetList(id)
    if (elemList == "") { return "" }
    const parts = elemList.split(",")
    let result = ""
    let i = 0
    while (i < parts.length()) {
        const eid = parseInt(parts[i])
        if (eid <= 0) { return "" }
        if (nGetKind(eid) != "STRING_LIT") { return "" }
        const sv = nGetS1(eid)
        if (sv.indexOf(",") >= 0) { return "" }
        if (result == "") { result = sv }
        else { result = `${result},${sv}` }
        i = i + 1
    }
    return result
}

// ── Statement checking ────────────────────────────────────────

function checkStmt(id: int) {
    const kind = nGetKind(id)
    if (kind == "FUNC_DECL") {
        rejectPrimitiveNullable(nGetS2(id), id)
        // D071: abstract methods have no body — just check params
        if (nGetI4(id) == 1) {
            pushScope()
            checkParamList(nGetList(id))
            popScope()
            return
        }
        pushScope()
        const paramList = nGetList(id)
        checkParamList(paramList)
        const bodyId = nGetI1(id)
        // Track return type and type params for RETURN statement type checking
        const prevFuncRetType = currentFuncRetType
        const prevTypeParams = currentTypeParams
        currentFuncRetType = nGetS2(id)
        currentTypeParams = nGetS3(id)
        // D070: Track static method context
        const prevStaticMethod = currentStaticMethod
        if (nGetI2(id) == 1) { currentStaticMethod = 1 }
        // D067 Phase 2: fresh narrowing scope per function
        const prevNarrowedTypes = narrowedTypes
        narrowedTypes = Map()
        checkBlock(bodyId)
        narrowedTypes = prevNarrowedTypes
        currentStaticMethod = prevStaticMethod
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
        // D138 Phase 1.5: arity-aware mangle 同 ifaceMethods 公约;check_class.ss:87 contains `,${req},` 比对依赖前后逗号包装
        let classMethods = ","
        if (methodsBlockId > 0) {
            const csv = mangleMethodList(nGetList(methodsBlockId), 1)
            if (csv != "") { classMethods = `,${csv},` }
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
        // D084: Rewrite OBJ_LITERAL → NEW_EXPR when type annotation present
        if (initId > 0 && nGetKind(initId) == "OBJ_LITERAL" && typeAnn != "") {
            nKind.set(initId + "", "NEW_EXPR")
            nSetS1(initId, typeAnn)
        }
        if (initId > 0) { checkExpr(initId) }
        if (typeAnn == "") { typeAnn = "auto" }
        rejectPrimitiveNullable(typeAnn, id)
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
                const doPfOwner = lookupPrivateOwner(objClass, fieldName, 0)
                if (doPfOwner != "" && currentCheckerClass != doPfOwner) {
                    checkerError(`cannot access private field '${fieldName}' of class '${doPfOwner}'`, nGetLine(id), nGetCol(id))
                }
                const doPtOwner = lookupProtectedOwner(objClass, fieldName, 0)
                if (doPtOwner != "" && currentCheckerClass != doPtOwner && isSubclassOf(currentCheckerClass, doPtOwner) == 0) {
                    checkerError(`cannot access protected field '${fieldName}' of class '${doPtOwner}'`, nGetLine(id), nGetCol(id))
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
        // D067 Phase 2: reassignment resets narrowing
        narrowedTypes.delete(name)
        return
    }
    if (kind == "MEMBER_ASSIGN") {
        const objExpr = nGetI1(id)
        const fieldName = nGetS1(id)
        const valId = nGetI2(id)
        if (objExpr > 0) { checkExpr(objExpr) }
        if (valId > 0) { checkExpr(valId) }
        // D078: ClassName.staticField = value
        if (nGetKind(objExpr) == "IDENT" && lookupVar(nGetS1(objExpr)) == "class") {
            const maClassName = nGetS1(objExpr)
            const sfKey = `${maClassName}.${fieldName}`
            if (staticFields.has(sfKey) == 0) {
                checkerError(`field '${fieldName}' is not static; assign it via an instance, not '${maClassName}'`, nGetLine(id), nGetCol(id))
            }
            if (constFields.has(sfKey) == 1) {
                checkerError(`cannot assign to const static field '${fieldName}' of class '${maClassName}'`, nGetLine(id), nGetCol(id))
            }
            const sfPfOwner = lookupPrivateOwner(maClassName, fieldName, 0)
            if (sfPfOwner != "" && currentCheckerClass != sfPfOwner) {
                checkerError(`cannot access private static field '${fieldName}' of class '${sfPfOwner}'`, nGetLine(id), nGetCol(id))
            }
            const sfPtOwner = lookupProtectedOwner(maClassName, fieldName, 0)
            if (sfPtOwner != "" && currentCheckerClass != sfPtOwner && isSubclassOf(currentCheckerClass, sfPtOwner) == 0) {
                checkerError(`cannot access protected static field '${fieldName}' of class '${sfPtOwner}'`, nGetLine(id), nGetCol(id))
            }
            if (nGetS2(id) == "ASSIGN" && checkerFieldTypes.has(sfKey) == 1 && valId > 0) {
                const sfType = checkerFieldTypes.getString(sfKey)
                const sfvType = checkerInferType(valId)
                if (sfvType != "" && isTypeCompatible(sfType, sfvType) == 0) {
                    checkerError(`type mismatch: cannot assign '${sfvType}' to static field '${fieldName}' of type '${sfType}'`, nGetLine(id), nGetCol(id))
                }
            }
            return
        }
        // Check if field is const
        const objClass = inferCheckerClass(objExpr)
        if (objClass != "") {
            const fieldKey = `${objClass}.${fieldName}`
            // D078: reject instance.staticField = value
            if (staticFields.has(fieldKey) == 1) {
                checkerError(`static field '${fieldName}' should be assigned via class name '${objClass}', not via instance`, nGetLine(id), nGetCol(id))
                return
            }
            if (constFields.has(fieldKey) == 1) {
                checkerError(`cannot assign to const field '${fieldName}' of class '${objClass}'`, nGetLine(id), nGetCol(id))
            }
            const pfOwner = lookupPrivateOwner(objClass, fieldName, 0)
            if (pfOwner != "" && currentCheckerClass != pfOwner) {
                checkerError(`cannot access private field '${fieldName}' of class '${pfOwner}'`, nGetLine(id), nGetCol(id))
            }
            const ptOwner = lookupProtectedOwner(objClass, fieldName, 0)
            if (ptOwner != "" && currentCheckerClass != ptOwner && isSubclassOf(currentCheckerClass, ptOwner) == 0) {
                checkerError(`cannot access protected field '${fieldName}' of class '${ptOwner}'`, nGetLine(id), nGetCol(id))
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
        // Type check: array element type vs assigned value
        const arrName = nGetS1(id)
        const arrType = lookupVar(arrName)
        if (arrType != "" && arrType != "auto" && valId > 0) {
            const elemType = extractElemType(arrType)
            if (elemType != "") {
                const vType = checkerInferType(valId)
                if (vType != "" && isTypeCompatible(elemType, vType) == 0) {
                    checkerError(`type mismatch: cannot assign '${vType}' to element of '${arrType}'`, nGetLine(id), nGetCol(id))
                }
            }
        }
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
        const condId = nGetI1(id)
        checkExpr(condId)
        // D067 Phase 2: detect null check for smart narrowing
        const ncVar = extractNullCheckVar(condId)
        let ncType = ""
        let ncOldNarrow = ""
        if (ncVar != "") {
            const ncVarType = lookupVar(ncVar)
            if (isNullableType(ncVarType) == 1) {
                ncType = stripNullable(ncVarType)
                ncOldNarrow = getNarrowedType(ncVar)
            }
        }
        // nGetS1(condId) is "Eq" or "Ne" (extractNullCheckVar verified BINARY Eq/Ne)
        const isEqNull = ncType != "" && nGetS1(condId) == "Eq" ? 1 : 0
        pushScope()
        if (ncType != "" && isEqNull == 0) {
            narrowedTypes.set(ncVar, ncType)
        }
        checkBlock(nGetI2(id))
        if (ncType != "" && isEqNull == 0) {
            restoreNarrowing(ncVar, ncOldNarrow)
        }
        popScope()
        const elseId = nGetI3(id)
        if (elseId > 0) {
            pushScope()
            if (ncType != "" && isEqNull == 1) {
                narrowedTypes.set(ncVar, ncType)
            }
            checkBlock(elseId)
            if (ncType != "" && isEqNull == 1) {
                restoreNarrowing(ncVar, ncOldNarrow)
            }
            popScope()
        }
        // Early exit: if the null-path always returns, narrow after the if
        if (ncType != "") {
            if (isEqNull == 1 && blockAlwaysReturns(nGetI2(id)) == 1) {
                narrowedTypes.set(ncVar, ncType)
            }
            if (isEqNull == 0 && elseId > 0 && blockAlwaysReturns(elseId) == 1) {
                narrowedTypes.set(ncVar, ncType)
            }
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
        const savedFFV = checkerFieldsForInVars
        const iterId = nGetI1(id)
        let allowDynFieldName = 0
        if (iterId > 0 && nGetKind(iterId) == "METHOD_CALL" && nGetS1(iterId) == "fields") {
            const recvCls = inferCheckerClass(nGetI1(iterId))
            if (recvCls != "" && checkerClassFields.has(recvCls) == 1) {
                allowDynFieldName = 1
            }
        }
        if (allowDynFieldName == 0 && iterId > 0 && stringLitArrayCsv(iterId) != "") {
            allowDynFieldName = 1
        }
        if (allowDynFieldName == 1) {
            const itemName = nGetS1(id)
            if (savedFFV == "") { checkerFieldsForInVars = itemName }
            else { checkerFieldsForInVars = `${savedFFV},${itemName}` }
        }
        checkBlock(nGetI2(id))
        checkerFieldsForInVars = savedFFV
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
        // Check catch clauses
        const catchList = nGetList(id)
        if (catchList != "") {
            const cparts = catchList.split(",")
            for (cp in cparts) {
                const cid = parseInt(cp)
                if (cid > 0) {
                    pushScope()
                    const errType = nGetS2(cid)
                    if (errType != "") {
                        defineVar(nGetS1(cid), errType, 0)
                    } else {
                        defineVar(nGetS1(cid), "string", 0)
                    }
                    checkBlock(nGetI1(cid))
                    popScope()
                }
            }
        }
        if (nGetI3(id) > 0) {
            pushScope()
            checkBlock(nGetI3(id))
            popScope()
        }
        return
    }
    if (kind == "THROW") {
        checkExpr(nGetI1(id))
        return
    }
    if (kind == "COMPTIME_BLOCK") {
        // Skip: checker pre-registration doesn't cover comptime-local functions
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
                const pType = nGetS2(paramId)
                rejectPrimitiveNullable(pType, paramId)
                defineVar(nGetS1(paramId), pType, 0)
            }
        }
    }
}
