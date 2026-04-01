// gen_calls.ss — Function calls, template literals, array literals
// Arrow functions and closures in gen_arrows.ss.

import { genArrowFunc, flushArrowDefs } from "./gen_arrows"

// ── Print call ──────────────────────────────────────────────────

function genPrintCall(callee: string, argList: string): string {
    const fnName = runtimeName(callee)
    if (argList == "") {
        const emptyStr = addStringConst("")
        emitIR(`  call void @${fnName}(ptr ${emptyStr})`)
        return "0"
    }
    let result = ""
    let resultOwned = 0
    const parts = argList.split(",")
    let first = 1
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0) {
            const argStr = genExprAsString(argId)
            const argOwned = lastExprStringOwned
            if (first == 1) {
                result = argStr
                resultOwned = argOwned
                first = 0
            } else {
                const space = addStringConst(" ")
                const r1 = nextReg()
                emitIR(`  ${r1} = call ptr @ss_string_concat(ptr ${result}, ptr ${space})`)
                if (resultOwned == 1) {
                    emitIR(`  call void @ss_rc_release(ptr ${result})`)
                }
                const r2 = nextReg()
                emitIR(`  ${r2} = call ptr @ss_string_concat(ptr ${r1}, ptr ${argStr})`)
                emitIR(`  call void @ss_rc_release(ptr ${r1})`)
                if (argOwned == 1) {
                    emitIR(`  call void @ss_rc_release(ptr ${argStr})`)
                }
                result = r2
                resultOwned = 1
            }
        }
    }
    emitIR(`  call void @${fnName}(ptr ${result})`)
    if (resultOwned == 1) {
        emitIR(`  call void @ss_rc_release(ptr ${result})`)
    }
    return "0"
}

// ── Call argument resolution ────────────────────────────────────

function resolveCallArgs(callee: string, argList: string, expectsDouble: int): string {
    let providedArgs = ""
    let providedCount = 0
    let spreadNodeId = 0
    if (argList != "") {
        const parts = argList.split(",")
        for (p in parts) {
            const argId = parseInt(p)
            if (argId > 0) {
                if (nGetKind(argId) == "SPREAD_ELEM") {
                    spreadNodeId = argId
                } else {
                    providedArgs = listAppend(providedArgs, argId)
                    providedCount = providedCount + 1
                }
            }
        }
    }
    let expectedCount = providedCount
    if (funcParamCount.has(callee) == 1) {
        expectedCount = parseInt(funcParamCount.getString(callee))
    }
    let fullArgs = providedArgs
    if (spreadNodeId == 0 && providedCount < expectedCount && funcDefaults.has(callee) == 1) {
        const defs = funcDefaults.getString(callee)
        const defParts = defs.split(",")
        for (dp in defParts) {
            const colonPos = dp.indexOf(":")
            if (colonPos > 0) {
                const defIdx = parseInt(dp.substring(0, colonPos))
                const defNodeId = dp.substring(colonPos + 1, dp.length() - colonPos - 1)
                if (defIdx >= providedCount) {
                    fullArgs = listAppendStr(fullArgs, defNodeId)
                }
            }
        }
    }
    let args = ""
    if (fullArgs != "") {
        const argParts = fullArgs.split(",")
        let first = 1
        for (ap in argParts) {
            const argId = parseInt(ap)
            if (argId > 0) {
                let val = genExpr(argId)
                let vType = inferType(argId)
                if (expectsDouble && (vType == "int" || vType == "auto")) {
                    const cvR = nextReg()
                    emitIR(`  ${cvR} = sitofp i32 ${val} to double`)
                    val = cvR
                    vType = "double"
                }
                const llType = ssTypeToLLVM(vType)
                if (first == 1) { first = 0 } else { args = args + ", " }
                args = `${args}${llType} ${val}`
            }
        }
    }
    // Expand spread argument: extract elements from array for remaining params
    if (spreadNodeId > 0) {
        const spreadArrExpr = nGetI1(spreadNodeId)
        const spreadArr = genExpr(spreadArrExpr)
        let elemType = inferArrayElemType(spreadArrExpr)
        if (elemType == "") { elemType = "i64" }
        const spreadCount = expectedCount - providedCount
        let idx = 0
        while (idx < spreadCount) {
            const elemVal = nextReg()
            emitIR(`  ${elemVal} = call i64 @ss_arrayGet(ptr ${spreadArr}, i32 ${idx})`)
            let converted = elemVal
            let convType = elemType
            if (elemType == "string" || ssTypeToLLVM(elemType) == "ptr") {
                converted = nextReg()
                emitIR(`  ${converted} = inttoptr i64 ${elemVal} to ptr`)
            } else if (elemType == "int") {
                converted = nextReg()
                emitIR(`  ${converted} = trunc i64 ${elemVal} to i32`)
            } else if (elemType == "double") {
                converted = nextReg()
                emitIR(`  ${converted} = bitcast i64 ${elemVal} to double`)
                convType = "double"
            }
            if (expectsDouble && (convType == "int" || convType == "auto")) {
                const dblR = nextReg()
                emitIR(`  ${dblR} = sitofp i32 ${converted} to double`)
                converted = dblR
                convType = "double"
            }
            const llType = ssTypeToLLVM(convType)
            if (args != "") { args = args + ", " }
            args = `${args}${llType} ${converted}`
            idx = idx + 1
        }
    }
    return args
}

