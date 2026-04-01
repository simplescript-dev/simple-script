// gen_decls.ss — Declaration and function code generation
// Used by gen_stmts.ss via textual import.

import { genMemberAssign, genAssign } from "./gen_assigns"

// ── Function codegen ────────────────────────────────────────

// Emit alloca/store for function parameters.
// useVarAlias=1: allocVarName for SSA renaming (free functions, arrows)
// useVarAlias=0: raw param name (class methods, where %name is used directly)
function emitParamAllocas(paramList: string, useVarAlias: int) {
    if (paramList == "") { return }
    const parts = paramList.split(",")
    for (p in parts) {
        const pId = parseInt(p)
        if (pId <= 0) { continue }
        if (nGetKind(pId) != "PARAM") { continue }
        const pName = nGetS1(pId)
        let pType = nGetS2(pId)
        pType = resolveTypeParam(pType)
        const llType = ssTypeToLLVM(pType)
        let llName = pName
        if (useVarAlias == 1) { llName = allocVarName(pName) }
        emitIR(`  %${llName} = alloca ${llType}, align 8`)
        emitIR(`  store ${llType} %${pName}.arg, ptr %${llName}, align 8`)
        setVarType(pName, pType)
        if (classFields.has(pType) == 1 || ifaceMethodsCG.has(pType) == 1) {
            setObjClass(pName, pType)
        }
    }
}

function genFuncDeclStmt(id: int) {
    // Generic functions are emitted on-demand at call sites (monomorphization)
    if (nGetS3(id) != "") { return }
    const fname = nGetS1(id)
    const fSig = paramSig(nGetList(id))
    const genKey = fSig != "" ? `${fname}_${fSig}_generated` : `${fname}_generated`
    if (fname != "main" && funcRetTypes.has(genKey) == 1) { return }
    funcRetTypes.set(genKey, "1")
    genFuncDecl(id)
}

function isOverloaded(fname: string): int {
    if (overloadReady == 0) { return 0 }
    if (overloadCount.has(fname) == 0) { return 0 }
    return parseInt(overloadCount.getString(fname)) > 1 ? 1 : 0
}

// RC: check if expression produces an owned (freshly allocated) value
function isOwnedExpr(nodeId: int): int {
    const kind = nGetKind(nodeId)
    if (kind == "NEW_EXPR") { return 1 }
    if (kind == "CALL") { return 1 }
    if (kind == "METHOD_CALL") { return 0 }
    if (kind == "STRING_LIT") { return 1 }
    if (kind == "TEMPLATE_LIT") { return 1 }
    if (kind == "ARRAY_LIT") { return 1 }
    if (kind == "BINARY") {
        const lType = inferType(nGetI1(nodeId))
        if (lType == "string") { return 1 }
        return 0
    }
    return 0
}

