// Generic class monomorphization codegen (extracted from gen_class.ss)

// ── Parent type parsing ───────────────────────────────────────

// Split "Box<int>" into base name and type args.
// Sets parentBaseName and parentTypeArgs module globals.
let parentBaseName = ""
let parentTypeArgs = ""
function splitParentType(parentType: string) {
    const ltIdx = parentType.indexOf("<")
    if (ltIdx < 0) {
        parentBaseName = parentType
        parentTypeArgs = ""
        return
    }
    parentBaseName = parentType.substring(0, ltIdx)
    // Find matching > by counting depth
    let depth = 0
    let endIdx = parentType.length() - 1
    let i = ltIdx
    while (i < parentType.length()) {
        const ch = parentType.substring(i, 1)
        if (ch == "<") { depth = depth + 1 }
        if (ch == ">") {
            depth = depth - 1
            if (depth == 0) { endIdx = i; break }
        }
        i = i + 1
    }
    parentTypeArgs = parentType.substring(ltIdx + 1, endIdx - ltIdx - 1)
}

// ── Deferred struct emission ─────────────────────────────────

// Emit struct type definitions for classes deferred during registration phase.
// Called after buildClassVtables() so vtable info is available.
function emitDeferredStructDefs() {
    if (deferredStructDefs == "") { return }
    const parts = deferredStructDefs.split(",")
    for (mn in parts) {
        if (mn == "") { continue }
        const hasVt = classNeedsVtable.has(mn) == 1 ? 1 : 0
        const flds = classFields.getString(mn)
        let fieldTypeStr = "i32, ptr"
        if (hasVt == 1) { fieldTypeStr = `${fieldTypeStr}, ptr` }
        if (flds != "") {
            const fParts = flds.split(",")
            for (fp in fParts) {
                const ft = classFieldTypes.getString(`${mn}.${fp}`)
                fieldTypeStr = `${fieldTypeStr}, ${ssTypeToLLVM(ft)}`
            }
        }
        const structDef = `%${mn} = type { ${fieldTypeStr} }\n`
        const strTarget = strOutFile ?? irOutFile
        if (strTarget != "") {
            appendFile(`${strTarget}.str`, structDef)
        } else {
            strConsts = `${strConsts}${structDef}`
        }
    }
    deferredStructDefs = ""
}

// ── Generic class monomorphization ──────────────────────────