// ── Generic function monomorphization ───────────────────────────

function genGenericCall(id: int, callee: string, argList: string): string {
    const funcNodeId = parseInt(genericFuncNodes.getString(callee))
    const typeParamStr = nGetS3(funcNodeId)
    const typeParamList = typeParamStr.split(",")
    const declParams = nGetList(funcNodeId)

    // 1. Resolve type params (explicit or inferred) + 2. Build mangled name
    const subs = Map()
    const explicitTypes = nGetS2(id)
    if (explicitTypes != "") {
        let tpIdx = 0
        for (tp in typeParamList) {
            subs.set(tp, listGet(explicitTypes, tpIdx))
            tpIdx = tpIdx + 1
        }
    } else if (declParams != "") {
        const dParts = declParams.split(",")
        const aParts = argList != "" ? argList.split(",") : ""
        let argIdx = 0
        for (dp in dParts) {
            const pId = parseInt(dp)
            if (pId <= 0 || nGetKind(pId) != "PARAM") { continue }
            const pType = nGetS2(pId)
            if (aParts != "") {
                let isTP = 0
                for (tp in typeParamList) {
                    if (tp == pType) { isTP = 1 }
                }
                if (isTP == 1 && subs.has(pType) == 0) {
                    let ai = 0
                    for (ap in aParts) {
                        if (ai == argIdx) {
                            subs.set(pType, inferType(parseInt(ap)))
                        }
                        ai = ai + 1
                    }
                }
            }
            argIdx = argIdx + 1
        }
    }
    let mangledSig = ""
    if (declParams != "") {
        const dParts2 = declParams.split(",")
        for (dp2 in dParts2) {
            const pId2 = parseInt(dp2)
            if (pId2 <= 0 || nGetKind(pId2) != "PARAM") { continue }
            let pt = nGetS2(pId2)
            if (subs.has(pt) == 1) { pt = subs.getString(pt) }
            if (mangledSig != "") { mangledSig = `${mangledSig}_` }
            mangledSig = `${mangledSig}${typeSig(pt)}`
        }
    }

    const mangledName = mangledSig != "" ? `${callee}_${mangledSig}` : callee

    // 3. Resolve return type
    let resolvedRet = nGetS2(funcNodeId)
    if (resolvedRet == "" ) { resolvedRet = "void" }
    if (subs.has(resolvedRet) == 1) { resolvedRet = subs.getString(resolvedRet) }

    // 4. Emit specialization if not already done
    if (specializedFuncs.has(mangledName) == 0) {
        // Validate type constraints
        for (tp in typeParamList) {
            const constraint = funcConstraint(callee, tp)
            if (constraint != "" && subs.has(tp) == 1) {
                checkConstraint(subs.getString(tp), constraint, tp, "function", callee)
            }
        }
        specializedFuncs.set(mangledName, "1")
        funcRetTypes.set(mangledName, resolvedRet)
        funcParamCount.set(mangledName, funcParamCount.getString(callee) ?? "0")

        // Save codegen state (same pattern as genArrowFunc)
        const savedFunc = currentFunc
        const savedReg = regCount
        const savedTerm = terminated
        const savedAliases = varAliases
        const savedIrOut = irOutFile
        const savedPtrVars = localPtrVars
        const savedFnVars = localFnVars
        const savedBlockDepth = rcBlockDepth
        const savedBlockStack = blockPtrVarStack
        const savedSubs = genericTypeSubs

        // Set up specialization context
        genericTypeSubs = subs
        specFuncName = mangledName
        if (irOutFile != "") { strOutFile = irOutFile }
        irOutFile = ""
        irBuf = ""

        // Generate the specialized function
        genFuncDecl(funcNodeId)

        // Buffer the generated IR
        genericSpecDefs = `${genericSpecDefs}${irBuf}`

        // Restore state
        irBuf = ""
        irOutFile = savedIrOut
        strOutFile = ""
        currentFunc = savedFunc
        regCount = savedReg
        terminated = savedTerm
        varAliases = savedAliases
        localPtrVars = savedPtrVars
        localFnVars = savedFnVars
        rcBlockDepth = savedBlockDepth
        blockPtrVarStack = savedBlockStack
        genericTypeSubs = savedSubs
        specFuncName = ""
    }

    // 5. Emit the call using mangled name
    const args = resolveCallArgs(callee, argList, resolvedRet == "double" ? 1 : 0)
    const llRetType = ssTypeToLLVM(resolvedRet)
    if (llRetType == "void") {
        emitIR(`  call void @${mangledName}(${args})`)
        return "0"
    }
    const r = nextReg()
    emitIR(`  ${r} = call ${llRetType} @${mangledName}(${args})`)
    return r
}