function genFuncDecl(id: int) {
    // specFuncName overrides name during generic specialization
    let name = specFuncName != "" ? specFuncName : nGetS1(id)
    // Use mangled name if function is overloaded (skip for specializations)
    let llName = name
    if (specFuncName == "" && isOverloaded(name) == 1) {
        const fSig = paramSig(nGetList(id))
        if (fSig != "") { llName = `${name}_${fSig}` }
    }
    regCount = 0
    currentFunc = llName
    terminated = 0
    varAliases = Map()
    localPtrVars = ""
    localFnVars = ""
    rcBlockDepth = 0

    // For 'main', use C main signature
    if (name == "main") {
        emitIR("define i32 @main(i32 %0, ptr %1) {")
        emitIR("entry:")
        emitIR("  call void @ss_initArgs(i32 %0, ptr %1)")
        emitIR("  %_atexit = call i32 @atexit(ptr @ss_rc_atexit_cleanup)")
        emitIR("  %_seedtime = call i64 @time(ptr null)")
        emitIR("  %_seedtime32 = trunc i64 %_seedtime to i32")
        emitIR("  call void @srand(i32 %_seedtime32)")
        regCount = 3
        emitGlobalInits()
    } else {
        // Collect param types (MVP: all int for now)
        const paramList = nGetList(id)
        let paramStr = ""
        if (paramList != "") {
            const parts = paramList.split(",")
            let idx = 0
            for (p in parts) {
                const pId = parseInt(p)
                if (pId > 0) {
                    if (idx > 0) { paramStr = paramStr + ", " }
                    paramStr = `${paramStr}${ssTypeToLLVM(nGetS2(pId))} %${nGetS1(pId)}.arg`
                    idx = idx + 1
                }
            }
        }
        let retType = resolveTypeParam(nGetS2(id))
        if (retType == "") { retType = "void" }
        const llRetType = ssTypeToLLVM(retType)
        emitIR(`define ${llRetType} @${llName}(${paramStr}) {`)
        emitIR("entry:")
        emitParamAllocas(paramList, 1)
    }

    // PIR: analyze function for class RC operations before codegen
    pirActive = 0
    const bodyId = nGetI1(id)
    if (name != "main") {
        pirAnalyzeFunc(bodyId, nGetList(id), llName)
    }

    // Generate body
    genBlock(bodyId)

    // Default return (only if not already terminated)
    if (terminated == 1) {
        emitIR("}")
        emitIR("")
        pirActive = 0
        return
    }
    pirEmitReturnCleanup()
    emitReleaseFnLocals()
    emitReleaseLocals()
    if (name == "main") {
        emitIR("  ret i32 0")
    } else {
        const retType = resolveTypeParam(nGetS2(id))
        if (retType == "string") {
            const nullStr = addStringConst("")
            emitIR(`  ret ptr ${nullStr}`)
        } else if (retType == "double") {
            emitIR("  ret double 0.0")
        } else if (retType == "void" || retType == "") {
            emitIR("  ret void")
        } else if (ssTypeToLLVM(retType) == "ptr") {
            emitIR("  ret ptr null")
        } else {
            emitIR("  ret i32 0")
        }
    }
    emitIR("}")
    emitIR("")
    pirActive = 0
    flushArrowDefs()
    flushGenericSpecDefs()
}

function flushGenericSpecDefs() {
    if (genericSpecDefs == "") { return }
    emitIR(genericSpecDefs)
    genericSpecDefs = ""
}

// ── Global variables ────────────────────────────────────────

// Track global vars needing runtime init (new Map(), function calls, etc.)
let globalInitIds = ""

function genGlobalVar(id: int) {
    const name = nGetS1(id)
    if (globalAliases.has(name) == 1) { return }
    const initId = nGetI1(id)
    const ik = nGetKind(initId)
    let gType = "ptr"
    if (ik == "INT_LIT") {
        emitIR(`@${name} = global i32 ${nGetS1(initId)}, align 4`)
        gType = "int"
    } else if (ik == "DOUBLE_LIT") {
        emitIR(`@${name} = global double ${nGetS1(initId)}, align 8`)
        gType = "double"
    } else if (ik == "STRING_LIT") {
        emitIR(`@${name} = global ptr ${addStringConst(nGetS1(initId))}, align 8`)
        gType = "string"
    } else if (ik == "TRUE_LIT") {
        emitIR(`@${name} = global i32 1, align 4`)
        gType = "int"
    } else if (ik == "FALSE_LIT") {
        emitIR(`@${name} = global i32 0, align 4`)
        gType = "int"
    } else {
        // Non-literal init: declare null, queue runtime init
        emitIR(`@${name} = global ptr null, align 8`)
        if (globalInitIds == "") { globalInitIds = `${id}` }
        else { globalInitIds = `${globalInitIds},${id}` }
        // Infer actual type for class tracking
        const realType = inferType(initId)
        if (realType != "" && realType != "ptr" && realType != "int") { gType = realType }
    }
    setVarType(name, gType)
    globalAliases.set(name, `@${name}`)
}

