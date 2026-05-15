// gen_arrows.ss — Arrow functions, closures, capture analysis
// Used by gen_calls.ss via textual import. No own imports needed.

// ── Arrow functions + closures ──────────────────────────────────
// Non-capturing arrows compile to top-level define blocks (raw fn ptr, i64).
// Capturing arrows allocate a closure struct, tagged with bit 0 = 1.
let arrowCount = 0
let arrowDefs = ""
const CLOSURE_HDR_SLOTS = 3  // rc, TypeInfo, fn_ptr — captures start at this offset

function parseCaptName(pair: string): string {
    const pos = pair.indexOf(":")
    if (pos <= 0) { return "" }
    return pair.substring(0, pos)
}

function parseCaptType(pair: string): string {
    const pos = pair.indexOf(":")
    if (pos <= 0) { return "" }
    return pair.substring(pos + 1, pair.length() - pos - 1)
}

// ── Capture analysis ────────────────────────────────────────────
// Globals used by collectFreeVarsRec to accumulate results
let captureList = ""     // comma-separated "name:type" pairs
let captureParamSet = Map()  // param names → "1" for O(1) lookup
let captureSeen = ""     // Map: "name" → "1" for dedup

function isCaptureParam(name: string): int {
    return captureParamSet.has(name)
}

function checkCaptureCandidate(name: string) {
    if (name == "" || name == "this") { return }
    if (isCaptureParam(name) == 1) { return }
    if (captureSeen.has(name) == 1) { return }
    if (globalAliases.has(name) == 1) { return }
    if (funcRetTypes.has(name) == 1 && getVarType(name) == "") { return }
    const vType = getVarType(name)
    if (vType == "") { return }
    captureSeen.set(name, "1")
    if (captureList == "") {
        captureList = `${name}:${vType}`
    } else {
        captureList = `${captureList},${name}:${vType}`
    }
}

function collectFreeVarsRec(nodeId: int) {
    if (nodeId <= 0) { return }
    const kind = nGetKind(nodeId)
    if (kind == "") { return }
    // Stop at nested arrow functions (they have their own scope)
    if (kind == "ARROW_FUNC") { return }
    // Check IDENT for capture
    if (kind == "IDENT") {
        checkCaptureCandidate(nGetS1(nodeId))
        return
    }
    // CALL: S1 may be a fn-typed variable reference
    if (kind == "CALL") {
        checkCaptureCandidate(nGetS1(nodeId))
        const cList = nGetList(nodeId)
        if (cList != "") {
            const cParts = cList.split(",")
            for (cp in cParts) {
                collectFreeVarsRec(parseInt(cp))
            }
        }
        return
    }
    // Recurse into all children (I1, I2, I3, List)
    collectFreeVarsRec(nGetI1(nodeId))
    collectFreeVarsRec(nGetI2(nodeId))
    collectFreeVarsRec(nGetI3(nodeId))
    const lst = nGetList(nodeId)
    if (lst != "") {
        const lParts = lst.split(",")
        for (lp in lParts) {
            collectFreeVarsRec(parseInt(lp))
        }
    }
}

function findFreeVars(bodyId: int, paramList: string): string {
    captureList = ""
    captureSeen = Map()
    // Build param name set
    captureParamSet = Map()
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                captureParamSet.set(nGetS1(pId), "1")
            }
        }
    }
    collectFreeVarsRec(bodyId)
    return captureList
}

// ── Arrow function codegen ──────────────────────────────────────

