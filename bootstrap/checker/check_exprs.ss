// check_exprs.ss — Expression checking (checkExpr dispatch + checkArgList walker).
// 20+ expr kinds dispatched by checkExpr; checkArgList handles NAMED_ARG / SPREAD_ELEM.
// State + helpers via global scope; delegates named-ctor / thread-capture to sibling modules.

function checkExpr(id: int) {
    if (id <= 0) { return }
    const kind = nGetKind(id)
    if (kind == "INT_LIT" || kind == "DOUBLE_LIT" || kind == "STRING_LIT") { return }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT" || kind == "NULL_LIT") { return }
    if (kind == "THIS") {
        if (currentStaticMethod == 1) {
            checkerError("'this' cannot be used in a static method", nGetLine(id), nGetCol(id))
        }
        return
    }
    if (kind == "SUPER") {
        if (currentStaticMethod == 1) {
            checkerError("'super' cannot be used in a static method", nGetLine(id), nGetCol(id))
            return
        }
        if (currentCheckerClass == "") {
            checkerError("'super' can only be used inside a class method", nGetLine(id), nGetCol(id))
        } else if (checkerClassParents.has(currentCheckerClass) == 0) {
            checkerError(`'super' cannot be used in class '${currentCheckerClass}' which has no parent class`, nGetLine(id), nGetCol(id))
        }
        return
    }
    if (kind == "IDENT") {
        const name = nGetS1(id)
        if (lookupVar(name) == "" && lookupFunc(name) == 0) {
            checkerError(`undefined variable '${name}'`, nGetLine(id), nGetCol(id), findSuggestion(name))
        }
        return
    }
    if (kind == "BINARY") {
        const binOp = nGetS1(id)
        if (binOp == "Instanceof" || binOp == "As") {
            checkExpr(nGetI1(id))
            const rightId = nGetI2(id)
            const opName = binOp == "Instanceof" ? "instanceof" : "as"
            // Validate left side is a class or interface type
            const leftType = checkerInferType(nGetI1(id), "")
            if (leftType != "" && leftType != "null") {
                const stripped = stripNullable(leftType)
                if (stripped != "" && checkerClassFields.has(stripped) == 0 && ifaceMethods.has(stripped) == 0) {
                    checkerError(`${opName} requires a class instance on the left side, got '${leftType}'`, nGetLine(id), nGetCol(id), "")
                }
            }
            if (nGetKind(rightId) != "IDENT") {
                checkerError(`${opName} requires a class name on the right side`, nGetLine(id), nGetCol(id), "")
            } else {
                const className = nGetS1(rightId)
                if (checkerClassFields.has(className) == 0) {
                    checkerError(`unknown class '${className}' in ${opName}`, nGetLine(rightId), nGetCol(rightId), findSuggestion(className))
                }
            }
            return
        }
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
                        const actualType = checkerInferType(caId, expectedType)
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
        // D068: Check private/protected method access
        if (recvClass != "") {
            const pmOwner = lookupPrivateOwner(recvClass, methodName, 1)
            if (pmOwner != "" && currentCheckerClass != pmOwner) {
                checkerError(`cannot access private method '${methodName}' of class '${pmOwner}'`, nGetLine(id), nGetCol(id))
            }
            const ptmOwner = lookupProtectedOwner(recvClass, methodName, 1)
            if (ptmOwner != "" && currentCheckerClass != ptmOwner && isSubclassOf(currentCheckerClass, ptmOwner) == 0) {
                checkerError(`cannot access protected method '${methodName}' of class '${ptmOwner}'`, nGetLine(id), nGetCol(id))
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
        // Check argument types (non-overloaded methods only)
        if (recvClass != "" && methodOverloaded.has(`${recvClass}.${methodName}`) == 0) {
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
                        const mcActType = checkerInferType(mcaId, mcExpType)
                        if (mcActType != "" && isTypeCompatible(mcExpType, mcActType) == 0) {
                            checkerError(`argument ${mcArgIdx + 1} of method '${methodName}': expected '${mcExpType}', got '${mcActType}'`, nGetLine(mcaId), nGetCol(mcaId))
                        }
                    }
                    mcArgIdx = mcArgIdx + 1
                }
            }
        }
        // D082 Phase 3: Thread.start closure capture validation
        if (recvClass == "Thread" && methodName == "start") {
            const tsArgList = nGetList(id)
            if (tsArgList != "") {
                const tsFirstArgId = parseInt(tsArgList.split(",")[0])
                if (tsFirstArgId > 0 && nGetKind(tsFirstArgId) == "ARROW_FUNC") {
                    checkThreadClosureCaptures(tsFirstArgId)
                }
            }
        }
        checkArgList(nGetList(id))
        return
    }
    if (kind == "MEMBER_ACCESS") {
        checkExpr(nGetI1(id))
        // D078: ClassName.staticField access
        const maObjNode = nGetI1(id)
        const maFieldName = nGetS1(id)
        if (nGetKind(maObjNode) == "IDENT" && lookupVar(nGetS1(maObjNode)) == "class") {
            const maClassName = nGetS1(maObjNode)
            const maSfKey = `${maClassName}.${maFieldName}`
            if (checkerFieldTypes.has(maSfKey) == 1 && staticFields.has(maSfKey) == 0) {
                checkerError(`field '${maFieldName}' is not static; access it via an instance, not '${maClassName}'`, nGetLine(id), nGetCol(id))
            }
            if (staticFields.has(maSfKey) == 1) {
                const maSfPfOwner = lookupPrivateOwner(maClassName, maFieldName, 0)
                if (maSfPfOwner != "" && currentCheckerClass != maSfPfOwner) {
                    checkerError(`cannot access private static field '${maFieldName}' of class '${maSfPfOwner}'`, nGetLine(id), nGetCol(id))
                }
                const maSfPtOwner = lookupProtectedOwner(maClassName, maFieldName, 0)
                if (maSfPtOwner != "" && currentCheckerClass != maSfPtOwner && isSubclassOf(currentCheckerClass, maSfPtOwner) == 0) {
                    checkerError(`cannot access protected static field '${maFieldName}' of class '${maSfPtOwner}'`, nGetLine(id), nGetCol(id))
                }
            }
            return
        }
        const maObjClass = inferCheckerClass(maObjNode)
        if (maObjClass != "") {
            // D078: reject instance.staticField
            if (staticFields.has(`${maObjClass}.${maFieldName}`) == 1) {
                checkerError(`static field '${maFieldName}' should be accessed via class name '${maObjClass}', not via instance`, nGetLine(id), nGetCol(id))
                return
            }
            const maPfOwner = lookupPrivateOwner(maObjClass, maFieldName, 0)
            if (maPfOwner != "" && currentCheckerClass != maPfOwner) {
                checkerError(`cannot access private field '${maFieldName}' of class '${maPfOwner}'`, nGetLine(id), nGetCol(id))
            }
            const maPtOwner = lookupProtectedOwner(maObjClass, maFieldName, 0)
            if (maPtOwner != "" && currentCheckerClass != maPtOwner && isSubclassOf(currentCheckerClass, maPtOwner) == 0) {
                checkerError(`cannot access protected field '${maFieldName}' of class '${maPtOwner}'`, nGetLine(id), nGetCol(id))
            }
        }
        return
    }
    if (kind == "INDEX_ACCESS") {
        checkExpr(nGetI1(id))
        checkExpr(nGetI2(id))
        const idxNode = nGetI2(id)
        if (idxNode > 0 && nGetKind(idxNode) != "STRING_LIT") {
            const objCls = inferCheckerClass(nGetI1(id))
            if (objCls != "" && checkerClassFields.has(objCls) == 1) {
                let allowed = 0
                if (nGetKind(idxNode) == "IDENT" && checkerFieldsForInVars != "") {
                    const probe = `,${checkerFieldsForInVars},`
                    if (probe.indexOf(`,${nGetS1(idxNode)},`) >= 0) { allowed = 1 }
                }
                if (allowed == 0) {
                    checkerError(`dynamic field name on class '${objCls}'; use obj["x"] or for (n in obj.fields())`, nGetLine(id), nGetCol(id))
                }
            }
        }
        return
    }
    if (kind == "NEW_EXPR") {
        const className = nGetS1(id)
        // D071 R1: Cannot instantiate abstract class
        if (abstractClasses.has(className) == 1) {
            checkerError(`cannot create an instance of abstract class '${className}'`, nGetLine(id), nGetCol(id))
        }
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
            // Check positional argument types
            if (hasSpreadArg(argList) == 0 && argList != "") {
                const newArgs = argList.split(",")
                let newArgIdx = 0
                for (na in newArgs) {
                    const naId = parseInt(na)
                    if (naId <= 0) { continue }
                    const expType = lookupConsParamType(className, newArgIdx)
                    if (expType != "") {
                        const actType = checkerInferType(naId, expType)
                        if (actType != "" && isTypeCompatible(expType, actType) == 0) {
                            checkerError(`argument ${newArgIdx + 1} of constructor '${className}': expected '${expType}', got '${actType}'`, nGetLine(naId), nGetCol(naId))
                        }
                    }
                    newArgIdx = newArgIdx + 1
                }
            }
        }
        checkArgList(argList)
        return
    }
    if (kind == "ARRAY_LIT") {
        checkArgList(nGetList(id))
        return
    }
    if (kind == "OBJ_LITERAL") {
        // D143 Phase 2: untyped OBJ_LITERAL 改 checker 放行(D141 ARROW_FUNC + D142 ARRAY_LIT 同模式)—
        // 反推回填 nSetS2 发生在 codegen 阶段 gen_calls.ss + gen/methods/gen_methods.ss args 循环
        // (inferObjLiteralFields helper),反推得 className 后 D084 rewrite OBJ_LITERAL → NEW_EXPR;
        // 反推不得 + 非 typed 上下文 → codegen 阶段硬错(H13 粒度)。checker 阶段先 checkExpr 字段值表达式
        // 让字段值类型检查不漏(部分字段值可能是 nested expr),但不再阻塞 OBJ_LITERAL 节点本身。
        const objLitFields = nGetList(id)
        if (objLitFields != "") {
            const olfParts = objLitFields.split(",")
            for (olfp in olfParts) {
                const olfId = parseInt(olfp)
                if (olfId > 0 && nGetKind(olfId) == "NAMED_ARG") {
                    const olfValId = nGetI1(olfId)
                    if (olfValId > 0) { checkExpr(olfValId) }
                }
            }
        }
        return
    }
    if (kind == "TERNARY") {
        checkExpr(nGetI1(id))
        checkExpr(nGetI2(id))
        checkExpr(nGetI3(id))
        // D144 Phase 2: 两分支类型一致性 + nSetS2 回填(D141/D142/D143 同模式扩)—
        // X mismatch 修复入口:`takesInt((cond)?1:"X")` 当前 silent miscompile,
        // 两分支基础类型不一致硬错(参 D143 §A.2 H4 决策行严格模式继承);两分支同类型时回填
        // nSetS2 让下游 inferType 直接消费(显式优先于 codegen 反推);含 NULL_LIT 分支 / class 分支
        // mismatch 跳过严格 check,等 codegen 阶段 inferTernaryBranchType 反推 callee T?/IShape upcast
        if (nGetS2(id) == "") {
            const ternThenT = checkerInferType(nGetI2(id), "")
            const ternElseT = checkerInferType(nGetI3(id), "")
            if (ternThenT != "" && ternElseT != "" && ternThenT != ternElseT) {
                const tIsP = (ternThenT == "int" || ternThenT == "double" || ternThenT == "string" || ternThenT == "bool") ? 1 : 0
                const eIsP = (ternElseT == "int" || ternElseT == "double" || ternElseT == "string" || ternElseT == "bool") ? 1 : 0
                if (tIsP == 1 && eIsP == 1) {
                    checkerError(`ternary branches type mismatch: '${ternThenT}' vs '${ternElseT}'`, nGetLine(id), nGetCol(id))
                }
            }
            if (ternThenT != "" && ternThenT == ternElseT && ternThenT != "null") {
                nSetS2(id, ternThenT)
            }
        }
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