// Called at the start of main() to init global vars with runtime expressions
function emitGlobalInits() {
    if (globalInitIds != "") {
        const parts = globalInitIds.split(",")
        for (p in parts) {
            const gid = parseInt(p)
            if (gid > 0) {
                const gname = nGetS1(gid)
                const initId = nGetI1(gid)
                const val = genExpr(initId)
                emitIR(`  store ptr ${val}, ptr @${gname}, align 8`)
                // Infer class type for global var (store in global scope, not main)
                const gInitType = inferType(initId)
                if (gInitType != "" && classFields.has(gInitType) == 1) {
                    const savedFunc = currentFunc
                    currentFunc = ""
                    setObjClass(gname, gInitType)
                    currentFunc = savedFunc
                }
            }
        }
    }
    // Auto-register annotated routes (@GetMapping etc.)
    if (annotatedRoutes != "") {
        emitAnnotatedRoutes()
    }
}

function emitAnnotatedRoutes() {
    // For each @RestController class, create a singleton wrapper function per route
    // that passes null as this (controller methods shouldn't use this for state)
    let remaining = annotatedRoutes
    let wrapperIdx = 0
    while (remaining != "") {
        let entry = remaining
        const nlIdx = remaining.indexOf("\n")
        if (nlIdx >= 0) {
            entry = remaining.substring(0, nlIdx)
            remaining = remaining.substring(nlIdx + 1, remaining.length() - nlIdx - 1)
        } else {
            remaining = ""
        }
        const p1 = entry.indexOf(":")
        if (p1 < 0) { continue }
        const httpMethod = entry.substring(0, p1)
        const rest1 = entry.substring(p1 + 1, entry.length() - p1 - 1)
        const p2 = rest1.indexOf(":")
        const path = rest1.substring(0, p2)
        const rest2 = rest1.substring(p2 + 1, rest1.length() - p2 - 1)
        const p3 = rest2.indexOf(":")
        const className = rest2.substring(0, p3)
        const methodName = rest2.substring(p3 + 1, rest2.length() - p3 - 1)
        // Generate registerRoute call with function pointer
        const pathStr = addStringConst(path)
        const methodStr = addStringConst(httpMethod)
        // Create singleton instance stored in global
        const globalName = `@__ctrl_${className}`
        // Emit global declaration (only once per class)
        if (funcRetTypes.has(`__ctrl_${className}_init`) == 0) {
            funcRetTypes.set(`__ctrl_${className}_init`, "1")
            emitIR(`  ; init controller ${className}`)
        }
        const instR = nextReg()
        emitIR(`  ${instR} = call ptr @${className}_new()`)
        // Create wrapper function that loads instance from register
        // Use a global to pass the instance
        const wrapName = `__route_${wrapperIdx}`
        wrapperIdx = wrapperIdx + 1
        // Store instance in a global variable
        const gName = `__ctrl_inst_${wrapperIdx}`
        arrowDefs = `${arrowDefs}@${gName} = internal global ptr null\n`
        emitIR(`  store ptr ${instR}, ptr @${gName}`)
        arrowDefs = `${arrowDefs}define ptr @${wrapName}(ptr %req, ptr %resp) {\nentry:\n  %inst = load ptr, ptr @${gName}\n  %r = call ptr @${className}_${methodName}(ptr %inst, ptr %req, ptr %resp)\n  ret ptr %r\n}\n\n`
        const fnPtr = nextReg()
        emitIR(`  ${fnPtr} = ptrtoint ptr @${wrapName} to i64`)
        emitIR(`  call void @registerRoute(ptr ${methodStr}, ptr ${pathStr}, i64 ${fnPtr})`)
    }
}

// ── Variable declarations ───────────────────────────────────

