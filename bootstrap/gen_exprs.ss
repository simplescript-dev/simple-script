// Expression generation + type helpers for bootstrap codegen
// ── Expression generation ─────────────────────────────────────
// Returns the SSA register or constant string holding the result.

function genThisExpr(): string {
    const r = nextReg()
    emitIR(`  ${r} = load ptr, ptr %this, align 8`)
    return r
}

function genIdent(id: int): string {
    const name = nGetS1(id)
    const vType = getVarType(name)
    if (vType == "" && funcRetTypes.has(name) == 1) {
        const r = nextReg()
        emitIR(`  ${r} = ptrtoint ptr @${name} to i64`)
        return r
    }
    const r = nextReg(); emitIR(`  ${r} = load ${ssTypeToLLVM(vType)}, ptr ${varRef(name)}, align 8`); return r
}

function genUnary(id: int): string {
    const op = nGetS1(id)
    const val = genExpr(nGetI1(id))
    const r = nextReg()
    if (op == "Neg") {
        const uType = inferType(nGetI1(id))
        if (uType == "double") {
            emitIR(`  ${r} = fsub double 0.0, ${val}`)
        } else {
            emitIR(`  ${r} = sub i32 0, ${val}`)
        }
    } else if (op == "BitNot") {
        emitIR(`  ${r} = xor i32 ${val}, -1`)
    } else {
        emitIR(`  ${r} = icmp eq i32 ${val}, 0`)
        const r2 = nextReg()
        emitIR(`  ${r2} = zext i1 ${r} to i32`)
        return r2
    }
    return r
}

function genIndexAccess(id: int): string {
    let arrVal = genExpr(nGetI1(id))
    const arrType = inferType(nGetI1(id))
    if (arrType == "i64") {
        const cvtR = nextReg()
        emitIR(`  ${cvtR} = inttoptr i64 ${arrVal} to ptr`)
        arrVal = cvtR
    }
    const idxVal = genExpr(nGetI2(id))
    const rawR = nextReg(); emitIR(`  ${rawR} = call i64 @ss_arrayGet(ptr ${arrVal}, i32 ${idxVal})`)
    const idxElem = inferArrayElemType(nGetI1(id))
    if (idxElem == "string") {
        const castR = nextReg()
        emitIR(`  ${castR} = inttoptr i64 ${rawR} to ptr`)
        return castR
    }
    if (idxElem == "int") {
        const castR = nextReg()
        emitIR(`  ${castR} = trunc i64 ${rawR} to i32`)
        return castR
    }
    return rawR
}

function genPostfixExpr(id: int): string {
    const pieRef = varRef(nGetS1(id))
    const r1 = nextReg()
    emitIR(`  ${r1} = load i32, ptr ${pieRef}, align 4`)
    const r2 = nextReg()
    emitIR(`  ${r2} = add i32 ${r1}, 1`)
    emitIR(`  store i32 ${r2}, ptr ${pieRef}, align 4`)
    return r1
}

function genExpr(id: int): string {
    if (id <= 0) { return "0" }
    const kind = nGetKind(id)

    if (kind == "INT_LIT") { return nGetS1(id) }
    if (kind == "DOUBLE_LIT") { return nGetS1(id) }
    if (kind == "STRING_LIT") { return addStringConst(nGetS1(id)) }
    if (kind == "TRUE_LIT") { return "1" }
    if (kind == "FALSE_LIT") { return "0" }
    if (kind == "NULL_LIT") { return "null" }
    if (kind == "THIS") { return genThisExpr() }
    if (kind == "IDENT") { return genIdent(id) }
    if (kind == "BINARY") { return genBinary(id) }
    if (kind == "UNARY") { return genUnary(id) }
    if (kind == "CALL") { return genCall(id) }
    if (kind == "METHOD_CALL") {
        if (nGetI3(id) > 0) { return genOptionalMethodCall(id) }
        return genMethodCall(id)
    }
    if (kind == "MEMBER_ACCESS") { return genMemberAccess(id) }
    if (kind == "NEW_EXPR") { return genNewExpr(id) }
    if (kind == "GROUPING") { return genExpr(nGetI1(id)) }
    if (kind == "TERNARY") { return genTernary(id) }
    if (kind == "TEMPLATE_LIT") { return genTemplateLit(id) }
    if (kind == "ARRAY_LIT") { return genArrayLit(id) }
    if (kind == "ARROW_FUNC") { return genArrowFunc(id) }
    if (kind == "INDEX_ACCESS") { return genIndexAccess(id) }
    if (kind == "POSTFIX_INC") { return genPostfixExpr(id) }
    return "0"
}

// ── Binary operation helpers ─────────────────────────────────

function genStringConcat(leftId: int, rightId: int): string {
    const l = genExprAsString(leftId)
    const lOwned = lastExprStringOwned
    const rVal = genExprAsString(rightId)
    const rOwned = lastExprStringOwned
    const r = nextReg(); emitIR(`  ${r} = call ptr @ss_string_concat(ptr ${l}, ptr ${rVal})`)
    // RC: release left operand (concat chain intermediate or conversion temp)
    if (lOwned == 1 || (nGetKind(leftId) == "BINARY" && inferType(nGetI1(leftId)) == "string")) {
        emitIR(`  call void @ss_rc_release(ptr ${l})`)
    }
    // RC Phase 5: release right conversion temp
    if (rOwned == 1) {
        emitIR(`  call void @ss_rc_release(ptr ${rVal})`)
    }
    return r
}

function genStringCompare(op: string, leftId: int, rightId: int, blt: string, brt: string): string {
    // String equality (Eq/Ne)
    if (op == "Eq" || op == "Ne") {
        let l = genExpr(leftId)
        let rVal = genExpr(rightId)
        if (blt == "i64") {
            const cvR = nextReg()
            emitIR(`  ${cvR} = inttoptr i64 ${l} to ptr`)
            l = cvR
        }
        if (brt == "i64") {
            const cvR = nextReg()
            emitIR(`  ${cvR} = inttoptr i64 ${rVal} to ptr`)
            rVal = cvR
        }
        const r = nextReg()
        if (op == "Eq") {
            emitIR(`  ${r} = call i32 @ss_string_eq(ptr ${l}, ptr ${rVal})`)
        } else {
            emitIR(`  ${r} = call i32 @ss_string_ne(ptr ${l}, ptr ${rVal})`)
        }
        return r
    }
    // String ordering (Lt/Gt/Le/Ge) using strcmp
    const sl = genExpr(leftId)
    const sr = genExpr(rightId)
    const cmpR = nextReg()
    emitIR(`  ${cmpR} = call i32 @ss_strcmp(ptr ${sl}, ptr ${sr})`)
    let cmpOp = "slt"
    if (op == "Gt") { cmpOp = "sgt" }
    if (op == "Le") { cmpOp = "sle" }
    if (op == "Ge") { cmpOp = "sge" }
    const cmpBool = nextReg()
    emitIR(`  ${cmpBool} = icmp ${cmpOp} i32 ${cmpR}, 0`)
    const r = nextReg(); emitIR(`  ${r} = zext i1 ${cmpBool} to i32`); return r
}

