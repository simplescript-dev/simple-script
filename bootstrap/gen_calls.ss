// gen_calls.ss — Function calls, template literals, array literals
// Arrow functions and closures in gen_arrows.ss.

import { genArrowFunc, flushArrowDefs } from "./gen_arrows"

let tmplPreRegs = new Map()

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

// ── D082: ref() and watch() call codegen ────────────────────────

function genRefCall(argList: string): string {
    // ref(value) → ss_refNew(value as i64)
    const parts = argList.split(",")
    const argId = parseInt(parts[0])
    const val = genExpr(argId)
    const val64 = emitValueToI64(val, inferType(argId))
    const result = nextReg()
    emitIR(`  ${result} = call ptr @ss_refNew(i64 ${val64})`)
    return result
}

function genWatchCall(argList: string) {
    // watch(ref, callback) → ss_refWatch(ref, callback as i64)
    const parts = argList.split(",")
    const refId = parseInt(parts[0])
    const cbId = parseInt(parts[1])
    const refVal = genExpr(refId)
    const cbVal = genExpr(cbId)
    emitIR(`  call void @ss_refWatch(ptr ${refVal}, i64 ${cbVal})`)
}

// ── D080: exec() call codegen ───────────────────────────────────

function genExecCall(argList: string): string {
    // exec(cmd) → call ss_popen_read, get exit code, construct ExecResult
    const parts = argList.split(",")
    const cmdId = parseInt(parts[0])
    const cmdReg = genExpr(cmdId)

    // Call ss_popen_read(cmd) → stdout string
    const stdout = nextReg()
    emitIR(`  ${stdout} = call ptr @ss_popen_read(ptr ${cmdReg})`)

    // Load exit code from global (set by ss_popen_read)
    const code = nextReg()
    emitIR(`  ${code} = load i32, ptr @ss_last_exit_code, align 4`)

    // Construct ExecResult via its auto-generated constructor
    const result = nextReg()
    emitIR(`  ${result} = call ptr @ExecResult_new(ptr ${stdout}, i32 ${code})`)

    return result
}

// ── D079: test() call codegen ───────────────────────────────────

function genTestCall(argList: string) {
    // Parse arguments: test("name", () => { ... })
    const parts = argList.split(",")
    let nameId = 0
    let fnId = 0
    let idx = 0
    for (p in parts) {
        const aid = parseInt(p)
        if (aid > 0) {
            if (idx == 0) { nameId = aid }
            if (idx == 1) { fnId = aid }
            idx = idx + 1
        }
    }

    const nameReg = genExpr(nameId)
    const fnReg = genExpr(fnId)

    const t0 = nextReg()
    emitIR(`  ${t0} = load i32, ptr @ss_test_total, align 4`)
    const t1 = nextReg()
    emitIR(`  ${t1} = add i32 ${t0}, 1`)
    emitIR(`  store i32 ${t1}, ptr @ss_test_total, align 4`)

    // Set up try/catch using setjmp (same pattern as genTryCatch)
    const depthR = nextReg()
    emitIR(`  ${depthR} = load i32, ptr @ss_exc_depth`)
    const newDepth = nextReg()
    emitIR(`  ${newDepth} = add i32 ${depthR}, 1`)
    emitIR(`  store i32 ${newDepth}, ptr @ss_exc_depth`)
    const offset = nextReg()
    emitIR(`  ${offset} = mul i32 ${depthR}, 200`)
    const off64 = nextReg()
    emitIR(`  ${off64} = sext i32 ${offset} to i64`)
    const bufPtr = nextReg()
    emitIR(`  ${bufPtr} = getelementptr i8, ptr @ss_jmpbuf, i64 ${off64}`)

    const sjRet = nextReg()
    emitIR(`  ${sjRet} = call i32 @setjmp(ptr ${bufPtr})`)
    const isExc = nextReg()
    emitIR(`  ${isExc} = icmp ne i32 ${sjRet}, 0`)

    const tryLabel = nextLabel("test.try")
    const catchLabel = nextLabel("test.catch")
    const passLabel = nextLabel("test.pass")
    const endLabel = nextLabel("test.end")

    emitIR(`  br i1 ${isExc}, label %${catchLabel}, label %${tryLabel}`)

    // ── Try: call the callback ──
    emitIR(`${tryLabel}:`)
    // Call fn (check closure vs direct)
    const tagBit = nextReg()
    emitIR(`  ${tagBit} = and i64 ${fnReg}, 1`)
    const isClosure = nextReg()
    emitIR(`  ${isClosure} = icmp eq i64 ${tagBit}, 1`)
    const closureLabel = nextLabel("test.closure")
    const directLabel = nextLabel("test.direct")
    emitIR(`  br i1 ${isClosure}, label %${closureLabel}, label %${directLabel}`)

    // Closure path
    emitIR(`${closureLabel}:`)
    const untagged = nextReg()
    emitIR(`  ${untagged} = and i64 ${fnReg}, -2`)
    const closurePtr = nextReg()
    emitIR(`  ${closurePtr} = inttoptr i64 ${untagged} to ptr`)
    const fnField = nextReg()
    emitIR(`  ${fnField} = getelementptr ptr, ptr ${closurePtr}, i32 2`)
    const fnPtr = nextReg()
    emitIR(`  ${fnPtr} = load ptr, ptr ${fnField}, align 8`)
    emitIR(`  call void ${fnPtr}(ptr ${closurePtr})`)
    emitIR(`  br label %${passLabel}`)

    // Direct path
    emitIR(`${directLabel}:`)
    const fpPtr = nextReg()
    emitIR(`  ${fpPtr} = inttoptr i64 ${fnReg} to ptr`)
    emitIR(`  call void ${fpPtr}()`)
    emitIR(`  br label %${passLabel}`)

    // ── Pass ──
    emitIR(`${passLabel}:`)
    emitExcDepthDec()
    // Increment passed
    const p0 = nextReg()
    emitIR(`  ${p0} = load i32, ptr @ss_test_passed, align 4`)
    const p1 = nextReg()
    emitIR(`  ${p1} = add i32 ${p0}, 1`)
    emitIR(`  store i32 ${p1}, ptr @ss_test_passed, align 4`)
    // Print "  PASS: <name>"
    const passMsg = nextReg()
    emitIR(`  ${passMsg} = call ptr @ss_string_concat(ptr @.rt.str.test_pass, ptr ${nameReg})`)
    emitIR(`  call void @ss_println(ptr ${passMsg})`)
    emitIR(`  call void @ss_rc_release(ptr ${passMsg})`)
    emitIR(`  br label %${endLabel}`)

    // ── Catch ──
    emitIR(`${catchLabel}:`)
    emitExcDepthDec()
    // Increment failed
    const f0 = nextReg()
    emitIR(`  ${f0} = load i32, ptr @ss_test_failed, align 4`)
    const f1 = nextReg()
    emitIR(`  ${f1} = add i32 ${f0}, 1`)
    emitIR(`  store i32 ${f1}, ptr @ss_test_failed, align 4`)
    // Print "  FAIL: <name> - <error>"
    const excMsg = nextReg()
    emitIR(`  ${excMsg} = load ptr, ptr @ss_exc_msg`)
    const failPart = nextReg()
    emitIR(`  ${failPart} = call ptr @ss_string_concat(ptr @.rt.str.test_fail, ptr ${nameReg})`)
    const failSep = nextReg()
    emitIR(`  ${failSep} = call ptr @ss_string_concat(ptr ${failPart}, ptr @.rt.str.test_sep)`)
    emitIR(`  call void @ss_rc_release(ptr ${failPart})`)
    const failFull = nextReg()
    emitIR(`  ${failFull} = call ptr @ss_string_concat(ptr ${failSep}, ptr ${excMsg})`)
    emitIR(`  call void @ss_rc_release(ptr ${failSep})`)
    emitIR(`  call void @ss_println(ptr ${failFull})`)
    emitIR(`  call void @ss_rc_release(ptr ${failFull})`)
    emitIR(`  br label %${endLabel}`)

    // ── End ──
    emitIR(`${endLabel}:`)
}