function genDestructureArray(id: int) {
    const names = nGetS1(id)
    const initId = nGetI1(id)
    const arrVal = genExpr(initId)
    // Detect tuple type from init expression
    let tupleType = ""
    const daInitType = inferType(initId)
    if (isTupleType(daInitType) == 1) { tupleType = daInitType }
    let itemType = inferArrayElemType(initId)
    if (itemType == "" && tupleType == "") { itemType = "i64" }
    const parts = names.split(",")
    let idx = 0
    for (n in parts) {
        // Rest element: const [a, ...rest] = arr
        if (n.startsWith("...") == 1) {
            const restName = n.substring(3, n.length() - 3)
            const llName = allocVarName(restName)
            emitIR(`  %${llName} = alloca ptr, align 8`)
            const sliceR = nextReg()
            emitIR(`  ${sliceR} = call ptr @ss_arraySlice(ptr ${arrVal}, i32 ${idx}, i32 2147483647)`)
            emitIR(`  store ptr ${sliceR}, ptr %${llName}, align 8`)
            const arrType = itemType != "i64" ? `Array<${itemType}>` : "Array<int>"
            setVarType(restName, arrType)
            if (currentFunc != "") { trackPtrVar(llName) }
            break
        }
        // Per-element type for tuples, uniform type for arrays
        let elemType = itemType
        if (tupleType != "") {
            elemType = tupleElemTypeAtIndex(tupleType, idx)
            if (elemType == "") { elemType = "i64" }
        }
        const llType = ssTypeToLLVM(elemType)
        const llName = allocVarName(n)
        emitIR(`  %${llName} = alloca ${llType}, align 8`)
        const elemR = nextReg()
        emitIR(`  ${elemR} = call i64 @ss_arrayGet(ptr ${arrVal}, i32 ${idx})`)
        // Convert i64 to target type
        if (elemType == "string") {
            const elemPtr = nextReg()
            emitIR(`  ${elemPtr} = inttoptr i64 ${elemR} to ptr`)
            emitIR(`  store ptr ${elemPtr}, ptr %${llName}, align 8`)
            if (currentFunc != "") {
                trackPtrVar(llName)
                emitIR(`  call void @ss_rc_retain(ptr ${elemPtr})`)
            }
        } else if (elemType == "int") {
            const elemI32 = nextReg()
            emitIR(`  ${elemI32} = trunc i64 ${elemR} to i32`)
            emitIR(`  store i32 ${elemI32}, ptr %${llName}, align 8`)
        } else if (elemType == "double") {
            const elemDb = nextReg()
            emitIR(`  ${elemDb} = bitcast i64 ${elemR} to double`)
            emitIR(`  store double ${elemDb}, ptr %${llName}, align 8`)
        } else {
            emitIR(`  store i64 ${elemR}, ptr %${llName}, align 8`)
        }
        setVarType(n, elemType)
        idx = idx + 1
    }
}

function genDestructureObject(id: int) {
    const names = nGetS1(id)
    const initId = nGetI1(id)
    const objVal = genExpr(initId)
    // Resolve class name
    let className = resolveObjClass(initId)
    if (className == "") {
        const it = inferType(initId)
        if (classFields.has(it) == 1) { className = it }
    }
    if (className == "") {
        println("codegen error: cannot resolve class for object destructuring")
        exit(1)
    }
    const parts = names.split(",")
    for (n in parts) {
        let fieldName = n
        let varName = n
        const colonIdx = n.indexOf(":")
        if (colonIdx >= 0) {
            fieldName = n.substring(0, colonIdx)
            varName = n.substring(colonIdx + 1, n.length() - colonIdx - 1)
        }
        const fieldVal = emitFieldLoad(className, objVal, fieldName)
        const fType = classFieldTypes.getString(`${className}.${fieldName}`)
        const llType = ssTypeToLLVM(fType)
        const llName = allocVarName(varName)
        emitIR(`  %${llName} = alloca ${llType}, align 8`)
        emitIR(`  store ${llType} ${fieldVal}, ptr %${llName}, align 8`)
        setVarType(varName, fType)
        // Track class for method dispatch
        if (classFields.has(fType) == 1 || ifaceMethodsCG.has(fType) == 1) {
            setObjClass(varName, fType)
        }
        // RC: retain reference-typed fields
        if (llType == "ptr" && currentFunc != "") {
            if (pirActive == 1 && pirIsClass(fType) == 1) {
                emitRetainForType(fieldVal, fType)
                pirMarkManaged(llName)
            } else {
                trackPtrVar(llName)
                emitIR(`  call void @ss_rc_retain(ptr ${fieldVal})`)
            }
        }
    }
}