function genNullCoalesce(leftId: int, rightId: int): string {
    const ncResult = nextReg()
    emitIR(`  ${ncResult} = alloca ptr, align 8`)
    const ncLeft = genExpr(leftId)
    emitIR(`  store ptr ${ncLeft}, ptr ${ncResult}, align 8`)
    const ncLen = nextReg()
    emitIR(`  ${ncLen} = call i32 @ss_stringLength(ptr ${ncLeft})`)
    const ncCmp = nextReg()
    emitIR(`  ${ncCmp} = icmp eq i32 ${ncLen}, 0`)
    const ncThen = nextLabel("nc.then")
    const ncEnd = nextLabel("nc.end")
    emitIR(`  br i1 ${ncCmp}, label %${ncThen}, label %${ncEnd}`)
    emitIR(`${ncThen}:`)
    const ncRight = genExpr(rightId)
    emitIR(`  store ptr ${ncRight}, ptr ${ncResult}, align 8`)
    emitIR(`  br label %${ncEnd}`)
    emitIR(`${ncEnd}:`)
    const ncFinal = nextReg()
    emitIR(`  ${ncFinal} = load ptr, ptr ${ncResult}, align 8`)
    return ncFinal
}

function genShortCircuit(op: string, leftId: int, rightId: int): string {
    const scResult = nextReg()
    emitIR(`  ${scResult} = alloca i32, align 4`)
    const scLeft = genExpr(leftId)
    emitIR(`  store i32 ${scLeft}, ptr ${scResult}, align 4`)
    const scCmp = nextReg()
    emitIR(`  ${scCmp} = icmp ne i32 ${scLeft}, 0`)
    const scRhs = nextLabel("sc.rhs")
    const scEnd = nextLabel("sc.end")
    if (op == "And") { emitIR(`  br i1 ${scCmp}, label %${scRhs}, label %${scEnd}`) } else { emitIR(`  br i1 ${scCmp}, label %${scEnd}, label %${scRhs}`) }
    emitIR(`${scRhs}:`)
    const scRight = genExpr(rightId)
    emitIR(`  store i32 ${scRight}, ptr ${scResult}, align 4`)
    emitIR(`  br label %${scEnd}`)
    emitIR(`${scEnd}:`)
    const scRes = nextReg()
    emitIR(`  ${scRes} = load i32, ptr ${scResult}, align 4`)
    return scRes
}

function genDoubleBinary(op: string, left: string, right: string, blt: string, brt: string): string {
    let dl = left
    let dr = right
    if (blt != "double") {
        const cvtR = nextReg()
        emitIR(`  ${cvtR} = sitofp i32 ${dl} to double`)
        dl = cvtR
    }
    if (brt != "double") {
        const cvtR = nextReg()
        emitIR(`  ${cvtR} = sitofp i32 ${dr} to double`)
        dr = cvtR
    }
    const r = nextReg()
    if (op == "Add") { emitIR(`  ${r} = fadd double ${dl}, ${dr}`); return r }
    if (op == "Sub") { emitIR(`  ${r} = fsub double ${dl}, ${dr}`); return r }
    if (op == "Mul") { emitIR(`  ${r} = fmul double ${dl}, ${dr}`); return r }
    if (op == "Div") { emitIR(`  ${r} = fdiv double ${dl}, ${dr}`); return r }
    if (op == "Mod") { emitIR(`  ${r} = frem double ${dl}, ${dr}`); return r }
    let fcmpOp = ""
    if (op == "Eq") { fcmpOp = "oeq" }
    if (op == "Ne") { fcmpOp = "one" }
    if (op == "Lt") { fcmpOp = "olt" }
    if (op == "Gt") { fcmpOp = "ogt" }
    if (op == "Le") { fcmpOp = "ole" }
    if (op == "Ge") { fcmpOp = "oge" }
    if (fcmpOp != "") {
        emitIR(`  ${r} = fcmp ${fcmpOp} double ${dl}, ${dr}`)
        const r2 = nextReg()
        emitIR(`  ${r2} = zext i1 ${r} to i32`)
        return r2
    }
    return r
}

function genIntBinary(op: string, left: string, right: string): string {
    const r = nextReg()
    if (op == "Add") { emitIR(`  ${r} = add i32 ${left}, ${right}`); return r }
    if (op == "Sub") { emitIR(`  ${r} = sub i32 ${left}, ${right}`); return r }
    if (op == "Mul") { emitIR(`  ${r} = mul i32 ${left}, ${right}`); return r }
    if (op == "Div") { emitIR(`  ${r} = sdiv i32 ${left}, ${right}`); return r }
    if (op == "Mod") { emitIR(`  ${r} = srem i32 ${left}, ${right}`); return r }
    if (op == "BitAnd") { emitIR(`  ${r} = and i32 ${left}, ${right}`); return r }
    if (op == "BitOr") { emitIR(`  ${r} = or i32 ${left}, ${right}`); return r }
    if (op == "BitXor") { emitIR(`  ${r} = xor i32 ${left}, ${right}`); return r }
    if (op == "Shl") { emitIR(`  ${r} = shl i32 ${left}, ${right}`); return r }
    if (op == "Shr") { emitIR(`  ${r} = ashr i32 ${left}, ${right}`); return r }
    if (op == "UShr") { emitIR(`  ${r} = lshr i32 ${left}, ${right}`); return r }
    let cmpOp = ""
    if (op == "Eq") { cmpOp = "eq" }
    if (op == "Ne") { cmpOp = "ne" }
    if (op == "Lt") { cmpOp = "slt" }
    if (op == "Gt") { cmpOp = "sgt" }
    if (op == "Le") { cmpOp = "sle" }
    if (op == "Ge") { cmpOp = "sge" }
    if (cmpOp != "") {
        emitIR(`  ${r} = icmp ${cmpOp} i32 ${left}, ${right}`)
        const r2 = nextReg()
        emitIR(`  ${r2} = zext i1 ${r} to i32`)
        return r2
    }
    emitIR(`  ; unknown binary op: ${op}`)
    return r
}