// ── Function call codegen ───────────────────────────────────────

function genCall(id: int): string {
    const callee = nGetS1(id)
    const argList = nGetList(id)

    // Generic function: monomorphize at call site
    if (genericFuncNodes.has(callee) == 1) {
        return genGenericCall(id, callee, argList)
    }

    const resolvedName = resolveOverload(callee, argList)

    if (callee == "println" || callee == "print") {
        return genPrintCall(callee, argList)
    }

    const effectiveName = resolvedName != callee ? resolvedName : callee
    const rtName = runtimeName(effectiveName)
    const args = resolveCallArgs(callee, argList, callReturnType(effectiveName) == "double" ? 1 : 0)
    const retType = callReturnType(effectiveName)
    const llRetType = ssTypeToLLVM(retType)

    // Indirect call: function pointer variable (supports closures via tag bit)
    if (getVarType(callee) == "fn" || getVarType(callee) == "i64") {
        const fpVal = nextReg()
        emitIR(`  ${fpVal} = load i64, ptr ${varRef(callee)}, align 8`)
        // Check tag bit 0: if set, this is a closure
        const tagBit = nextReg()
        emitIR(`  ${tagBit} = and i64 ${fpVal}, 1`)
        const isClosure = nextReg()
        emitIR(`  ${isClosure} = icmp eq i64 ${tagBit}, 1`)
        const lblClosure = nextLabel("closure.call")
        const lblDirect = nextLabel("direct.call")
        const lblDone = nextLabel("call.done")
        emitIR(`  br i1 ${isClosure}, label %${lblClosure}, label %${lblDirect}`)
        // Closure path: untag, load fn_ptr, call with self
        emitIR(`${lblClosure}:`)
        const untagged = nextReg()
        emitIR(`  ${untagged} = and i64 ${fpVal}, -2`)
        const closurePtr = nextReg()
        emitIR(`  ${closurePtr} = inttoptr i64 ${untagged} to ptr`)
        const fnField = nextReg()
        emitIR(`  ${fnField} = getelementptr ptr, ptr ${closurePtr}, i32 2`)
        const fnPtr = nextReg()
        emitIR(`  ${fnPtr} = load ptr, ptr ${fnField}, align 8`)
        const closureArgs = args != "" ? `ptr ${closurePtr}, ${args}` : `ptr ${closurePtr}`
        const r1 = nextReg()
        emitIR(`  ${r1} = call i64 ${fnPtr}(${closureArgs})`)
        emitIR(`  br label %${lblDone}`)
        // Direct path: raw function pointer call
        emitIR(`${lblDirect}:`)
        const fpPtr = nextReg()
        emitIR(`  ${fpPtr} = inttoptr i64 ${fpVal} to ptr`)
        const r2 = nextReg()
        emitIR(`  ${r2} = call i64 ${fpPtr}(${args})`)
        emitIR(`  br label %${lblDone}`)
        // Merge
        emitIR(`${lblDone}:`)
        const r = nextReg()
        emitIR(`  ${r} = phi i64 [${r1}, %${lblClosure}], [${r2}, %${lblDirect}]`)
        return r
    }

    if (llRetType == "void") {
        emitIR(`  call void @${rtName}(${args})`)
        return "0"
    }
    const r = nextReg(); emitIR(`  ${r} = call ${llRetType} @${rtName}(${args})`); return r
}