// Pre-register a specialized class in all Maps with concrete types
function preRegisterSpecializedClass(classNodeId: int, mangledName: string, subs: string) {
    // Guard: skip if already registered (may be called from inferGenericClassName and genGenericNewExpr)
    if (classFields.has(mangledName) == 1) { return }
    const paramList = classFieldList(classNodeId)
    let fieldNames = ""
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                const fName = paramName(pId)
                let fType = paramType(pId)
                if (subs.has(fType) == 1) { fType = subs.getString(fType) }
                fieldNames = listAppendStr(fieldNames, fName)
                classFieldTypes.set(`${mangledName}.${fName}`, stripNullableCG(fType))
                if (nGetS3(pId) == "const") {
                    classConstFields.set(`${mangledName}.${fName}`, "1")
                }
            }
        }
    }
    classFields.set(mangledName, fieldNames)
    funcRetTypes.set(`${mangledName}_deepClone`, mangledName)
    funcRetTypes.set(`${mangledName}_shallowClone`, mangledName)
    // Register methods with resolved return types
    const methodsBlockId = classMethodsBlock(classNodeId)
    let methodNames = ""
    if (methodsBlockId > 0) {
        const mList = nGetList(methodsBlockId)
        if (mList != "") {
            const mParts = mList.split(",")
            for (mp in mParts) {
                const mId = parseInt(mp)
                if (mId > 0 && nGetKind(mId) == "FUNC_DECL") {
                    const mName = funcName(mId)
                    methodNames = listAppendStr(methodNames, mName)
                    let mRet = stripNullableCG(funcRetType(mId))
                    if (mRet == "") { mRet = "void" }
                    if (subs.has(mRet) == 1) { mRet = subs.getString(mRet) }
                    funcRetTypes.set(`${mangledName}_${mName}`, mRet)
                    // Register overloaded variant
                    const mSig = paramSig(funcParams(mId))
                    if (mSig != "") {
                        funcRetTypes.set(`${mangledName}_${mName}_${mSig}`, mRet)
                    }
                }
            }
        }
    }
    classMethods.set(mangledName, methodNames)
    classIds.set(mangledName, `${nextClassId}`)
    nextClassId = nextClassId + 1
    // Store info for deferred codegen
    specClassNodeId.set(mangledName, `${classNodeId}`)
    // Serialize type args from subs (ordered by classTypeParams)
    const origTP = classTypeParams(classNodeId)
    let typeArgsStr = ""
    if (origTP != "") {
        const tpParts = origTP.split(",")
        for (tp in tpParts) {
            if (subs.has(tp) == 1) {
                typeArgsStr = listAppendStr(typeArgsStr, subs.getString(tp))
            }
        }
    }
    specClassTypeArgs.set(mangledName, typeArgsStr)
    // Handle inheritance for generic class with extends
    const rawParent = classParentName(classNodeId)
    if (rawParent != "") {
        splitParentType(rawParent)
        let resolvedParent = parentBaseName
        const pTArgs = parentTypeArgs
        if (pTArgs != "" && genericClassNodes.has(resolvedParent) == 1) {
            // Parent is also generic: resolve type args through current subs
            const parentNodeId = parseInt(genericClassNodes.getString(resolvedParent))
            const parentTP = classTypeParams(parentNodeId)
            const tpList = parentTP.split(",")
            const tArgParts = pTArgs.split(",")
            const parentSubs = Map()
            let tpIdx = 0
            for (tp in tpList) {
                let ai = 0
                for (ta in tArgParts) {
                    if (ai == tpIdx) {
                        let resolvedTA = ta
                        if (subs.has(ta) == 1) { resolvedTA = subs.getString(ta) }
                        parentSubs.set(tp, resolvedTA)
                    }
                    ai = ai + 1
                }
                tpIdx = tpIdx + 1
            }
            let pMangledSig = ""
            for (tp in tpList) {
                if (parentSubs.has(tp) == 1) {
                    if (pMangledSig != "") { pMangledSig = `${pMangledSig}_` }
                    pMangledSig = `${pMangledSig}${typeSig(parentSubs.getString(tp))}`
                }
            }
            resolvedParent = `${resolvedParent}_${pMangledSig}`
            if (classFields.has(resolvedParent) == 0) {
                // Mark vtable before parent struct emission (child needs vtable hierarchy)
                classNeedsVtable.set(resolvedParent, "1")
                preRegisterSpecializedClass(parentNodeId, resolvedParent, parentSubs)
            }
        }
        classParents.set(mangledName, resolvedParent)
        // Inline inheritance resolution: prepend parent fields
        if (classFields.has(resolvedParent) == 1) {
            const pFields = classFields.getString(resolvedParent)
            if (pFields != "") {
                const curFields = classFields.getString(mangledName)
                if (curFields == "") {
                    classFields.set(mangledName, pFields)
                } else {
                    classFields.set(mangledName, `${pFields},${curFields}`)
                }
                const pfs = pFields.split(",")
                for (pf in pfs) {
                    if (classFieldTypes.has(`${resolvedParent}.${pf}`) == 1) {
                        classFieldTypes.set(`${mangledName}.${pf}`, classFieldTypes.getString(`${resolvedParent}.${pf}`))
                        if (classConstFields.has(`${resolvedParent}.${pf}`) == 1) {
                            classConstFields.set(`${mangledName}.${pf}`, "1")
                        }
                    }
                }
            }
        }
        // Inline vtable building for inheritance hierarchy
        classNeedsVtable.set(mangledName, "1")
        classNeedsVtable.set(resolvedParent, "1")
        buildVtableForClass(resolvedParent)
        buildVtableForClass(mangledName)
    }
    // Assign dtor tag if class has ptr fields (for codegen-time specializations)
    if (registrationPhase == 0) {
        const allFields = classFields.getString(mangledName)
        if (allFields != "") {
            let hasPtrField = 0
            const afParts = allFields.split(",")
            for (af in afParts) {
                if (af == "") { continue }
                const aft = classFieldTypes.has(`${mangledName}.${af}`) == 1 ? classFieldTypes.getString(`${mangledName}.${af}`) : ""
                if (aft != "" && ssTypeToLLVM(aft) == "ptr") { hasPtrField = 1 }
            }
            if (hasPtrField == 1 && classDtorTags.has(mangledName) == 0) {
                classDtorTags.set(mangledName, `${dtorNextTag}`)
                dtorNextTag = dtorNextTag + 1
            }
        }
    }
    // Emit or defer struct type definition
    const finalFields = classFields.getString(mangledName)
    if (registrationPhase == 1) {
        deferredStructDefs = listAppendStr(deferredStructDefs, mangledName)
    } else {
        const hasVt = classNeedsVtable.has(mangledName) == 1 ? 1 : 0
        let fieldTypeStr = "i32, ptr"
        if (hasVt == 1) { fieldTypeStr = `${fieldTypeStr}, ptr` }
        if (finalFields != "") {
            const fParts = finalFields.split(",")
            for (fp in fParts) {
                const ft = classFieldTypes.getString(`${mangledName}.${fp}`)
                fieldTypeStr = `${fieldTypeStr}, ${ssTypeToLLVM(ft)}`
            }
        }
        const structDef = `%${mangledName} = type { ${fieldTypeStr} }\n`
        const strTarget = strOutFile ?? irOutFile
        if (strTarget != "") {
            appendFile(`${strTarget}.str`, structDef)
        } else {
            strConsts = `${strConsts}${structDef}`
        }
    }
}