function genArrowFunc(id: int): string {
    arrowCount = arrowCount + 1
    const fnName = `__arrow_${arrowCount}`
    let retType = nGetS2(id)
    if (retType == "") { retType = "int" }
    const llRetType = ssTypeToLLVM(retType)
    const bodyId = nGetI1(id)
    const paramList = nGetList(id)
    funcRetTypes.set(fnName, retType)

    // Capture analysis (before state save, so getVarType sees outer scope)
    const captures = findFreeVars(bodyId, paramList)
    const hasCaptures = captures != "" ? 1 : 0

    // D082 Phase 3: capture thread closure flag, reset for inner arrows
    const thisIsThreadClosure = isThreadClosure
    isThreadClosure = 0

    // Build param string (with ptr %self.arg for capturing arrows)
    let paramStr = ""
    if (hasCaptures == 1) {
        paramStr = "ptr %self.arg"
    }
    if (paramList != "") {
        const parts = paramList.split(",")
        let idx = 0
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0) {
                if (paramStr != "") { paramStr = `${paramStr}, ` }
                paramStr = `${paramStr}${ssTypeToLLVM(nGetS2(pId))} %${nGetS1(pId)}.arg`
                idx = idx + 1
            }
        }
    }

    // Save non-IR-emit state (RC tracking, var aliases, etc.). irBuf/irOutFile/
    // strOutFile/funcEntry* are owned by startFuncEmit/endFuncEmit (stack-based).
    const savedFunc = currentFunc
    const savedReg = regCount
    const savedTerm = terminated
    const savedAliases = varAliases
    const savedPtrVars = localPtrVars
    const savedFnVars = localFnVars
    const savedBlockDepth = rcBlockDepth
    const savedBlockStack = blockPtrVarStack

    currentFunc = fnName
    regCount = 0
    regTable = []
    terminated = 0
    varAliases = Map()
    localPtrVars = ""
    localFnVars = ""
    rcBlockDepth = 0
    blockPtrVarStack = ""

    // SS-LIM-4: enter function-emit window (push IR-emit + entry-alloca state).
    startFuncEmit()

    emitIR(`define ${llRetType} @${fnName}(${paramStr}) {`)
    emitIR("entry:")
    markEntryAllocaPoint()
    emitParamAllocas(paramList, 1)

    // Load captured values from closure struct
    if (hasCaptures == 1) {
        const capParts = captures.split(",")
        let capIdx = 0
        for (cp in capParts) {
            const capName = parseCaptName(cp)
            const capType = parseCaptType(cp)
            if (capName != "") {
                const llCapType = ssTypeToLLVM(capType)
                const capAlias = allocVarName(capName)
                emitEntryAlloca(`%${capAlias}`, llCapType, 8)
                const gepR = nextReg()
                emitIR(`  ${gepR} = getelementptr ptr, ptr %self.arg, i32 ${CLOSURE_HDR_SLOTS + capIdx}`)
                const loadR = nextReg()
                emitIR(`  ${loadR} = load ${llCapType}, ptr ${gepR}, align 8`)
                emitIR(`  store ${llCapType} ${loadR}, ptr %${capAlias}, align 8`)
                setVarType(capName, capType)
                capIdx = capIdx + 1
            }
        }
    }

    genBlock(bodyId)
    if (terminated == 0) {
        if (llRetType == "void") { emitIR("  ret void") }
        else if (llRetType == "ptr") { emitIR(`  ret ptr ${addStringConst("")}`) }
        else { emitIR(`  ret ${llRetType} 0`) }
    }
    emitIR("}")
    emitIR("")

    // Generate per-closure drop function + TypeInfo for capturing closures
    if (hasCaptures == 1) {
        const dropName = `__closure_${arrowCount}_drop`
        emitIR(`define void @${dropName}(ptr %p) {`)
        emitIR("entry:")
        // Release captured ref-type values
        const capParts2 = captures.split(",")
        let capIdx2 = 0
        for (cp2 in capParts2) {
            const capType2 = parseCaptType(cp2)
            if (capType2 != "") {
                const llCapType2 = ssTypeToLLVM(capType2)
                if (llCapType2 == "ptr") {
                    const gepD = nextReg()
                    emitIR(`  ${gepD} = getelementptr ptr, ptr %p, i32 ${CLOSURE_HDR_SLOTS + capIdx2}`)
                    const loadD = nextReg()
                    emitIR(`  ${loadD} = load ptr, ptr ${gepD}, align 8`)
                    // D168 §C.9: dispatch via emitReleaseForType — class/string/Array 走 ss_release
                    // 触发 vtable.drop_fn,Map 等旧 ABI 走 ss_rc_release 兼容(Phase 3 切完统一)
                    emitReleaseForType(loadD, capType2)
                }
                capIdx2 = capIdx2 + 1
            }
        }
        emitIR("  call void @mi_free(ptr %p)")
        emitIR("  ret void")
        emitIR("}")
        emitIR("")
        // TypeInfo for this closure
        const closureNameStr = addStringConst(`closure_${arrowCount}`)
        emitIR(`@__closure_${arrowCount}_type_info = global %TypeInfo { ptr @${dropName}, ptr null, ptr null, i64 0, ptr ${closureNameStr}, i32 0, ptr null }`)
        emitIR("")
    }

    // SS-LIM-4: pop function-emit frame (splice entry allocas + restore IR-emit state).
    const arrowIR = endFuncEmit()
    arrowDefs = `${arrowDefs}${arrowIR}`

    // Restore non-IR-emit state.
    currentFunc = savedFunc
    regCount = savedReg
    terminated = savedTerm
    varAliases = savedAliases
    localPtrVars = savedPtrVars
    localFnVars = savedFnVars
    rcBlockDepth = savedBlockDepth
    blockPtrVarStack = savedBlockStack

    if (hasCaptures == 0) {
        // Non-capturing: return raw function pointer (no closure allocation)
        const r = nextReg()
        emitIR(`  ${r} = ptrtoint ptr @${fnName} to i64`)
        return r
    }

    // Capturing: allocate closure struct { rc, TypeInfo, fn_ptr, captures... }
    const capParts3 = captures.split(",")
    let capCount = 0
    for (cp3 in capParts3) { capCount = capCount + 1 }
    const structSize = (CLOSURE_HDR_SLOTS + capCount) * 8
    const closureReg = nextReg()
    emitIR(`  ${closureReg} = call ptr @mi_calloc(i64 1, i64 ${structSize})`)
    const rcPtr = nextReg()
    emitIR(`  ${rcPtr} = getelementptr i32, ptr ${closureReg}, i32 0`)
    emitIR(`  store i64 1, ptr ${rcPtr}, align 8`)
    const tiPtr = nextReg()
    emitIR(`  ${tiPtr} = getelementptr ptr, ptr ${closureReg}, i32 1`)
    emitIR(`  store ptr @__closure_${arrowCount}_type_info, ptr ${tiPtr}, align 8`)
    const fnFieldR = nextReg()
    emitIR(`  ${fnFieldR} = getelementptr ptr, ptr ${closureReg}, i32 2`)
    emitIR(`  store ptr @${fnName}, ptr ${fnFieldR}, align 8`)
    let capIdx3 = 0
    for (cp4 in capParts3) {
        const capName3 = parseCaptName(cp4)
        const capType3 = parseCaptType(cp4)
        if (capName3 != "") {
            const llCapType3 = ssTypeToLLVM(capType3)
            const capField = nextReg()
            emitIR(`  ${capField} = getelementptr ptr, ptr ${closureReg}, i32 ${CLOSURE_HDR_SLOTS + capIdx3}`)
            const capVal = nextReg()
            emitIR(`  ${capVal} = load ${llCapType3}, ptr ${varRef(capName3)}, align 8`)
            // D082 Phase 3: thread closures deep-clone class instances for isolation
            if (thisIsThreadClosure == 1 && llCapType3 == "ptr" && classFields.has(capType3) == 1) {
                const clonedVal = nextReg()
                emitIR(`  ${clonedVal} = call ptr @ss_deep_clone_${capType3}(ptr ${capVal})`)
                emitIR(`  store ptr ${clonedVal}, ptr ${capField}, align 8`)
            } else {
                emitIR(`  store ${llCapType3} ${capVal}, ptr ${capField}, align 8`)
                if (llCapType3 == "ptr") {
                    // D168 §C.9: dispatch via emitRetainForType — class/string/Array 走 ss_retain,
                    // Map 等旧 ABI 走 ss_rc_retain 兼容(Phase 3 切完统一)
                    emitRetainForType(capVal, capType3)
                }
            }
            capIdx3 = capIdx3 + 1
        }
    }
    // Tag the closure pointer (set bit 0)
    const ptrInt = nextReg()
    emitIR(`  ${ptrInt} = ptrtoint ptr ${closureReg} to i64`)
    const tagged = nextReg()
    emitIR(`  ${tagged} = or i64 ${ptrInt}, 1`)
    return tagged
}

function flushArrowDefs() {
    if (arrowDefs != "") {
        emitIR(arrowDefs)
        arrowDefs = ""
    }
}