// ── Template literal codegen ────────────────────────────────────

function genTemplateLit(id: int): string {
    const fragList = nGetList(id)
    if (fragList == "") {
        return addStringConst("")
    }
    let result = ""
    let resultIsOwned = 0
    const parts = fragList.split(",")
    for (p in parts) {
        const fragId = parseInt(p)
        if (fragId > 0) {
            const fk = nGetKind(fragId)
            let fragStr = ""
            let fragOwned = 0
            if (fk == "TMPL_FRAG_LIT") {
                fragStr = addStringConst(nGetS1(fragId))
            } else if (fk == "TMPL_FRAG_EXPR") {
                fragStr = genExprAsString(nGetI1(fragId))
                fragOwned = lastExprStringOwned
            }
            if (result == "") {
                result = fragStr
                resultIsOwned = fragOwned
            } else {
                const old = result
                const r = nextReg()
                emitIR(`  ${r} = call ptr @ss_string_concat(ptr ${old}, ptr ${fragStr})`)
                // RC: release consumed left operand (concat intermediate or conversion temp)
                if (resultIsOwned == 1) {
                    emitIR(`  call void @ss_rc_release(ptr ${old})`)
                }
                // RC Phase 5: release consumed right operand (conversion temp)
                if (fragOwned == 1) {
                    emitIR(`  call void @ss_rc_release(ptr ${fragStr})`)
                }
                result = r
                resultIsOwned = 1
            }
        }
    }
    return result
}

// ── Array literal codegen ───────────────────────────────────────