function genGenericNewExpr(id: int, className: string): string {
    const classNodeId = parseInt(genericClassNodes.getString(className))
    const typeParamStr = classTypeParams(classNodeId)
    const typeParamList = typeParamStr.split(",")
    const declFields = classFieldList(classNodeId)
    const argList = nGetList(id)

    // 1. Resolve type params (explicit or inferred from constructor arguments)
    const subs = Map()
    const explicitTypes = nGetS2(id)
    if (explicitTypes != "") {
        let tpIdx = 0
        for (tp in typeParamList) {
            subs.set(tp, listGet(explicitTypes, tpIdx))
            tpIdx = tpIdx + 1
        }
    } else if (declFields != "" && argList != "") {
        const fParts = declFields.split(",")
        const aParts = argList.split(",")
        let argIdx = 0
        for (fp in fParts) {
            const pId = parseInt(fp)
            if (pId <= 0 || nGetKind(pId) != "PARAM") { continue }
            const pType = nGetS2(pId)
            let isTP = 0
            for (tp in typeParamList) { if (tp == pType) { isTP = 1 } }
            if (isTP == 1 && subs.has(pType) == 0) {
                let ai = 0
                for (ap in aParts) {
                    if (ai == argIdx) { subs.set(pType, inferType(parseInt(ap))) }
                    ai = ai + 1
                }
            }
            argIdx = argIdx + 1
        }
    }

    // 2. Build mangled name
    let mangledSig = ""
    for (tp in typeParamList) {
        if (subs.has(tp) == 1) {
            if (mangledSig != "") { mangledSig = `${mangledSig}_` }
            mangledSig = `${mangledSig}${typeSig(subs.getString(tp))}`
        }
    }
    const mangledName = mangledSig != "" ? `${className}_${mangledSig}` : className

    // 3. Specialize if not already done
    if (specializedClasses.has(mangledName) == 0) {
        // Validate type constraints
        for (tp in typeParamList) {
            const constraint = classConstraint(className, tp)
            if (constraint != "" && subs.has(tp) == 1) {
                checkConstraint(subs.getString(tp), constraint, tp, "class", className)
            }
        }
        specializedClasses.set(mangledName, "1")
        preRegisterSpecializedClass(classNodeId, mangledName, subs)

        // State-save/buffer/flush (same pattern as genGenericCall)
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
        const savedClassName = currentClassName
        const savedSpecClass = specClassName

        genericTypeSubs = subs
        specClassName = mangledName
        if (irOutFile != "") { strOutFile = irOutFile }
        irOutFile = ""
        irBuf = ""

        genClassDecl(classNodeId)
        specClassGenerated.set(mangledName, "1")

        genericSpecDefs = `${genericSpecDefs}${irBuf}`

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
        currentClassName = savedClassName
        specClassName = savedSpecClass
    }

    // 4. Emit constructor call with mangled name
    let args = ""
    if (argList != "") {
        const parts = argList.split(",")
        let first = 1
        for (p in parts) {
            const argId = parseInt(p)
            if (argId > 0) {
                const val = genExpr(argId)
                const vType = inferType(argId)
                const llType = ssTypeToLLVM(vType)
                if (first == 1) { first = 0 } else { args = args + ", " }
                args = `${args}${llType} ${val}`
            }
        }
    }
    const r = nextReg()
    emitIR(`  ${r} = call ptr @${mangledName}_new(${args})`)
    return r
}

// Generate code for pre-registered specialized classes that haven't been codegen'd yet.
// Called after emitGlobalsAndCode to handle generic parents from extends (Case B).
function generateDeferredSpecializations() {
    const keyList = specClassNodeId.keys()
    for (mn in keyList) {
        if (mn == "") { continue }
        if (specClassGenerated.has(mn) == 1) { continue }
        specClassGenerated.set(mn, "1")
        const nodeId = parseInt(specClassNodeId.getString(mn))
        const typeArgsVal = specClassTypeArgs.getString(mn)
        // Rebuild subs Map from classTypeParams + stored type args
        const origTP = classTypeParams(nodeId)
        const subs = Map()
        if (origTP != "" && typeArgsVal != "") {
            const tpParts = origTP.split(",")
            const taParts = typeArgsVal.split(",")
            let idx = 0
            for (tp in tpParts) {
                let ai = 0
                for (ta in taParts) {
                    if (ai == idx) { subs.set(tp, ta) }
                    ai = ai + 1
                }
                idx = idx + 1
            }
        }
        // State-save/buffer/flush pattern (same as genGenericNewExpr)
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
        const savedClassName = currentClassName
        const savedSpecClass = specClassName

        genericTypeSubs = subs
        specClassName = mn
        if (irOutFile != "") { strOutFile = irOutFile }
        irOutFile = ""
        irBuf = ""

        genClassDecl(nodeId)

        genericSpecDefs = `${genericSpecDefs}${irBuf}`

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
        currentClassName = savedClassName
        specClassName = savedSpecClass

        flushArrowDefs()
        flushGenericSpecDefs()
    }
}