function genVarDecl(id: int) {
    const name = nGetS1(id)
    const initId = nGetI1(id)
    const typeAnn = nGetS3(id)

    // Infer type from init expression
    const initType = inferType(initId)
    const llType = ssTypeToLLVM(initType)

    // Global vars: just store (alloca already done by genGlobalVar)
    if (currentFunc == "" && globalAliases.has(name) == 1) {
        const val = genExpr(initId)
        const gn = globalAliases.getString(name)
        emitIR(`  store ${llType} ${val}, ptr ${gn}, align 8`)
        return
    }
    const llName = allocVarName(name)
    emitIR(`  %${llName} = alloca ${llType}, align 8`)
    setVarType(name, initType)

    // Track generic type annotation (e.g., Array<string>)
    if (typeAnn.contains("<") == 1) {
        setVarType(name, typeAnn)
    }
    // Infer array element type from init expression (split, etc.)
    if (typeAnn == "" && initType == "ptr") {
        const aeType = inferArrayElemType(initId)
        if (aeType != "") {
            setVarType(name, `Array<${aeType}>`)
        }
    }

    // Track object class for method dispatch (redundant with varTypes but kept for compatibility)
    if (nGetKind(initId) == "NEW_EXPR") {
        const newClassName = nGetS1(initId)
        if (genericClassNodes.has(newClassName) == 1) {
            setObjClass(name, inferGenericClassName(newClassName, nGetList(initId), nGetS2(initId)))
        } else {
            setObjClass(name, newClassName)
        }
    }
    if (nGetKind(initId) == "CALL") {
        const callRet = funcRetTypes.getString(nGetS1(initId)) ?? ""
        if (callRet != "" && classFields.has(callRet) == 1) {
            setObjClass(name, callRet)
        }
    }
    // Infer class from method call chain (e.g., createFoo().setBar())
    if (nGetKind(initId) == "METHOD_CALL") {
        const mRetType = inferType(initId)
        if (mRetType != "" && classFields.has(mRetType) == 1) {
            setObjClass(name, mRetType)
        }
    }
    // Propagate class from IDENT (let b = a where a is a class instance)
    if (nGetKind(initId) == "IDENT") {
        const srcClass = getObjClass(nGetS1(initId))
        if (srcClass != "") {
            setObjClass(name, srcClass)
        } else {
            // Also check varTypes for class type
            const srcType = getVarType(nGetS1(initId))
            if (srcType != "" && classFields.has(srcType) == 1) {
                setObjClass(name, srcType)
            }
        }
    }
    // Interface type annotation: override objClass so dispatch uses interface
    if (typeAnn != "" && ifaceMethodsCG.has(typeAnn) == 1) {
        setVarType(name, typeAnn)
        setObjClass(name, typeAnn)
    }

    // PIR REUSE: set pending reuse context for genNewExpr
    if (pirActive == 1 && nGetKind(initId) == "NEW_EXPR" && pirIsReuseAlloc(name) == 1) {
        const rInfo = pirGetReuseInfo(name)
        const reuseReg = pirGetReuseReg(name)
        if (rInfo != "" && reuseReg != "") {
            pirPendingReuseReg = reuseReg
            pirPendingReuseClass = pirParseEntryType(rInfo)
        }
    }

    let val = genExpr(initId)
    const valLLType = ssTypeToLLVM(inferType(initId))
    if (valLLType == "i64" && llType == "i32") {
        const trR = nextReg()
        emitIR(`  ${trR} = trunc i64 ${val} to i32`)
        val = trR
    }
    if (valLLType == "i64" && llType == "ptr") {
        const cvR = nextReg()
        emitIR(`  ${cvR} = inttoptr i64 ${val} to ptr`)
        val = cvR
    }
    emitIR(`  store ${llType} ${val}, ptr %${llName}, align 8`)
    // RC: track local ptr vars for release
    if (llType == "ptr" && currentFunc != "") {
        // PIR: user class instances use new RC system + PIR scheduling
        if (pirActive == 1 && pirIsClass(initType) == 1) {
            if (isOwnedExpr(initId) == 0 && pirIsMoveStmt(id) == 0) {
                emitRetainForType(val, initType)
            }
            pirMarkManaged(llName)
        } else {
            trackPtrVar(llName)
            if (isOwnedExpr(initId) == 0) {
                emitIR(`  call void @ss_rc_retain(ptr ${val})`)
            }
        }
    }
    // Track fn-typed locals for closure release at function exit
    // Only function-scope (rcBlockDepth==0); block-scope closures freed by scope rules
    if (initType == "fn" && currentFunc != "" && rcBlockDepth == 0) {
        trackFnVar(llName)
    }
    // Mark Map as ptr-value if type annotation indicates it (val_type=1 at offset 516)
    let isMapInit = 0
    if (nGetKind(initId) == "NEW_EXPR" && nGetS1(initId) == "Map") { isMapInit = 1 }
    if (nGetKind(initId) == "CALL" && nGetS1(initId) == "Map") { isMapInit = 1 }
    if (isMapInit == 1) {
        const mVarType = getVarType(name)
        if (mapValueIsPtr(mVarType) == 1) {
            const vtpGep = nextReg()
            emitIR(`  ${vtpGep} = getelementptr i8, ptr ${val}, i64 516`)
            emitIR(`  store i32 1, ptr ${vtpGep}`)
        }
    }
}