function genArrayLit(id: int): string {
    const elemList = nGetList(id)

    // Check if any spread elements exist + detect ptr/scalar element mix
    let hasSpread = 0
    let hasPtrElem = 0
    let hasScalarElem = 0
    if (elemList != "") {
        const chkParts = elemList.split(",")
        for (cp in chkParts) {
            const cid = parseInt(cp)
            if (cid > 0) {
                if (nGetKind(cid) == "SPREAD_ELEM") { hasSpread = 1 }
                const eType = inferType(cid)
                const eLLType = ssTypeToLLVM(eType)
                if (eLLType == "ptr") { hasPtrElem = 1 } else { hasScalarElem = 1 }
            }
        }
    }

    // Choose array constructor: use scalar array for mixed types (tuple safety)
    let arrCtor = "@ss_newArray"
    if (hasPtrElem == 1 && hasScalarElem == 0) { arrCtor = "@ss_newArrayPtr" }

    // If spread exists, use push-based building
    if (hasSpread == 1) {
        const arrAlloca = nextReg()
        emitIR(`  ${arrAlloca} = alloca ptr, align 8`)
        const initArr = nextReg()
        emitIR(`  ${initArr} = call ptr ${arrCtor}(i32 0)`)
        emitIR(`  store ptr ${initArr}, ptr ${arrAlloca}, align 8`)
        if (elemList != "") {
            const parts = elemList.split(",")
            for (p in parts) {
                const elemId = parseInt(p)
                if (elemId > 0) {
                    if (nGetKind(elemId) == "SPREAD_ELEM") {
                        // Spread: concat arrays
                        const spreadArr = genExpr(nGetI1(elemId))
                        const curArr = nextReg()
                        emitIR(`  ${curArr} = load ptr, ptr ${arrAlloca}, align 8`)
                        const merged = nextReg()
                        emitIR(`  ${merged} = call ptr @ss_arrayConcat(ptr ${curArr}, ptr ${spreadArr})`)
                        emitIR(`  store ptr ${merged}, ptr ${arrAlloca}, align 8`)
                    } else {
                        // Normal element: push
                        const val = genExpr(elemId)
                        const vType = inferType(elemId)
                        let val64 = val
                        if (vType == "string") {
                            const cR = nextReg()
                            emitIR(`  ${cR} = ptrtoint ptr ${val} to i64`)
                            val64 = cR
                        } else {
                            const sR = nextReg()
                            emitIR(`  ${sR} = sext i32 ${val} to i64`)
                            val64 = sR
                        }
                        const curArr = nextReg()
                        emitIR(`  ${curArr} = load ptr, ptr ${arrAlloca}, align 8`)
                        const pushed = nextReg()
                        emitIR(`  ${pushed} = call ptr @ss_arrayPush(ptr ${curArr}, i64 ${val64})`)
                        emitIR(`  store ptr ${pushed}, ptr ${arrAlloca}, align 8`)
                    }
                }
            }
        }
        const finalArr = nextReg()
        emitIR(`  ${finalArr} = load ptr, ptr ${arrAlloca}, align 8`)
        return finalArr
    }

    // No spread: use fixed-size allocation
    let count = 0
    if (elemList != "") {
        const parts = elemList.split(",")
        for (p in parts) {
            count = count + 1
        }
    }
    const arrReg = nextReg()
    emitIR(`  ${arrReg} = call ptr ${arrCtor}(i32 ${count})`)

    if (elemList != "") {
        let idx = 0
        const parts = elemList.split(",")
        for (p in parts) {
            const elemId = parseInt(p)
            if (elemId > 0) {
                const val = genExpr(elemId)
                const vType = inferType(elemId)
                const llElemType = ssTypeToLLVM(vType)
                if (llElemType == "ptr") {
                    const castReg = nextReg()
                    emitIR(`  ${castReg} = ptrtoint ptr ${val} to i64`)
                    emitIR(`  call void @ss_arraySet(ptr ${arrReg}, i32 ${idx}, i64 ${castReg})`)
                } else if (llElemType == "i64") {
                    emitIR(`  call void @ss_arraySet(ptr ${arrReg}, i32 ${idx}, i64 ${val})`)
                } else {
                    const extReg = nextReg()
                    emitIR(`  ${extReg} = sext i32 ${val} to i64`)
                    emitIR(`  call void @ss_arraySet(ptr ${arrReg}, i32 ${idx}, i64 ${extReg})`)
                }
                idx = idx + 1
            }
        }
    }
    return arrReg
}