// ── Call argument resolution ────────────────────────────────────

function resolveCallArgs(callee: string, argList: string, typeCallee: string): string {
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
        let argIdx = 0
        for (ap in argParts) {
            const argId = parseInt(ap)
            if (argId > 0) {
                let val = genExpr(argId)
                let vType = inferType(argId)
                const ptKey = `${typeCallee}:${argIdx}`
                if (funcParamTypes.has(ptKey) == 1 && funcParamTypes.getString(ptKey) == "double" && (vType == "int" || vType == "auto")) {
                    const cvR = nextReg()
                    emitIR(`  ${cvR} = sitofp i32 ${val} to double`)
                    val = cvR
                    vType = "double"
                }
                const llType = ssTypeToLLVM(vType)
                if (first == 1) { first = 0 } else { args = args + ", " }
                args = `${args}${llType} ${val}`
                argIdx = argIdx + 1
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
            let converted = emitI64ToValue(elemVal, elemType)
            let convType = elemType
            const spKey = `${typeCallee}:${providedCount + idx}`
            if (funcParamTypes.has(spKey) == 1 && funcParamTypes.getString(spKey) == "double" && (convType == "int" || convType == "auto")) {
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

    // 5. Register specialized param types and emit call
    if (declParams != "") {
        const ptParts = declParams.split(",")
        let ptIdx = 0
        for (ptp in ptParts) {
            const ptId = parseInt(ptp)
            if (ptId <= 0 || nGetKind(ptId) != "PARAM") { continue }
            let pt = nGetS2(ptId)
            if (subs.has(pt) == 1) { pt = subs.getString(pt) }
            funcParamTypes.set(`${mangledName}:${ptIdx}`, pt)
            ptIdx = ptIdx + 1
        }
    }
    const args = resolveCallArgs(callee, argList, mangledName)
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

    // D079: test("name", callback) — inline try/catch wrapper
    if (callee == "test") {
        genTestCall(argList)
        return "0"
    }

    // D080: exec(cmd) — popen + ExecResult construction
    if (callee == "exec") {
        return genExecCall(argList)
    }

    // D082: ref(value) — create reactive reference
    if (callee == "ref") {
        return genRefCall(argList)
    }

    // D082: watch(ref, callback) — register watcher
    if (callee == "watch") {
        genWatchCall(argList)
        return "0"
    }

    const effectiveName = resolvedName != callee ? resolvedName : callee
    const rtName = runtimeName(effectiveName)
    const args = resolveCallArgs(callee, argList, effectiveName)
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
                const preKey = `${fragId}`
                if (tmplPreRegs.has(preKey) == 1) {
                    fragStr = genExprAsString(nGetI1(fragId), tmplPreRegs.getString(preKey))
                } else {
                    fragStr = genExprAsString(nGetI1(fragId))
                }
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
                        const val64 = emitValueToI64(val, inferType(elemId))
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
                const val64 = emitValueToI64(val, inferType(elemId))
                emitIR(`  call void @ss_arraySet(ptr ${arrReg}, i32 ${idx}, i64 ${val64})`)
                idx = idx + 1
            }
        }
    }
    return arrReg
}