// ── Return statement ────────────────────────────────────────

function genReturn(id: int) {
    const valId = nGetI1(id)
    if (valId <= 0) {
        pirEmitReturnCleanup()
        emitReleaseAllBlockVars()
        emitReleaseFnLocals()
        emitReleaseLocals()
        if (currentFunc == "main") {
            emitIR("  ret i32 0")
        } else {
            emitIR("  ret void")
        }
    } else {
        let val = genExpr(valId)
        const vType = inferType(valId)
        const retLLType = ssTypeToLLVM(vType)
        // Get declared return type
        let declRet = "i32"
        if (funcRetTypes.has(currentFunc) == 1) {
            declRet = ssTypeToLLVM(funcRetTypes.getString(currentFunc))
        }
        if (currentFunc == "main") { declRet = "i32" }
        // Convert type if needed
        if (retLLType == "i64" && declRet == "i32") {
            const trR = nextReg(); emitIR(`  ${trR} = trunc i64 ${val} to i32`)
            val = trR
        } else if (retLLType == "i64" && declRet == "ptr") {
            const cvR = nextReg(); emitIR(`  ${cvR} = inttoptr i64 ${val} to ptr`)
            val = cvR
        } else if (retLLType == "double" && declRet == "i32") {
            const fpR = nextReg(); emitIR(`  ${fpR} = fptosi double ${val} to i32`)
            val = fpR
        } else if (retLLType == "i32" && declRet == "double") {
            const siR = nextReg(); emitIR(`  ${siR} = sitofp i32 ${val} to double`)
            val = siR
        }
        // RC: retain borrowed ptr before releasing locals
        if (declRet == "ptr" && isOwnedExpr(valId) == 0) {
            emitRetainForType(val, vType)
        }
        pirEmitReturnCleanup()
        emitReleaseAllBlockVars()
        emitReleaseFnLocals()
        emitReleaseLocals()
        emitIR(`  ret ${declRet} ${val}`)
    }
    terminated = 1
}

// ── Assignments ── (see gen_assigns.ss)