function genBinary(id: int): string {
    const op = nGetS1(id)
    const leftId = nGetI1(id)
    const rightId = nGetI2(id)
    const blt = inferType(leftId)
    const brt = inferType(rightId)

    // String concatenation
    if (op == "Add" && (blt == "string" || brt == "string" || blt == "i64" || brt == "i64")) {
        if (blt == "string" || brt == "string") {
            return genStringConcat(leftId, rightId)
        }
    }
    // String equality/comparison
    if ((op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge") && (blt == "string" || brt == "string")) {
        return genStringCompare(op, leftId, rightId, blt, brt)
    }
    if (op == "NullCoalesce") { return genNullCoalesce(leftId, rightId) }
    if (op == "And" || op == "Or") { return genShortCircuit(op, leftId, rightId) }

    // Numeric: evaluate operands
    let left = genExpr(leftId)
    let right = genExpr(rightId)
    if (blt == "i64") { const tr = nextReg(); emitIR(`  ${tr} = trunc i64 ${left} to i32`); left = tr }
    if (brt == "i64") { const tr = nextReg(); emitIR(`  ${tr} = trunc i64 ${right} to i32`); right = tr }

    if (blt == "double" || brt == "double") {
        return genDoubleBinary(op, left, right, blt, brt)
    }
    return genIntBinary(op, left, right)
}

// ── Call helpers ─────────────────────────────────────────────

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

function resolveCallArgs(callee: string, argList: string, expectsDouble: int): string {
    let providedArgs = ""
    let providedCount = 0
    if (argList != "") {
        const parts = argList.split(",")
        for (p in parts) {
            const argId = parseInt(p)
            if (argId > 0) {
                if (providedArgs == "") { providedArgs = `${argId}` } else { providedArgs = `${providedArgs},${argId}` }
                providedCount = providedCount + 1
            }
        }
    }
    let expectedCount = providedCount
    if (funcParamCount.has(callee) == 1) {
        expectedCount = parseInt(funcParamCount.getString(callee))
    }
    let fullArgs = providedArgs
    if (providedCount < expectedCount && funcDefaults.has(callee) == 1) {
        const defs = funcDefaults.getString(callee)
        const defParts = defs.split(",")
        for (dp in defParts) {
            const colonPos = dp.indexOf(":")
            if (colonPos > 0) {
                const defIdx = parseInt(dp.substring(0, colonPos))
                const defNodeId = dp.substring(colonPos + 1, dp.length() - colonPos - 1)
                if (defIdx >= providedCount) {
                    if (fullArgs == "") { fullArgs = defNodeId } else { fullArgs = `${fullArgs},${defNodeId}` }
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
    return args
}

function genCall(id: int): string {
    const callee = nGetS1(id)
    const argList = nGetList(id)
    const resolvedName = resolveOverload(callee, argList)

    if (callee == "println" || callee == "print") {
        return genPrintCall(callee, argList)
    }

    const effectiveName = resolvedName != callee ? resolvedName : callee
    const rtName = runtimeName(effectiveName)
    const args = resolveCallArgs(callee, argList, callReturnType(effectiveName) == "double" ? 1 : 0)
    const retType = callReturnType(effectiveName)
    const llRetType = ssTypeToLLVM(retType)

    // Indirect call: function pointer variable
    if (getVarType(callee) == "fn" || getVarType(callee) == "i64") {
        const fpVal = nextReg()
        emitIR(`  ${fpVal} = load i64, ptr ${varRef(callee)}, align 8`)
        const fpPtr = nextReg()
        emitIR(`  ${fpPtr} = inttoptr i64 ${fpVal} to ptr`)
        const r = nextReg()
        emitIR(`  ${r} = call i64 ${fpPtr}(${args})`)
        return r
    }

    if (llRetType == "void") {
        emitIR(`  call void @${rtName}(${args})`)
        return "0"
    }
    const r = nextReg(); emitIR(`  ${r} = call ${llRetType} @${rtName}(${args})`); return r
}

// obj?.method() — if obj is "", return default; otherwise call normally
function genOptionalMethodCall(id: int): string {
    const objId = nGetI1(id)
    const objVal = genExpr(objId)
    const retType = inferType(id)
    const llRetType = ssTypeToLLVM(retType)

    // Alloca for result
    const resultAlloca = nextReg()
    emitIR(`  ${resultAlloca} = alloca ${llRetType}, align 8`)
    // Store default
    if (llRetType == "ptr") {
        const emptyStr = addStringConst("")
        emitIR(`  store ptr ${emptyStr}, ptr ${resultAlloca}, align 8`)
    } else {
        emitIR(`  store ${llRetType} 0, ptr ${resultAlloca}, align 8`)
    }

    // Check if obj is null
    const cmpR = nextReg()
    emitIR(`  ${cmpR} = icmp eq ptr ${objVal}, null`)
    const callLabel = nextLabel("opt.call")
    const endLabel = nextLabel("opt.end")
    emitIR(`  br i1 ${cmpR}, label %${endLabel}, label %${callLabel}`)

    // Call method normally (clear the optional flag so genMethodCall doesn't loop)
    emitIR(`${callLabel}:`)
    nSetI3(id, 0)
    const callResult = genMethodCall(id)
    emitIR(`  store ${llRetType} ${callResult}, ptr ${resultAlloca}, align 8`)
    emitIR(`  br label %${endLabel}`)

    emitIR(`${endLabel}:`)
    const finalR = nextReg()
    emitIR(`  ${finalR} = load ${llRetType}, ptr ${resultAlloca}, align 8`)
    return finalR
}

function emitClassMethodCall(className: string, method: string, objVal: string, argList: string, isStatic: int): string {
    // Walk parent chain to find the class that has this method
    let methodClass = className
    while (methodClass != "") {
        if (funcRetTypes.has(`${methodClass}_${method}`) == 1) { break }
        if (classParents.has(methodClass) == 1) {
            methodClass = classParents.getString(methodClass)
        } else {
            methodClass = className
            break
        }
    }
    // Build args: static calls skip this, instance calls include this as first arg
    let callArgs = ""
    if (isStatic == 0) { callArgs = `ptr ${objVal}` }
    if (argList != "") {
        const argParts = argList.split(",")
        for (ap in argParts) {
            const argId = parseInt(ap)
            if (argId > 0) {
                let aVal = genExpr(argId)
                let aType = inferType(argId)
                if (callArgs != "") { callArgs = `${callArgs}, ` }
                callArgs = `${callArgs}${ssTypeToLLVM(aType)} ${aVal}`
            }
        }
    }
    // Resolve overloaded method name
    let resolved = `${methodClass}_${method}`
    if (isOverloaded(resolved) == 1) {
        const sig = argsSig(argList)
        if (sig != "" && funcRetTypes.has(`${resolved}_${sig}`) == 1) {
            resolved = `${resolved}_${sig}`
        }
    }
    let retType = "ptr"
    if (funcRetTypes.has(resolved) == 1) {
        retType = ssTypeToLLVM(funcRetTypes.getString(resolved))
    }
    // Vtable indirect dispatch for instance calls on vtable classes
    if (isStatic == 0 && classNeedsVtable.has(className) == 1 && classVtableSlots.has(className) == 1) {
        const vtSlots = classVtableSlots.getString(className)
        const slotParts = vtSlots.split(",")
        let slotIdx = -1
        let si = 0
        for (sp in slotParts) {
            if (sp == method) { slotIdx = si }
            si = si + 1
        }
        if (slotIdx >= 0) {
            // Load vtable ptr from object (first field at offset 0)
            const vtPtrR = nextReg()
            emitIR(`  ${vtPtrR} = load ptr, ptr ${objVal}, align 8`)
            // Load function ptr from vtable slot
            const fnGep = nextReg()
            emitIR(`  ${fnGep} = getelementptr ptr, ptr ${vtPtrR}, i32 ${slotIdx}`)
            const fnPtr = nextReg()
            emitIR(`  ${fnPtr} = load ptr, ptr ${fnGep}, align 8`)
            // Indirect call through vtable
            if (retType == "void") {
                emitIR(`  call void ${fnPtr}(${callArgs})`)
                return "0"
            }
            const r = nextReg()
            emitIR(`  ${r} = call ${retType} ${fnPtr}(${callArgs})`)
            return r
        }
    }
    // Static dispatch fallback
    if (retType == "void") {
        emitIR(`  call void @${resolved}(${callArgs})`)
        return "0"
    }
    const r = nextReg()
    emitIR(`  ${r} = call ${retType} @${resolved}(${callArgs})`)
    return r
}

// Check if a class (or its parents) has a given method
function classHasMethod(cls: string, method: string): int {
    let c = cls
    while (c != "") {
        if (funcRetTypes.has(`${c}_${method}`) == 1) { return 1 }
        if (classParents.has(c) == 1) { c = classParents.getString(c) } else { return 0 }
    }
    return 0
}

// ── Built-in method sub-dispatchers ──────────────────────────

function genStringMethod(method: string, objVal: string, argList: string): string {
    if (method == "charAt" || method == "charCodeAt" || method == "repeat") {
        const av = genExpr(parseInt(argList))
        let retT = "ptr"
        if (method == "charCodeAt") { retT = "i32" }
        const fn = preludeName(`ss_${method}`)
        const r = nextReg(); emitIR(`  ${r} = call ${retT} @${fn}(ptr ${objVal}, i32 ${av})`); return r
    }
    if (method == "substring") {
        const argParts = argList.split(",")
        const startVal = genExpr(parseInt(argParts[0]))
        const lenVal = genExpr(parseInt(argParts[1]))
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_substring(ptr ${objVal}, i32 ${startVal}, i32 ${lenVal})`); return r
    }
    if (method == "contains") {
        const sub = genExpr(parseInt(argList))
        const idxR = nextReg()
        emitIR(`  ${idxR} = call i32 @ss_indexOf(ptr ${objVal}, ptr ${sub})`)
        const cmpR = nextReg()
        emitIR(`  ${cmpR} = icmp sge i32 ${idxR}, 0`)
        const r = nextReg()
        emitIR(`  ${r} = zext i1 ${cmpR} to i32`)
        return r
    }
    if (method == "startsWith") {
        const sub = genExpr(parseInt(argList))
        const pLen = nextReg()
        emitIR(`  ${pLen} = call i32 @ss_stringLength(ptr ${sub})`)
        const subStr = nextReg()
        emitIR(`  ${subStr} = call ptr @ss_substring(ptr ${objVal}, i32 0, i32 ${pLen})`)
        const r = nextReg()
        emitIR(`  ${r} = call i32 @ss_string_eq(ptr ${subStr}, ptr ${sub})`)
        return r
    }
    if (method == "endsWith") {
        const sub = genExpr(parseInt(argList))
        const sLen = nextReg()
        emitIR(`  ${sLen} = call i32 @ss_stringLength(ptr ${objVal})`)
        const sufLen = nextReg()
        emitIR(`  ${sufLen} = call i32 @ss_stringLength(ptr ${sub})`)
        const start = nextReg()
        emitIR(`  ${start} = sub i32 ${sLen}, ${sufLen}`)
        const subStr = nextReg()
        emitIR(`  ${subStr} = call ptr @ss_substring(ptr ${objVal}, i32 ${start}, i32 ${sufLen})`)
        const r = nextReg()
        emitIR(`  ${r} = call i32 @ss_string_eq(ptr ${subStr}, ptr ${sub})`)
        return r
    }
    if (method == "replace") {
        const argParts = argList.split(",")
        const oldVal = genExpr(parseInt(argParts[0]))
        const newVal = genExpr(parseInt(argParts[1]))
        const fn = preludeName("ss_replace")
        const r = nextReg(); emitIR(`  ${r} = call ptr @${fn}(ptr ${objVal}, ptr ${oldVal}, ptr ${newVal})`); return r
    }
    if (method == "split") {
        const delim = genExpr(parseInt(argList))
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_split(ptr ${objVal}, ptr ${delim})`); return r
    }
    if (method == "join") {
        const delim = genExpr(parseInt(argList))
        const fn = preludeName("ss_join")
        const r = nextReg(); emitIR(`  ${r} = call ptr @${fn}(ptr ${objVal}, ptr ${delim})`); return r
    }
    if (method == "trim" || method == "toUpperCase" || method == "toLowerCase") {
        const fn = preludeName(`ss_${method}`)
        const r = nextReg(); emitIR(`  ${r} = call ptr @${fn}(ptr ${objVal})`); return r
    }
    if (method == "padStart" || method == "padEnd") {
        const ap = argList.split(",")
        const w = genExpr(parseInt(ap[0]))
        const p = genExpr(parseInt(ap[1]))
        const fn = preludeName(`ss_${method}`)
        const r = nextReg(); emitIR(`  ${r} = call ptr @${fn}(ptr ${objVal}, i32 ${w}, ptr ${p})`); return r
    }
    return ""
}

function genHigherOrderMethod(method: string, objVal: string, argList: string): string {
    if (method == "map" || method == "filter" || method == "forEach") {
        const cbVal = genExpr(parseInt(argList))
        const fn = preludeName(`ss_${method}`)
        const r = nextReg()
        emitIR(`  ${r} = call ptr @${fn}(ptr ${objVal}, i64 ${cbVal})`)
        return r
    }
    if (method == "reduce") {
        const rArgs = argList.split(",")
        const cbVal = genExpr(parseInt(rArgs[0]))
        const initVal = genExpr(parseInt(rArgs[1]))
        let initI64 = initVal
        if (inferType(parseInt(rArgs[1])) == "int") {
            const sR = nextReg()
            emitIR(`  ${sR} = sext i32 ${initVal} to i64`)
            initI64 = sR
        }
        const fn = preludeName("ss_reduce")
        const r64 = nextReg()
        emitIR(`  ${r64} = call i64 @${fn}(ptr ${objVal}, i64 ${cbVal}, i64 ${initI64})`)
        const r = nextReg()
        emitIR(`  ${r} = trunc i64 ${r64} to i32`)
        return r
    }
    return ""
}

function genArrayMethod(method: string, objVal: string, argList: string): string {
    if (method == "push") {
        const argId = parseInt(argList)
        const val = genExpr(argId)
        const pushType = inferType(argId)
        let val64p = val
        const llPushType = ssTypeToLLVM(pushType)
        if (llPushType == "ptr") {
            if (pushNonOwning == 0) {
                emitIR(`  call void @ss_rc_retain(ptr ${val})`)
            }
            const cR = nextReg()
            emitIR(`  ${cR} = ptrtoint ptr ${val} to i64`)
            val64p = cR
        } else if (pushType == "double") {
            const dR = nextReg()
            emitIR(`  ${dR} = bitcast double ${val} to i64`)
            val64p = dR
        } else if (llPushType == "i64" || pushType == "i64") {
            val64p = val
        } else {
            const sR = nextReg()
            emitIR(`  ${sR} = sext i32 ${val} to i64`)
            val64p = sR
        }
        pushNonOwning = 0
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_arrayPush(ptr ${objVal}, i64 ${val64p})`); return r
    }
    if (method == "reverse") { emitIR(`  call void @ss_arrayReverse(ptr ${objVal})`); return objVal }
    if (method == "sort") { emitIR(`  call void @ss_arraySort(ptr ${objVal})`); return objVal }
    if (method == "slice") {
        const slArgs = argList.split(",")
        const slStart = genExpr(parseInt(slArgs[0]))
        const slEnd = genExpr(parseInt(slArgs[1]))
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_arraySlice(ptr ${objVal}, i32 ${slStart}, i32 ${slEnd})`); return r
    }
    if (method == "concat") {
        const otherArr = genExpr(parseInt(argList))
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_arrayConcat(ptr ${objVal}, ptr ${otherArr})`); return r
    }
    return ""
}

function genMapMethod(method: string, objVal: string, argList: string): string {
    if (method == "set") {
        const argParts = argList.split(",")
        let key = genExpr(parseInt(argParts[0]))
        const keyType = inferType(parseInt(argParts[0]))
        if (keyType == "i64") {
            const kR = nextReg()
            emitIR(`  ${kR} = inttoptr i64 ${key} to ptr`)
            key = kR
        }
        const val = genExpr(parseInt(argParts[1]))
        const valType = inferType(parseInt(argParts[1]))
        let val64 = val
        const llValType = ssTypeToLLVM(valType)
        if (llValType == "ptr") {
            emitIR(`  call void @ss_rc_retain(ptr ${val})`)
            const castR = nextReg()
            emitIR(`  ${castR} = ptrtoint ptr ${val} to i64`)
            val64 = castR
        } else if (valType == "double") {
            const dR = nextReg()
            emitIR(`  ${dR} = bitcast double ${val} to i64`)
            val64 = dR
        } else if (llValType == "i64" || valType == "i64") {
            val64 = val
        } else {
            const sextR = nextReg()
            emitIR(`  ${sextR} = sext i32 ${val} to i64`)
            val64 = sextR
        }
        emitIR(`  call void @ss_mapSet(ptr ${objVal}, ptr ${key}, i64 ${val64})`)
        return "0"
    }
    if (method == "get" || method == "getString" || method == "has") {
        let mkey = genExpr(parseInt(argList))
        const mkeyType = inferType(parseInt(argList))
        if (mkeyType == "i64") {
            const cvR = nextReg()
            emitIR(`  ${cvR} = inttoptr i64 ${mkey} to ptr`)
            mkey = cvR
        }
        const r = nextReg()
        if (method == "has") {
            emitIR(`  ${r} = call i32 @ss_mapHas(ptr ${objVal}, ptr ${mkey})`)
        } else if (method == "getString") {
            emitIR(`  ${r} = call ptr @ss_mapGetString(ptr ${objVal}, ptr ${mkey})`)
        } else {
            emitIR(`  ${r} = call i64 @ss_mapGet(ptr ${objVal}, ptr ${mkey})`)
        }
        return r
    }
    if (method == "size") { const r = nextReg(); emitIR(`  ${r} = call i32 @ss_mapSize(ptr ${objVal})`); return r }
    if (method == "keys") { const r = nextReg(); emitIR(`  ${r} = call ptr @ss_mapKeys(ptr ${objVal})`); return r }
    if (method == "delete") { const dk = genExpr(parseInt(argList)); emitIR(`  call void @ss_mapDelete(ptr ${objVal}, ptr ${dk})`); return "0" }
    return ""
}

// ── Main method call dispatcher ──────────────────────────────

// ── Method call helpers ──────────────────────────────────────

function genStaticMethodCall(method: string, objId: int, argList: string): string {
    const className = nGetS1(objId)
    let methodClass = className
    while (methodClass != "") {
        if (funcRetTypes.has(`${methodClass}_${method}`) == 1) { break }
        if (classParents.has(methodClass) == 1) { methodClass = classParents.getString(methodClass) }
        else { methodClass = className; break }
    }
    const isMathClass = className == "Math" ? 1 : 0
    let args = ""
    if (argList != "") {
        const argParts = argList.split(",")
        let first = 1
        for (ap in argParts) {
            const argId = parseInt(ap)
            if (argId > 0) {
                let aVal = genExpr(argId)
                let aType = inferType(argId)
                if (isMathClass == 1 && (aType == "int" || aType == "auto")) {
                    const cvR = nextReg()
                    emitIR(`  ${cvR} = sitofp i32 ${aVal} to double`)
                    aVal = cvR
                    aType = "double"
                }
                if (first == 1) { first = 0 } else { args = `${args}, ` }
                args = `${args}${ssTypeToLLVM(aType)} ${aVal}`
            }
        }
    }
    let resolved = `${methodClass}_${method}`
    if (isOverloaded(resolved) == 1) {
        const sig = argsSig(argList)
        if (sig != "" && funcRetTypes.has(`${resolved}_${sig}`) == 1) {
            resolved = `${resolved}_${sig}`
        }
    }
    const rtName = runtimeName(resolved)
    let retType = "ptr"
    if (funcRetTypes.has(resolved) == 1) {
        retType = ssTypeToLLVM(funcRetTypes.getString(resolved))
    }
    if (retType == "void") {
        emitIR(`  call void @${rtName}(${args})`)
        return "0"
    }
    const r = nextReg()
    emitIR(`  ${r} = call ${retType} @${rtName}(${args})`)
    return r
}

function genLengthMethod(objVal: string, objType: string): string {
    const r = nextReg()
    if (objType == "ptr" || objType == "i64" || objType.contains("Array") == 1) {
        emitIR(`  ${r} = call i32 @ss_arrayLen(ptr ${objVal})`)
    } else {
        emitIR(`  ${r} = call i32 @ss_stringLength(ptr ${objVal})`)
    }
    return r
}

function genIndexOfMethod(objVal: string, argList: string): string {
    const argId = parseInt(argList)
    const argType = inferType(argId)
    const sub = genExpr(argId)
    if (argType == "int" || argType == "i64" || argType == "double") {
        let val64 = sub
        if (argType == "int") {
            const sR = nextReg()
            emitIR(`  ${sR} = sext i32 ${sub} to i64`)
            val64 = sR
        }
        const r = nextReg(); emitIR(`  ${r} = call i32 @ss_arrayIndexOf(ptr ${objVal}, i64 ${val64})`); return r
    }
    const r = nextReg(); emitIR(`  ${r} = call i32 @ss_indexOf(ptr ${objVal}, ptr ${sub})`); return r
}

function genMethodCall(id: int): string {
    const method = nGetS1(id)
    const objId = nGetI1(id)
    const argList = nGetList(id)

    // Static method: ClassName.method()
    if (nGetKind(objId) == "IDENT" && getVarType(nGetS1(objId)) == "" && classFields.has(nGetS1(objId)) == 1) {
        return genStaticMethodCall(method, objId, argList)
    }

    let objVal = genExpr(objId)
    const objType = inferType(objId)
    if (objType == "i64") {
        const castR = nextReg()
        emitIR(`  ${castR} = inttoptr i64 ${objVal} to ptr`)
        objVal = castR
    }

    const objClass = resolveObjClass(objId)

    // User class method: walk parent chain
    if (objClass != "" && objClass != "Map" && classHasMethod(objClass, method) == 1) {
        return emitClassMethodCall(objClass, method, objVal, argList, 0)
    }

    // Type-dependent dispatch
    if (method == "length") { return genLengthMethod(objVal, objType) }
    if (method == "indexOf") { return genIndexOfMethod(objVal, argList) }

    // Non-owning push check
    if (method == "push" && nGetKind(objId) == "MEMBER_ACCESS") {
        const maField = nGetS1(objId)
        const maClass = resolveObjClass(nGetI1(objId))
        if (maClass != "" && nonOwningFields.has(`${maClass}.${maField}`) == 1) {
            pushNonOwning = 1
        }
    }

    // Dispatch to category handlers
    let result = genStringMethod(method, objVal, argList)
    if (result != "") { return result }
    result = genHigherOrderMethod(method, objVal, argList)
    if (result != "") { return result }
    result = genArrayMethod(method, objVal, argList)
    if (result != "") { return result }
    result = genMapMethod(method, objVal, argList)
    if (result != "") { return result }

    // Fallback: class method
    if (objClass != "" && objClass != "Map") {
        return emitClassMethodCall(objClass, method, objVal, argList, 0)
    }

    emitIR(`  ; TODO: method call .${method}`)
    return "0"
}

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

// Arrow functions compile to top-level define blocks (like Zig fn pointers)
// The function pointer is a ptr, stored as i64 in SS's uniform value system
let arrowCount = 0
let arrowDefs = ""

function genArrowFunc(id: int): string {
    arrowCount = arrowCount + 1
    const fnName = `__arrow_${arrowCount}`
    let retType = nGetS2(id)
    if (retType == "") { retType = "int" }
    const llRetType = ssTypeToLLVM(retType)
    const bodyId = nGetI1(id)
    const paramList = nGetList(id)
    funcRetTypes.set(fnName, retType)

    // Build param string
    let paramStr = ""
    if (paramList != "") {
        const parts = paramList.split(",")
        let idx = 0
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0) {
                if (idx > 0) { paramStr = `${paramStr}, ` }
                paramStr = `${paramStr}${ssTypeToLLVM(nGetS2(pId))} %${nGetS1(pId)}.arg`
                idx = idx + 1
            }
        }
    }

    // Save state
    const savedFunc = currentFunc
    const savedReg = regCount
    const savedTerm = terminated
    const savedAliases = varAliases
    const savedIrOut = irOutFile

    // Generate body into buffer; string constants still go to main .str
    currentFunc = fnName
    regCount = 0
    terminated = 0
    varAliases = Map()
    if (irOutFile != "") { strOutFile = irOutFile }
    irOutFile = ""
    irBuf = ""

    emitIR(`define ${llRetType} @${fnName}(${paramStr}) {`)
    emitIR("entry:")
    emitParamAllocas(paramList, 1)
    genBlock(bodyId)
    if (terminated == 0) {
        if (llRetType == "void") { emitIR("  ret void") }
        else if (llRetType == "ptr") { emitIR(`  ret ptr ${addStringConst("")}`) }
        else { emitIR(`  ret ${llRetType} 0`) }
    }
    emitIR("}")
    emitIR("")
    arrowDefs = `${arrowDefs}${irBuf}`

    // Restore state
    irBuf = ""
    irOutFile = savedIrOut
    strOutFile = ""
    currentFunc = savedFunc
    regCount = savedReg
    terminated = savedTerm
    varAliases = savedAliases

    // Return function pointer as ptr (ptrtoint to i64 for SS's value system)
    const r = nextReg()
    emitIR(`  ${r} = ptrtoint ptr @${fnName} to i64`)
    return r
}

function flushArrowDefs() {
    if (arrowDefs != "") {
        emitIR(arrowDefs)
        arrowDefs = ""
    }
}

function genArrayLit(id: int): string {
    const elemList = nGetList(id)

    // Check if any spread elements exist + detect ptr elements
    let hasSpread = 0
    let hasPtrElem = 0
    if (elemList != "") {
        const chkParts = elemList.split(",")
        for (cp in chkParts) {
            const cid = parseInt(cp)
            if (cid > 0) {
                if (nGetKind(cid) == "SPREAD_ELEM") { hasSpread = 1 }
                const eType = inferType(cid)
                const eLLType = ssTypeToLLVM(eType)
                if (eLLType == "ptr") { hasPtrElem = 1 }
            }
        }
    }

    // Choose array constructor based on element type
    let arrCtor = "@ss_newArray"
    if (hasPtrElem == 1) { arrCtor = "@ss_newArrayPtr" }

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

function genTernary(id: int): string {
    const vType = inferType(nGetI2(id))
    const llType = ssTypeToLLVM(vType)

    // Use alloca+store+load instead of phi to handle nested ternaries
    const resultAlloca = nextReg()
    emitIR(`  ${resultAlloca} = alloca ${llType}, align 8`)

    const condVal = genExpr(nGetI1(id))
    const thenLabel = nextLabel("tern.then")
    const elseLabel = nextLabel("tern.else")
    const mergeLabel = nextLabel("tern.merge")

    const cmp = nextReg()
    emitIR(`  ${cmp} = icmp ne i32 ${condVal}, 0`)
    emitIR(`  br i1 ${cmp}, label %${thenLabel}, label %${elseLabel}`)

    emitIR(`${thenLabel}:`)
    const thenVal = genExpr(nGetI2(id))
    emitIR(`  store ${llType} ${thenVal}, ptr ${resultAlloca}, align 8`)
    emitIR(`  br label %${mergeLabel}`)

    emitIR(`${elseLabel}:`)
    const elseVal = genExpr(nGetI3(id))
    emitIR(`  store ${llType} ${elseVal}, ptr ${resultAlloca}, align 8`)
    emitIR(`  br label %${mergeLabel}`)

    emitIR(`${mergeLabel}:`)
    const result = nextReg()
    emitIR(`  ${result} = load ${llType}, ptr ${resultAlloca}, align 8`)
    return result
}

// Convert any expression to string for println
// Sets lastExprStringOwned: 1 if result is newly allocated (conversion), 0 if borrowed
function genExprAsString(id: int): string {
    const vType = inferType(id)
    const llType = ssTypeToLLVM(vType)
    // String or class instance (exclude generic types like Array<string>)
    if (vType == "string" || (llType == "ptr" && vType != "ptr" && vType.contains("<") == 0)) {
        const sVal = genExpr(id)
        // If the actual LLVM value is i64 (e.g., from untyped array), inttoptr
        const sNodeKind = nGetKind(id)
        if (sNodeKind == "IDENT" && getVarType(nGetS1(id)) == "i64") {
            const castR = nextReg()
            emitIR(`  ${castR} = inttoptr i64 ${sVal} to ptr`)
            lastExprStringOwned = 0
            return castR
        }
        lastExprStringOwned = 0
        return sVal
    }
    const val = genExpr(id)
    if (vType == "double") {
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_double_to_string(double ${val})`)
        lastExprStringOwned = 1
        return r
    }
    if (vType == "i64") {
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_i64_to_string(i64 ${val})`)
        lastExprStringOwned = 1
        return r
    }
    if (vType == "ptr" || vType.contains("<") == 1) {
        const castR = nextReg()
        emitIR(`  ${castR} = ptrtoint ptr ${val} to i64`)
        const r = nextReg(); emitIR(`  ${r} = call ptr @ss_i64_to_string(i64 ${castR})`)
        lastExprStringOwned = 1
        return r
    }
    const r = nextReg(); emitIR(`  ${r} = call ptr @ss_int_to_string(i32 ${val})`)
    lastExprStringOwned = 1
    return r
}

// ── Type inference ────────────────────────────────────────────

// Infer element type of an array expression (returns "string", "int", "double", or "")
function inferArrayElemType(arrId: int): string {
    if (arrId <= 0) { return "" }
    const aeKind = nGetKind(arrId)
    if (aeKind == "IDENT") {
        const aeType = getVarType(nGetS1(arrId))
        if (aeType.contains("<string>") == 1) { return "string" }
        if (aeType.contains("<int>") == 1) { return "int" }
        if (aeType.contains("<double>") == 1) { return "double" }
    }
    if (aeKind == "METHOD_CALL") {
        const aeMethod = nGetS1(arrId)
        if (aeMethod == "split") { return "string" }
        if (aeMethod == "filter" || aeMethod == "slice" || aeMethod == "reverse" || aeMethod == "sort") {
            return inferArrayElemType(nGetI1(arrId))
        }
    }
    return ""
}

// Resolve the CLASS name of an expression (returns class name or "")
function resolveObjClass(nodeId: int): string {
    if (nodeId <= 0) { return "" }
    const kind = nGetKind(nodeId)
    // Variable → check varType for class name
    if (kind == "IDENT") {
        const vt = getVarType(nGetS1(nodeId))
        if (vt != "" && classFields.has(vt) == 1) { return vt }
        const oc = getObjClass(nGetS1(nodeId))
        if (oc != "") { return oc }
        // Class name used as static method target (e.g., JSON.create())
        if (classFields.has(nGetS1(nodeId)) == 1) { return nGetS1(nodeId) }
        return ""
    }
    // this → current class
    if (kind == "THIS" && currentClassName != "") { return currentClassName }
    // new ClassName() → class name directly
    if (kind == "NEW_EXPR") { return nGetS1(nodeId) }
    // Function call → check return type
    if (kind == "CALL") {
        const callee = nGetS1(nodeId)
        if (funcRetTypes.has(callee) == 1) {
            const rt = funcRetTypes.getString(callee)
            if (classFields.has(rt) == 1) { return rt }
        }
        return ""
    }
    // Method call → recursively resolve object, then look up method return type
    if (kind == "METHOD_CALL") {
        const rt = inferType(nodeId)
        if (classFields.has(rt) == 1) { return rt }
        return ""
    }
    // Member access → resolve object class, look up field type
    if (kind == "MEMBER_ACCESS") {
        const objClass = resolveObjClass(nGetI1(nodeId))
        if (objClass != "") {
            const fType = classFieldTypes.getString(`${objClass}.${nGetS1(nodeId)}`)
            if (fType != "" && classFields.has(fType) == 1) { return fType }
        }
        return ""
    }
    return ""
}

function inferType(id: int): string {
    if (id <= 0) { return "int" }
    const kind = nGetKind(id)
    if (kind == "INT_LIT") { return "int" }
    if (kind == "DOUBLE_LIT") { return "double" }
    if (kind == "STRING_LIT") { return "string" }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT") { return "int" }
    if (kind == "NULL_LIT") { return "ptr" }
    if (kind == "TEMPLATE_LIT") { return "string" }
    if (kind == "THIS") {
        if (currentClassName != "") { return currentClassName }
        return "ptr"
    }
    if (kind == "IDENT") {
        const vType = getVarType(nGetS1(id))
        if (vType != "") { return vType }
        if (funcRetTypes.has(nGetS1(id)) == 1) { return "fn" }
        return "int"
    }
    if (kind == "BINARY") {
        const op = nGetS1(id)
        if (op == "Add") {
            const blt2 = inferType(nGetI1(id))
            if (blt2 == "string") { return "string" }
            const brt2 = inferType(nGetI2(id))
            if (brt2 == "string") { return "string" }
        }
        if (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge" || op == "And" || op == "Or") {
            return "int"
        }
        const binLt = inferType(nGetI1(id))
        const binRt = inferType(nGetI2(id))
        if (binLt == "double" || binRt == "double") { return "double" }
        if (binLt == "i64") { return "int" }
        return binLt
    }
    if (kind == "CALL") {
        const callee = nGetS1(id)
        if (callee == "Map") { return "Map" }
        if (getVarType(callee) == "fn" || getVarType(callee) == "i64") { return "i64" }
        // Use funcRetTypes directly — preserves class names
        if (funcRetTypes.has(callee) == 1) {
            return funcRetTypes.getString(callee)
        }
        return callReturnType(callee)
    }
    if (kind == "NEW_EXPR") { return nGetS1(id) }
    if (kind == "METHOD_CALL") {
        const method = nGetS1(id)
        // Resolve object type FIRST via unified inferType (recursive)
        const objType = resolveObjClass(nGetI1(id))
        // If object is a known class, look up method return type in class chain
        if (objType != "" && objType != "string" && objType != "int" && objType != "double") {
            let lookupClass = objType
            while (lookupClass != "") {
                if (funcRetTypes.has(`${lookupClass}_${method}`) == 1) {
                    return funcRetTypes.getString(`${lookupClass}_${method}`)
                }
                if (classParents.has(lookupClass) == 1) {
                    lookupClass = classParents.getString(lookupClass)
                } else {
                    lookupClass = ""
                }
            }
        }
        // Built-in method return types (fallback for string/array/map methods)
        if (methodRetTypes.has(method) == 1) {
            return methodRetTypes.getString(method)
        }
        return "int"
    }
    if (kind == "MEMBER_ACCESS") {
        const mField = nGetS1(id)
        const mObj = nGetI1(id)
        let maClassName = resolveObjClass(mObj)
        if (maClassName != "" && classFieldTypes.has(`${maClassName}.${mField}`) == 1) {
            return classFieldTypes.getString(`${maClassName}.${mField}`)
        }
        return "int"
    }
    if (kind == "GROUPING") { return inferType(nGetI1(id)) }
    if (kind == "UNARY") { return inferType(nGetI1(id)) }
    if (kind == "TERNARY") { return inferType(nGetI2(id)) }
    if (kind == "ARRAY_LIT") { return "ptr" }
    if (kind == "ARROW_FUNC") { return "fn" }
    if (kind == "INDEX_ACCESS") {
        const iaElem = inferArrayElemType(nGetI1(id))
        if (iaElem != "") { return iaElem }
        return "i64"
    }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { return "int" }
    if (kind == "SPREAD_ELEM") { return inferType(nGetI1(id)) }
    return "int"
}

function preludeName(cName: string): string {
    const pName = `_${cName}`
    if (funcRetTypes.has(pName) == 1) { return pName }
    return cName
}

function callReturnType(callee: string): string {
    if (funcRetTypes.has(callee) == 1) {
        return funcRetTypes.getString(callee)
    }
    return "int"
}

// ── Type helpers ──────────────────────────────────────────────

function ssTypeToLLVM(t: string): string {
    if (t == "int" || t == "bool" || t == "auto" || t == "") { return "i32" }
    if (t == "double") { return "double" }
    if (t == "string") { return "ptr" }
    if (t == "void") { return "void" }
    if (t == "ptr") { return "ptr" }
    if (t == "fn") { return "i64" }
    if (t == "i64") { return "i64" }
    // Generic types (Array<string>, Map<string,int>, etc.) → ptr
    if (t.contains("<") == 1) { return "ptr" }
    // Class type names → ptr (includes Map, registered as built-in class)
    if (classFields.has(t) == 1) { return "ptr" }
    // Generic type params (single uppercase letter like T, U, V) → ptr (erased)
    if (t.length() == 1 && charCodeAt(t, 0) >= 65 && charCodeAt(t, 0) <= 90) { return "ptr" }
    return "i32"
}

function setVarType(name: string, varType: string) {
    varTypes.set(`${currentFunc}:${name}`, varType)
}

function getVarType(name: string): string {
    const scopedKey = `${currentFunc}:${name}`
    if (varTypes.has(scopedKey) == 1) {
        return varTypes.getString(scopedKey)
    }
    const globalKey = `:${name}`
    if (varTypes.has(globalKey) == 1) {
        return varTypes.getString(globalKey)
    }
    return ""
}

// ── Method overloading: type signature ───────────────────────

function typeSig(ssType: string): string {
    if (ssType == "int" || ssType == "bool" || ssType == "auto" || ssType == "") { return "i" }
    if (ssType == "double") { return "d" }
    if (ssType == "string") { return "s" }
    if (ssType == "fn") { return "f" }
    if (ssType == "void") { return "v" }
    if (ssType.contains("<") == 1) { return "p" }
    // Class name → use full name
    return ssType
}

function paramSig(paramList: string): string {
    if (paramList == "") { return "" }
    let sig = ""
    const parts = paramList.split(",")
    for (p in parts) {
        const pId = parseInt(p)
        if (pId > 0 && nGetKind(pId) == "PARAM") {
            if (sig != "") { sig = `${sig}_` }
            sig = `${sig}${typeSig(nGetS2(pId))}`
        }
    }
    return sig
}

function argsSig(argList: string): string {
    if (argList == "") { return "" }
    let sig = ""
    const parts = argList.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0) {
            const aType = inferType(argId)
            if (sig != "") { sig = `${sig}_` }
            // For IDENT with class type, use class name
            if (nGetKind(argId) == "IDENT") {
                const objClass = getObjClass(nGetS1(argId))
                if (objClass != "") {
                    sig = `${sig}${objClass}`
                    continue
                }
            }
            if (nGetKind(argId) == "NEW_EXPR") {
                sig = `${sig}${nGetS1(argId)}`
                continue
            }
            sig = `${sig}${typeSig(aType)}`
        }
    }
    return sig
}

function resolveOverload(baseName: string, argList: string): string {
    // Only resolve overloads for functions with multiple signatures
    if (overloadReady == 0) { return baseName }
    if (overloadCount.has(baseName) == 0) { return baseName }
    if (parseInt(overloadCount.getString(baseName)) <= 1) { return baseName }
    // This function IS overloaded — find the right signature
    const sig = argsSig(argList)
    if (sig != "") {
        const mangled = `${baseName}_${sig}`
        if (funcRetTypes.has(mangled) == 1) { return mangled }
    }
    return baseName
}
