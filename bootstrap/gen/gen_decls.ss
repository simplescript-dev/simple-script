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
        emitEntryAlloca(`%${llName}`, llType, 8)
        emitIR(`  store ${llType} %${pName}.arg, ptr %${llName}, align 8`)
        setVarType(pName, pType)
        const pTypeBase = stripNullableCG(pType)
        if (classFields.has(pTypeBase) == 1 || ifaceMethodsCG.has(pTypeBase) == 1) {
            setObjClass(pName, pTypeBase)
        }
    }
}

function genFuncDeclStmt(id: int) {
    if (comptimeMustBeKnown == 1) {
        if (handleMethodOfFuncDecl(id) == 1) { return }
        ctFuncNodes.set(nGetS1(id), `${id}`)
        return
    }
    // @methodOf-annotated functions are class-method injection targets,
    // not standalone runtime functions. Skip runtime emission.
    if (hasMethodOfAnnotation(id) == 1) { return }
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
        if (nGetS1(nodeId) == "NullCoalesce") { return 0 }
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
    regTable = []
    currentFunc = llName
    terminated = 0
    varAliases = Map()
    localPtrVars = ""
    localFnVars = ""
    rcBlockDepth = 0

    // SS-LIM-4: enter function-emit window (alloca → entry hoist buffer)
    startFuncEmit()

    // For 'main', use C main signature
    if (name == "main") {
        emitMainProlog()
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
        markEntryAllocaPoint()
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
    if (terminated == 0) {
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
    }
    emitIR("}")
    emitIR("")
    // SS-LIM-4: splice funcEntryAllocas + pop frame; caller routes funcIR.
    const funcIR = endFuncEmit()
    if (irOutFile != "") {
        appendFile(irOutFile, funcIR)
    } else {
        irBuf = `${irBuf}${funcIR}`
    }
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

function emitLiteralGlobalInit(globalRef: string, initId: int): string {
    const ik = nGetKind(initId)
    if (ik == "INT_LIT") {
        emitIR(`${globalRef} = global i32 ${nGetS1(initId)}, align 4`)
        return "int"
    }
    if (ik == "DOUBLE_LIT") {
        emitIR(`${globalRef} = global double ${nGetS1(initId)}, align 8`)
        return "double"
    }
    if (ik == "STRING_LIT") {
        emitIR(`${globalRef} = global ptr ${addStringConst(nGetS1(initId))}, align 8`)
        return "string"
    }
    if (ik == "TRUE_LIT") {
        emitIR(`${globalRef} = global i32 1, align 4`)
        return "int"
    }
    if (ik == "FALSE_LIT") {
        emitIR(`${globalRef} = global i32 0, align 4`)
        return "int"
    }
    if (ik == "UNARY" && nGetS1(initId) == "Neg") {
        const innerKind = nGetKind(nGetI1(initId))
        if (innerKind == "INT_LIT") {
            emitIR(`${globalRef} = global i32 -${nGetS1(nGetI1(initId))}, align 4`)
            return "int"
        }
        if (innerKind == "DOUBLE_LIT") {
            emitIR(`${globalRef} = global double -${nGetS1(nGetI1(initId))}, align 8`)
            return "double"
        }
    }
    return ""
}

function genGlobalVar(id: int) {
    const name = nGetS1(id)
    if (globalAliases.has(name) == 1) { return }
    const initId = nGetI1(id)
    let gType = "ptr"
    const litType = emitLiteralGlobalInit(`@${name}`, initId)
    if (litType != "") {
        gType = litType
        // I021-codegen-fix: CONST 字面值同步入 ctVars,防 comptime 引用 fallback 喷 `load`
        // 到顶层(D128 array/object/map 同模式扩五标量 lit kind + UNARY-Neg)
        if (nGetS2(id) == "CONST") {
            const lk = nGetKind(initId)
            if (lk == "STRING_LIT") {
                ctVars.set(`:${name}`, `${ctVal(interpNewString(nGetS1(initId)))}`)
            } else if (lk == "INT_LIT") {
                ctVars.set(`:${name}`, `${ctVal(interpNewInt(parseInt(nGetS1(initId))))}`)
            } else if (lk == "DOUBLE_LIT") {
                ctVars.set(`:${name}`, `${ctVal(interpNewDouble(parseDouble(nGetS1(initId))))}`)
            } else if (lk == "TRUE_LIT") {
                ctVars.set(`:${name}`, `${ctVal(interpNewBool(1))}`)
            } else if (lk == "FALSE_LIT") {
                ctVars.set(`:${name}`, `${ctVal(interpNewBool(0))}`)
            } else if (lk == "UNARY" && nGetS1(initId) == "Neg") {
                const innerId = nGetI1(initId)
                const innerKind = nGetKind(innerId)
                if (innerKind == "INT_LIT") {
                    ctVars.set(`:${name}`, `${ctVal(interpNewInt(0 - parseInt(nGetS1(innerId))))}`)
                } else if (innerKind == "DOUBLE_LIT") {
                    ctVars.set(`:${name}`, `${ctVal(interpNewDouble(0.0 - parseDouble(nGetS1(innerId))))}`)
                }
            }
        }
    } else if (nGetKind(initId) == "COMPTIME_EXPR") {
        const ceType = inferType(initId)
        const ceLit = comptimeExprLiteral.getString(`${initId}`)
        if (ceType == "int") {
            emitIR(`@${name} = global i32 ${ceLit}, align 4`)
            gType = "int"
        } else if (ceType == "double") {
            emitIR(`@${name} = global double ${ceLit}, align 8`)
            gType = "double"
        } else if (ceType == "string") {
            emitIR(`@${name} = global ptr ${ceLit}, align 8`)
            gType = "string"
        } else if (ceType == "type") {
            // D112: TypeValue 不落 runtime,alias 并入 ctVars(全局 scope key `:${name}`)
            ctVars.set(`:${name}`, `${ctVal(interpNewType(ceLit))}`)
            return
        } else if ((ceType == "array" || ceType == "object" || ceType == "map") && nGetS2(id) == "CONST" && parseInt(ceLit) > 0) {
            // D128: 顶级 const Array/Object/Map → ctVars `:${name}` 全局 scope(D098 §D112 同模式扩三 kind);ceTv == 0 失败回落 else 通用 runtime alloca 路径
            ctVars.set(`:${name}`, `${ctVal(parseInt(ceLit))}`)
            return
        } else {
            emitIR(`@${name} = global ptr null, align 8`)
            if (globalInitIds == "") { globalInitIds = `${id}` }
            else { globalInitIds = `${globalInitIds},${id}` }
        }
    } else {
        // Non-literal init: declare null/zero, queue runtime init
        const annotation = nGetS3(id)
        const realType = inferType(initId)
        if (isFnType(annotation) == 1 || isFnType(realType) == 1) {
            emitIR(`@${name} = global i64 0, align 8`)
            gType = "fn"
        } else {
            emitIR(`@${name} = global ptr null, align 8`)
        }
        if (globalInitIds == "") { globalInitIds = `${id}` }
        else { globalInitIds = `${globalInitIds},${id}` }
        if (gType != "fn") {
            if (annotation != "") {
                gType = annotation
            } else {
                if (realType != "" && realType != "ptr" && realType != "int") { gType = realType }
            }
        }
    }
    setVarType(name, gType)
    globalAliases.set(name, `@${name}`)
}

function emitGlobalVars(stmtList: string) {
    const parts = stmtList.split(",")
    for (p in parts) {
        const sid = parseInt(p)
        if (sid > 0 && nGetKind(sid) == "VAR_DECL") { genGlobalVar(sid) }
    }
}

function emitMainProlog() {
    emitIR("define i32 @main(i32 %0, ptr %1) {")
    emitIR("entry:")
    markEntryAllocaPoint()
    emitIR("  call void @ss_initArgs(i32 %0, ptr %1)")
    emitIR("  %_atexit = call i32 @atexit(ptr @ss_rc_atexit_cleanup)")
    emitIR("  %_atexit_test = call i32 @atexit(ptr @ss_test_summary)")
    emitIR("  %_seedtime = call i64 @time(ptr null)")
    emitIR("  %_seedtime32 = trunc i64 %_seedtime to i32")
    emitIR("  call void @srand(i32 %_seedtime32)")
    regCount = 3
    emitGlobalInits()
    emitStaticFieldInits()
}

function emitGlobalInits() {
    if (globalInitIds != "") {
        const parts = globalInitIds.split(",")
        for (p in parts) {
            const gid = parseInt(p)
            if (gid > 0) {
                const gname = nGetS1(gid)
                const initId = nGetI1(gid)
                const val = genExpr(initId)
                const gVarType = getVarType(gname)
                if (isFnType(gVarType) == 1) {
                    emitIR(`  store i64 ${val}, ptr @${gname}, align 8`)
                } else {
                    emitIR(`  store ptr ${val}, ptr @${gname}, align 8`)
                }
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
    // Annotation processors: DI bean init, route registration, etc.
    emitAnnotationInits()
}

// ── Variable declarations ───────────────────────────────────

function genDestructureArray(id: int) {
    const names = nGetS1(id)
    const initId = nGetI1(id)
    if (comptimeMustBeKnown == 1) {
        const ctArrV = genVal(initId)
        if (isCt(ctArrV) != 1) { return }
        const arrPayload = payload(ctArrV)
        if (interpType(arrPayload) != "array") { return }
        const arrLen = interpArrayLen(arrPayload)
        let ctIdx = 0
        for (cn in names.split(",")) {
            if (cn.startsWith("...") == 1) {
                const restName = cn.substring(3, cn.length() - 3)
                const restArr = interpNewArray("")
                while (ctIdx < arrLen) {
                    interpArrayPush(restArr, interpArrayGet(arrPayload, ctIdx))
                    ctIdx = ctIdx + 1
                }
                ctVars.set(`${currentFunc}:${restName}`, `${ctVal(restArr)}`)
                break
            }
            const ctElemValId = ctIdx < arrLen ? interpArrayGet(arrPayload, ctIdx) : interpNewNull()
            ctVars.set(`${currentFunc}:${cn}`, `${ctVal(ctElemValId)}`)
            ctIdx = ctIdx + 1
        }
        return
    }
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
            emitEntryAlloca(`%${llName}`, "ptr", 8)
            const sliceR = nextReg()
            emitIR(`  ${sliceR} = call ptr @ss_arraySlice(ptr ${arrVal}, i32 ${idx}, i32 2147483647)`)
            emitIR(`  store ptr ${sliceR}, ptr %${llName}, align 8`)
            const arrType = itemType != "i64" ? `Array<${itemType}>` : "Array<int>"
            setVarType(restName, arrType)
            if (currentFunc != "") { trackPtrVar(llName, arrType) }
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
        emitEntryAlloca(`%${llName}`, llType, 8)
        const elemR = nextReg()
        emitIR(`  ${elemR} = call i64 @ss_arrayGet(ptr ${arrVal}, i32 ${idx})`)
        // Convert i64 to target type
        if (elemType == "string") {
            const elemPtr = nextReg()
            emitIR(`  ${elemPtr} = inttoptr i64 ${elemR} to ptr`)
            emitIR(`  store ptr ${elemPtr}, ptr %${llName}, align 8`)
            if (currentFunc != "") {
                trackPtrVar(llName, "string")
                emitRetainForType(elemPtr, "string")
            }
        } else if (elemType == "int") {
            const elemI32 = nextReg()
            emitIR(`  ${elemI32} = trunc i64 ${elemR} to i32`)
            emitIR(`  store i32 ${elemI32}, ptr %${llName}, align 8`)
        } else if (elemType == "double") {
            const elemDb = nextReg()
            emitIR(`  ${elemDb} = bitcast i64 ${elemR} to double`)
            emitIR(`  store double ${elemDb}, ptr %${llName}, align 8`)
        } else if (llType == "ptr") {
            const elemPtr = nextReg()
            emitIR(`  ${elemPtr} = inttoptr i64 ${elemR} to ptr`)
            emitIR(`  store ptr ${elemPtr}, ptr %${llName}, align 8`)
            if (currentFunc != "") {
                trackPtrVar(llName, elemType)
                emitRetainForType(elemPtr, elemType)
            }
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
    if (comptimeMustBeKnown == 1) {
        const ctObjV = genVal(initId)
        if (isCt(ctObjV) != 1) { return }
        const ctObjPayload = payload(ctObjV)
        if (interpType(ctObjPayload) != "object") { return }
        for (cn in names.split(",")) {
            let ctFieldName = cn
            let ctVarName = cn
            const ctColonIdx = cn.indexOf(":")
            if (ctColonIdx >= 0) {
                ctFieldName = cn.substring(0, ctColonIdx)
                ctVarName = cn.substring(ctColonIdx + 1, cn.length() - ctColonIdx - 1)
            }
            const ctFieldValId = interpGetField(ctObjPayload, ctFieldName)
            ctVars.set(`${currentFunc}:${ctVarName}`, `${ctVal(ctFieldValId)}`)
        }
        return
    }
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
        emitEntryAlloca(`%${llName}`, llType, 8)
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
                trackPtrVar(llName, fType)
                emitRetainForType(fieldVal, fType)
            }
        }
    }
}

function genVarDecl(id: int) {
    const name = nGetS1(id)
    const initId = nGetI1(id)
    const typeAnn = nGetS3(id)

    // D084: Rewrite OBJ_LITERAL → NEW_EXPR (also needed in codegen for arrow bodies skipped by checker)
    if (initId > 0 && nGetKind(initId) == "OBJ_LITERAL" && typeAnn != "") {
        nKind.set(initId + "", "NEW_EXPR")
        nSetS1(initId, typeAnn)
    }

    // Comptime: evaluate and store in ctVars, no IR emission
    if (comptimeMustBeKnown == 1) {
        const ctInit = genVal(initId)
        if (isCt(ctInit) == 1) {
            ctVars.set(`${currentFunc}:${name}`, `${ctInit}`)
        }
        return
    }

    // Infer type from init expression
    const initType = inferType(initId)

    // D112: COMPTIME_EXPR 返回 TypeValue,alias 并入 ctVars(函数内 scope `${currentFunc}:${name}`)
    if (initId > 0 && nGetKind(initId) == "COMPTIME_EXPR" && initType == "type") {
        const ceLit = comptimeExprLiteral.getString(`${initId}`)
        ctVars.set(`${currentFunc}:${name}`, `${ctVal(interpNewType(ceLit))}`)
        return
    }
    // I014 §路径 A — COMPTIME_EXPR 返 Array/Object/Map 时 CONST 绑定走 ctVars,跳过 runtime alloca。
    // 消费侧(for-in unroll / evalMemberAccess)查 ctVars 得 ctVal,for-in 走 D120 §A.4 #3 ct-array
    // unroll,body 里 `r.invoke()` 触发 method_call.ss static dispatch emit。runtime alloca 的 i32 0
    // fallback 会和 `load ptr` 撞类型错;CONST 强制条件避免 let 可变 routes 难以承接的场景。
    if (initId > 0 && nGetKind(initId) == "COMPTIME_EXPR" && (initType == "array" || initType == "object" || initType == "map") && nGetS2(id) == "CONST") {
        const ceLit = comptimeExprLiteral.getString(`${initId}`)
        const ceTv = parseInt(ceLit)
        if (ceTv > 0) {
            ctVars.set(`${currentFunc}:${name}`, `${ctVal(ceTv)}`)
            return
        }
    }
    const llType = ssTypeToLLVM(initType)

    // Global vars: just store (alloca already done by genGlobalVar)
    if (currentFunc == "" && globalAliases.has(name) == 1) {
        const val = genExpr(initId)
        const gn = globalAliases.getString(name)
        emitIR(`  store ${llType} ${val}, ptr ${gn}, align 8`)
        return
    }
    const llName = allocVarName(name)
    emitEntryAlloca(`%${llName}`, llType, 8)
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
        const newClassName = resolveCtTypeAlias(nGetS1(initId))
        if (genericClassNodes.has(newClassName) == 1) {
            setObjClass(name, inferGenericClassName(newClassName, nGetList(initId), nGetS2(initId)))
        } else {
            setObjClass(name, newClassName)
        }
    }
    // Propagate class from IDENT (let b = a where a is a class instance)
    if (nGetKind(initId) == "IDENT") {
        const srcClass = getObjClass(nGetS1(initId))
        if (srcClass != "") {
            setObjClass(name, srcClass)
        } else {
            const srcType = getVarType(nGetS1(initId))
            if (srcType != "" && classFields.has(srcType) == 1) {
                setObjClass(name, srcType)
            }
        }
    }
    if (getObjClass(name) == "") {
        const retType = inferType(initId)
        if (retType != "" && classFields.has(retType) == 1) {
            setObjClass(name, retType)
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

    const initTagged = genVal(initId)
    if (nGetS2(id) == "CONST" && isCt(initTagged) == 1) {
        ctVars.set(`${currentFunc}:${name}`, `${initTagged}`)
    }
    let val = reg(initTagged)
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
            let trackType = initType
            if (typeAnn != "" && typeAnn.contains("<") == 1) { trackType = typeAnn }
            trackPtrVar(llName, trackType)
            if (isOwnedExpr(initId) == 0 && isRcManaged(trackType) == 1) {
                // D168 §C.11: borrowed RC-managed 局部 binding-retain 走 ss_retain_any
                // (magic 分派),与 emitReleaseVarList 的 ss_release_any 出口对称。
                emitIR(`  call void @ss_retain_any(ptr ${val})`)
            }
        }
    }
    // Track fn-typed locals for closure release at function exit
    // Only function-scope (rcBlockDepth==0); block-scope closures freed by scope rules
    if (isFnType(initType) == 1 && currentFunc != "" && rcBlockDepth == 0) {
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
    // D089 Phase 3: comptime return → set flag + value
    if (comptimeMustBeKnown == 1) {
        const ctRetValId = nGetI1(id)
        if (ctRetValId > 0) {
            const ctRetTagged = genVal(ctRetValId)
            if (isCt(ctRetTagged) == 1) {
                interpReturnVal = payload(ctRetTagged)
            }
        }
        interpReturnFlag = 1
        return
    }
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
        // Get declared return type (retSSType 复用于下方 D168 §C.11 RC 分派)
        let retSSType = ""
        const hasRetType = funcRetTypes.has(currentFunc)
        if (hasRetType == 1) { retSSType = funcRetTypes.getString(currentFunc) }
        let declRet = "i32"
        if (hasRetType == 1) { declRet = ssTypeToLLVM(retSSType) }
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
        // RC: retain borrowed RC-managed ptr before releasing locals。按声明返回类型
        // retSSType(精确)判 isRcManaged —— inferType(valId) 对 method-call 返回式不
        // 精确会误判;Ref/Channel 等非 RC-managed 返回跳过(ss_*_any 不支持其布局)。
        if (declRet == "ptr" && isOwnedExpr(valId) == 0 && isRcManaged(retSSType) == 1) {
            emitIR(`  call void @ss_retain_any(ptr ${val})`)
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
