// Expression generation + type helpers for bootstrap codegen
// ── Expression generation ─────────────────────────────────────
// Returns the SSA register or constant string holding the result.

function genExpr(id: int): string {
    if (id <= 0) { return "0" }
    const kind = nGetKind(id)

    if (kind == "INT_LIT") {
        return nGetS1(id)
    }
    if (kind == "DOUBLE_LIT") { return nGetS1(id) }
    if (kind == "STRING_LIT") {
        const name = addStringConst(nGetS1(id))
        return name
    }
    if (kind == "TRUE_LIT") { return "1" }
    if (kind == "FALSE_LIT") { return "0" }

    if (kind == "IDENT") {
        const name = nGetS1(id)
        const vType = getVarType(name)
        const r = nextReg()
        emitIR("  " + r + " = load " + ssTypeToLLVM(vType) + ", ptr " + varRef(name) + ", align 8")
        return r
    }

    if (kind == "BINARY") {
        return genBinary(id)
    }

    if (kind == "UNARY") {
        const op = nGetS1(id)
        const val = genExpr(nGetI1(id))
        const r = nextReg()
        if (op == "Neg") {
            const uType = inferType(nGetI1(id))
            if (uType == "double") {
                emitIR("  " + r + " = fsub double 0.0, " + val)
            } else {
                emitIR("  " + r + " = sub i32 0, " + val)
            }
        } else {
            emitIR("  " + r + " = icmp eq i32 " + val + ", 0")
            const r2 = nextReg()
            emitIR("  " + r2 + " = zext i1 " + r + " to i32")
            return r2
        }
        return r
    }

    if (kind == "CALL") {
        return genCall(id)
    }

    if (kind == "METHOD_CALL") {
        return genMethodCall(id)
    }

    if (kind == "MEMBER_ACCESS") {
        return genMemberAccess(id)
    }

    if (kind == "NEW_EXPR") {
        return genNewExpr(id)
    }

    if (kind == "GROUPING") {
        return genExpr(nGetI1(id))
    }

    if (kind == "TERNARY") {
        return genTernary(id)
    }

    if (kind == "TEMPLATE_LIT") {
        return genTemplateLit(id)
    }

    if (kind == "ARRAY_LIT") {
        return genArrayLit(id)
    }

    if (kind == "INDEX_ACCESS") {
        let arrVal = genExpr(nGetI1(id))
        // If array var is i64 (from for-in), inttoptr
        const arrType = inferType(nGetI1(id))
        if (arrType == "i64") {
            const cvtR = nextReg()
            emitIR("  " + cvtR + " = inttoptr i64 " + arrVal + " to ptr")
            arrVal = cvtR
        }
        const idxVal = genExpr(nGetI2(id))
        const r = nextReg()
        emitIR("  " + r + " = call i64 @ym_arrayGet(ptr " + arrVal + ", i32 " + idxVal + ")")
        return r
    }

    if (kind == "POSTFIX_INC") {
        const pieRef = varRef(nGetS1(id))
        const r1 = nextReg()
        emitIR("  " + r1 + " = load i32, ptr " + pieRef + ", align 4")
        const r2 = nextReg()
        emitIR("  " + r2 + " = add i32 " + r1 + ", 1")
        emitIR("  store i32 " + r2 + ", ptr " + pieRef + ", align 4")
        return r1
    }

    return "0"
}

function genBinary(id: int): string {
    const op = nGetS1(id)
    const leftId = nGetI1(id)
    const rightId = nGetI2(id)

    const blt = inferType(leftId)
    const brt = inferType(rightId)

    // String concatenation
    if (op == "Add" && (blt == "string" || brt == "string" || blt == "i64" || brt == "i64")) {
        // Check if at least one side is actually string
        if (blt == "string" || brt == "string") {
            const l = genExprAsString(leftId)
            const rVal = genExprAsString(rightId)
            const r = nextReg()
            emitIR("  " + r + " = call ptr @ym_string_concat(ptr " + l + ", ptr " + rVal + ")")
            return r
        }
    }

    // String equality
    if ((op == "Eq" || op == "Ne") && (blt == "string" || brt == "string")) {
        let l = genExpr(leftId)
        let rVal = genExpr(rightId)
        // Convert i64 to ptr if needed
        if (blt == "i64") {
            const cvR = nextReg()
            emitIR("  " + cvR + " = inttoptr i64 " + l + " to ptr")
            l = cvR
        }
        if (brt == "i64") {
            const cvR = nextReg()
            emitIR("  " + cvR + " = inttoptr i64 " + rVal + " to ptr")
            rVal = cvR
        }
        const r = nextReg()
        if (op == "Eq") {
            emitIR("  " + r + " = call i32 @ym_string_eq(ptr " + l + ", ptr " + rVal + ")")
        } else {
            emitIR("  " + r + " = call i32 @ym_string_ne(ptr " + l + ", ptr " + rVal + ")")
        }
        return r
    }

    // Short-circuit && and ||
    // Short-circuit && and ||
    if (op == "And" || op == "Or") {
        const scResult = nextReg()
        emitIR("  " + scResult + " = alloca i32, align 4")
        const scLeft = genExpr(leftId)
        emitIR("  store i32 " + scLeft + ", ptr " + scResult + ", align 4")
        const scCmp = nextReg()
        emitIR("  " + scCmp + " = icmp ne i32 " + scLeft + ", 0")
        const scRhs = nextLabel("sc.rhs")
        const scEnd = nextLabel("sc.end")
        // And: eval rhs if left is true; Or: eval rhs if left is false
        if (op == "And") { emitIR("  br i1 " + scCmp + ", label %" + scRhs + ", label %" + scEnd) } else { emitIR("  br i1 " + scCmp + ", label %" + scEnd + ", label %" + scRhs) }
        emitIR(scRhs + ":")
        const scRight = genExpr(rightId)
        emitIR("  store i32 " + scRight + ", ptr " + scResult + ", align 4")
        emitIR("  br label %" + scEnd)
        emitIR(scEnd + ":")
        const scRes = nextReg()
        emitIR("  " + scRes + " = load i32, ptr " + scResult + ", align 4")
        return scRes
    }

    let left = genExpr(leftId)
    let right = genExpr(rightId)

    // Normalize i64 operands to i32 for integer arithmetic
    if (blt == "i64" && brt != "i64") {
        const trR = nextReg()
        emitIR("  " + trR + " = trunc i64 " + left + " to i32")
        left = trR
    }
    if (brt == "i64" && blt != "i64") {
        const trR = nextReg()
        emitIR("  " + trR + " = trunc i64 " + right + " to i32")
        right = trR
    }
    if (blt == "i64" && brt == "i64") {
        const trL = nextReg()
        emitIR("  " + trL + " = trunc i64 " + left + " to i32")
        left = trL
        const trR = nextReg()
        emitIR("  " + trR + " = trunc i64 " + right + " to i32")
        right = trR
    }

    if (blt == "double" || brt == "double") {
        // Convert int operand to double if needed
        if (blt != "double") {
            const cvtR = nextReg()
            emitIR("  " + cvtR + " = sitofp i32 " + left + " to double")
            left = cvtR
        }
        if (brt != "double") {
            const cvtR = nextReg()
            emitIR("  " + cvtR + " = sitofp i32 " + right + " to double")
            right = cvtR
        }
        const r = nextReg()
        if (op == "Add") { emitIR("  " + r + " = fadd double " + left + ", " + right); return r }
        if (op == "Sub") { emitIR("  " + r + " = fsub double " + left + ", " + right); return r }
        if (op == "Mul") { emitIR("  " + r + " = fmul double " + left + ", " + right); return r }
        if (op == "Div") { emitIR("  " + r + " = fdiv double " + left + ", " + right); return r }
        if (op == "Mod") { emitIR("  " + r + " = frem double " + left + ", " + right); return r }
        // Float comparison
        let fcmpOp = ""
        if (op == "Eq") { fcmpOp = "oeq" }
        if (op == "Ne") { fcmpOp = "one" }
        if (op == "Lt") { fcmpOp = "olt" }
        if (op == "Gt") { fcmpOp = "ogt" }
        if (op == "Le") { fcmpOp = "ole" }
        if (op == "Ge") { fcmpOp = "oge" }
        if (fcmpOp != "") {
            emitIR("  " + r + " = fcmp " + fcmpOp + " double " + left + ", " + right)
            const r2 = nextReg()
            emitIR("  " + r2 + " = zext i1 " + r + " to i32")
            return r2
        }
    }
    const r = nextReg()
    if (op == "Add") { emitIR("  " + r + " = add i32 " + left + ", " + right); return r }
    if (op == "Sub") { emitIR("  " + r + " = sub i32 " + left + ", " + right); return r }
    if (op == "Mul") { emitIR("  " + r + " = mul i32 " + left + ", " + right); return r }
    if (op == "Div") { emitIR("  " + r + " = sdiv i32 " + left + ", " + right); return r }
    if (op == "Mod") { emitIR("  " + r + " = srem i32 " + left + ", " + right); return r }
    // And/Or handled above with short-circuit
    // Integer comparison
    let cmpOp = ""
    if (op == "Eq") { cmpOp = "eq" }
    if (op == "Ne") { cmpOp = "ne" }
    if (op == "Lt") { cmpOp = "slt" }
    if (op == "Gt") { cmpOp = "sgt" }
    if (op == "Le") { cmpOp = "sle" }
    if (op == "Ge") { cmpOp = "sge" }
    if (cmpOp != "") {
        emitIR("  " + r + " = icmp " + cmpOp + " i32 " + left + ", " + right)
        const r2 = nextReg()
        emitIR("  " + r2 + " = zext i1 " + r + " to i32")
        return r2
    }
    emitIR("  ; unknown binary op: " + op)
    return r
}

function genCall(id: int): string {
    const callee = nGetS1(id)
    const rtName = runtimeName(callee)
    const argList = nGetList(id)

    // Special case: println with auto-conversion
    if (callee == "println" || callee == "print") {
        const fnName = runtimeName(callee)
        if (argList == "") {
            const emptyStr = addStringConst("")
            emitIR("  call void @" + fnName + "(ptr " + emptyStr + ")")
            return "0"
        }
        // Build concatenated string from all args
        let result = ""
        const parts = argList.split(",")
        let first = 1
        for (p in parts) {
            const argId = parseInt(p)
            if (argId > 0) {
                const argStr = genExprAsString(argId)
                if (first == 1) {
                    result = argStr
                    first = 0
                } else {
                    const space = addStringConst(" ")
                    const r1 = nextReg()
                    emitIR("  " + r1 + " = call ptr @ym_string_concat(ptr " + result + ", ptr " + space + ")")
                    const r2 = nextReg()
                    emitIR("  " + r2 + " = call ptr @ym_string_concat(ptr " + r1 + ", ptr " + argStr + ")")
                    result = r2
                }
            }
        }
        emitIR("  call void @" + fnName + "(ptr " + result + ")")
        return "0"
    }

    // General function call
    const expectsDouble = callReturnType(callee) == "double"
    // Collect provided args
    let providedArgs = ""
    let providedCount = 0
    if (argList != "") {
        const parts = argList.split(",")
        for (p in parts) {
            const argId = parseInt(p)
            if (argId > 0) {
                if (providedArgs == "") { providedArgs = argId + "" } else { providedArgs = providedArgs + "," + argId }
                providedCount = providedCount + 1
            }
        }
    }
    // Check if we need to fill in defaults
    let expectedCount = providedCount
    if (funcParamCount.has(callee) == 1) {
        expectedCount = parseInt(funcParamCount.getString(callee))
    }
    // Append defaults for missing args
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
                    if (fullArgs == "") { fullArgs = defNodeId } else { fullArgs = fullArgs + "," + defNodeId }
                }
            }
        }
    }
    // Generate args
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
                    emitIR("  " + cvR + " = sitofp i32 " + val + " to double")
                    val = cvR
                    vType = "double"
                }
                const llType = ssTypeToLLVM(vType)
                if (first == 1) { first = 0 } else { args = args + ", " }
                args = args + llType + " " + val
            }
        }
    }

    // Determine return type
    const retType = callReturnType(callee)
    const llRetType = ssTypeToLLVM(retType)

    if (llRetType == "void") {
        emitIR("  call void @" + rtName + "(" + args + ")")
        return "0"
    }
    const r = nextReg()
    emitIR("  " + r + " = call " + llRetType + " @" + rtName + "(" + args + ")")
    return r
}

function genMethodCall(id: int): string {
    const method = nGetS1(id)
    const objId = nGetI1(id)
    const argList = nGetList(id)

    let objVal = genExpr(objId)
    // If object is i64 (e.g., from for-in or Map.get), convert to ptr for string/array methods
    const objType = inferType(objId)
    if (objType == "i64") {
        const castR = nextReg()
        emitIR("  " + castR + " = inttoptr i64 " + objVal + " to ptr")
        objVal = castR
    }

    // String methods
    if (method == "length") {
        const r = nextReg()
        // Heuristic: if object is from split/newArray (ptr type), use arrayLen
        const origType = inferType(objId)
        if (origType == "ptr" || origType == "i64") {
            emitIR("  " + r + " = call i32 @ym_arrayLen(ptr " + objVal + ")")
        } else {
            emitIR("  " + r + " = call i32 @ym_stringLength(ptr " + objVal + ")")
        }
        return r
    }
    // Single i32-arg methods: charAt(ptr→ptr), charCodeAt(ptr→i32), repeat(ptr→ptr)
    if (method == "charAt" || method == "charCodeAt" || method == "repeat") {
        const av = genExpr(parseInt(argList))
        let retT = "ptr"
        if (method == "charCodeAt") { retT = "i32" }
        const r = nextReg()
        emitIR("  " + r + " = call " + retT + " @ym_" + method + "(ptr " + objVal + ", i32 " + av + ")")
        return r
    }
    if (method == "indexOf") {
        const argId = parseInt(argList)
        const argType = inferType(argId)
        const sub = genExpr(argId)
        if (argType == "int" || argType == "i64" || argType == "double") {
            let val64 = sub
            if (argType == "int") {
                const sR = nextReg()
                emitIR("  " + sR + " = sext i32 " + sub + " to i64")
                val64 = sR
            }
            const r = nextReg()
            emitIR("  " + r + " = call i32 @ym_arrayIndexOf(ptr " + objVal + ", i64 " + val64 + ")")
            return r
        }
        const r = nextReg()
        emitIR("  " + r + " = call i32 @ym_indexOf(ptr " + objVal + ", ptr " + sub + ")")
        return r
    }
    if (method == "substring") {
        const argParts = argList.split(",")
        const startVal = genExpr(parseInt(argParts[0]))
        const lenVal = genExpr(parseInt(argParts[1]))
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_substring(ptr " + objVal + ", i32 " + startVal + ", i32 " + lenVal + ")")
        return r
    }
    // Single ptr-arg bool methods → call i32 @ym_XXX(ptr, ptr)
    if (method == "contains" || method == "startsWith" || method == "endsWith") {
        const sub = genExpr(parseInt(argList))
        const r = nextReg()
        emitIR("  " + r + " = call i32 @ym_" + method + "(ptr " + objVal + ", ptr " + sub + ")")
        return r
    }
    if (method == "replace") {
        const argParts = argList.split(",")
        const oldVal = genExpr(parseInt(argParts[0]))
        const newVal = genExpr(parseInt(argParts[1]))
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_replace(ptr " + objVal + ", ptr " + oldVal + ", ptr " + newVal + ")")
        return r
    }
    // Single ptr-arg string methods → call ptr @ym_XXX(ptr, ptr)
    if (method == "split" || method == "join") {
        const delim = genExpr(parseInt(argList))
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_" + method + "(ptr " + objVal + ", ptr " + delim + ")")
        return r
    }
    // No-arg string methods → call ptr @ym_XXX(ptr obj)
    if (method == "trim" || method == "toUpperCase" || method == "toLowerCase") {
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_" + method + "(ptr " + objVal + ")")
        return r
    }
    // Two-arg pad methods → call ptr @ym_XXX(ptr obj, i32 width, ptr pad)
    if (method == "padStart" || method == "padEnd") {
        const ap = argList.split(",")
        const w = genExpr(parseInt(ap[0]))
        const p = genExpr(parseInt(ap[1]))
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_" + method + "(ptr " + objVal + ", i32 " + w + ", ptr " + p + ")")
        return r
    }
    // Array methods
    if (method == "push") {
        const argId = parseInt(argList)
        const val = genExpr(argId)
        const pushType = inferType(argId)
        let val64p = val
        if (pushType == "int" || pushType == "auto" || pushType == "") {
            const sR = nextReg()
            emitIR("  " + sR + " = sext i32 " + val + " to i64")
            val64p = sR
        }
        if (pushType == "string" || pushType == "ptr") {
            const cR = nextReg()
            emitIR("  " + cR + " = ptrtoint ptr " + val + " to i64")
            val64p = cR
        }
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_arrayPush(ptr " + objVal + ", i64 " + val64p + ")")
        return r
    }
    // Map methods
    if (method == "set") {
        const argParts = argList.split(",")
        let key = genExpr(parseInt(argParts[0]))
        // Ensure key is ptr (might be i64 from for-in)
        const keyType = inferType(parseInt(argParts[0]))
        if (keyType == "i64") {
            const kR = nextReg()
            emitIR("  " + kR + " = inttoptr i64 " + key + " to ptr")
            key = kR
        }
        const val = genExpr(parseInt(argParts[1]))
        const valType = inferType(parseInt(argParts[1]))
        let val64 = val
        if (valType == "int" || valType == "auto" || valType == "") {
            const sextR = nextReg()
            emitIR("  " + sextR + " = sext i32 " + val + " to i64")
            val64 = sextR
        }
        if (valType == "string" || valType == "ptr") {
            const castR = nextReg()
            emitIR("  " + castR + " = ptrtoint ptr " + val + " to i64")
            val64 = castR
        }
        emitIR("  call void @ym_mapSet(ptr " + objVal + ", ptr " + key + ", i64 " + val64 + ")")
        return "0"
    }
    if (method == "get") {
        const argId = parseInt(argList)
        const key = genExpr(argId)
        const r = nextReg()
        emitIR("  " + r + " = call i64 @ym_mapGet(ptr " + objVal + ", ptr " + key + ")")
        return r
    }
    if (method == "getString") {
        const argId = parseInt(argList)
        const key = genExpr(argId)
        const r = nextReg()
        emitIR("  " + r + " = call i64 @ym_mapGet(ptr " + objVal + ", ptr " + key + ")")
        // Cast i64 to ptr (reinterpret)
        const r2 = nextReg()
        emitIR("  " + r2 + " = inttoptr i64 " + r + " to ptr")
        return r2
    }
    if (method == "has") {
        const argId = parseInt(argList)
        const key = genExpr(argId)
        const r = nextReg()
        emitIR("  " + r + " = call i32 @ym_mapHas(ptr " + objVal + ", ptr " + key + ")")
        return r
    }
    // No-arg Map/Array methods
    if (method == "size") { const r = nextReg(); emitIR("  " + r + " = call i32 @ym_mapSize(ptr " + objVal + ")"); return r }
    if (method == "keys") { const r = nextReg(); emitIR("  " + r + " = call ptr @ym_mapKeys(ptr " + objVal + ")"); return r }
    if (method == "delete") { const dk = genExpr(parseInt(argList)); emitIR("  call void @ym_mapDelete(ptr " + objVal + ", ptr " + dk + ")"); return "0" }
    if (method == "reverse") { emitIR("  call void @ym_arrayReverse(ptr " + objVal + ")"); return objVal }
    if (method == "sort") { emitIR("  call void @ym_arraySort(ptr " + objVal + ")"); return objVal }
    if (method == "slice") {
        const slArgs = argList.split(",")
        const slStart = genExpr(parseInt(slArgs[0]))
        const slEnd = genExpr(parseInt(slArgs[1]))
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_arraySlice(ptr " + objVal + ", i32 " + slStart + ", i32 " + slEnd + ")")
        return r
    }
    if (method == "concat") {
        const otherArr = genExpr(parseInt(argList))
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_arrayConcat(ptr " + objVal + ", ptr " + otherArr + ")")
        return r
    }

    // Class method call: obj.method(args) → ClassName_method(obj, args)
    const objId2 = nGetI1(id)
    let className = ""
    if (nGetKind(objId2) == "IDENT") {
        className = getObjClass(nGetS1(objId2))
    }
    if (nGetKind(objId2) == "THIS" && currentClassName != "") {
        className = currentClassName
    }
    if (className != "" && className != "Map") {
        // Find actual class that has this method (walk parent chain)
        let methodClass = className
        while (methodClass != "") {
            if (funcRetTypes.has(methodClass + "_" + method) == 1) { break }
            if (classParents.has(methodClass) == 1) {
                methodClass = classParents.getString(methodClass)
            } else {
                methodClass = className
                break
            }
        }
        let callArgs = "ptr " + objVal
        if (argList != "") {
            const argParts = argList.split(",")
            for (ap in argParts) {
                const argId = parseInt(ap)
                if (argId > 0) {
                    const aVal = genExpr(argId)
                    const aType = inferType(argId)
                    callArgs = callArgs + ", " + ssTypeToLLVM(aType) + " " + aVal
                }
            }
        }
        let mRetType = "ptr"
        if (funcRetTypes.has(methodClass + "_" + method) == 1) {
            mRetType = ssTypeToLLVM(funcRetTypes.getString(methodClass + "_" + method))
        }
        if (mRetType == "void") {
            emitIR("  call void @" + methodClass + "_" + method + "(" + callArgs + ")")
            return "0"
        }
        const cr = nextReg()
        emitIR("  " + cr + " = call " + mRetType + " @" + methodClass + "_" + method + "(" + callArgs + ")")
        return cr
    }

    emitIR("  ; TODO: method call ." + method)
    return "0"
}

function genTemplateLit(id: int): string {
    const fragList = nGetList(id)
    if (fragList == "") {
        return addStringConst("")
    }
    let result = ""
    const parts = fragList.split(",")
    for (p in parts) {
        const fragId = parseInt(p)
        if (fragId > 0) {
            const fk = nGetKind(fragId)
            let fragStr = ""
            if (fk == "TMPL_FRAG_LIT") {
                fragStr = addStringConst(nGetS1(fragId))
            } else if (fk == "TMPL_FRAG_EXPR") {
                fragStr = genExprAsString(nGetI1(fragId))
            }
            if (result == "") {
                result = fragStr
            } else {
                const r = nextReg()
                emitIR("  " + r + " = call ptr @ym_string_concat(ptr " + result + ", ptr " + fragStr + ")")
                result = r
            }
        }
    }
    return result
}

function genArrayLit(id: int): string {
    const elemList = nGetList(id)
    let count = 0
    if (elemList != "") {
        const parts = elemList.split(",")
        for (p in parts) {
            count = count + 1
        }
    }
    const arrReg = nextReg()
    emitIR("  " + arrReg + " = call ptr @ym_newArray(i32 " + count + ")")

    if (elemList != "") {
        let idx = 0
        const parts = elemList.split(",")
        for (p in parts) {
            const elemId = parseInt(p)
            if (elemId > 0) {
                const val = genExpr(elemId)
                const vType = inferType(elemId)
                if (vType == "string") {
                    const castReg = nextReg()
                    emitIR("  " + castReg + " = ptrtoint ptr " + val + " to i64")
                    emitIR("  call void @ym_arraySet(ptr " + arrReg + ", i32 " + idx + ", i64 " + castReg + ")")
                } else {
                    const extReg = nextReg()
                    emitIR("  " + extReg + " = sext i32 " + val + " to i64")
                    emitIR("  call void @ym_arraySet(ptr " + arrReg + ", i32 " + idx + ", i64 " + extReg + ")")
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
    emitIR("  " + resultAlloca + " = alloca " + llType + ", align 8")

    const condVal = genExpr(nGetI1(id))
    const thenLabel = nextLabel("tern.then")
    const elseLabel = nextLabel("tern.else")
    const mergeLabel = nextLabel("tern.merge")

    const cmp = nextReg()
    emitIR("  " + cmp + " = icmp ne i32 " + condVal + ", 0")
    emitIR("  br i1 " + cmp + ", label %" + thenLabel + ", label %" + elseLabel)

    emitIR(thenLabel + ":")
    const thenVal = genExpr(nGetI2(id))
    emitIR("  store " + llType + " " + thenVal + ", ptr " + resultAlloca + ", align 8")
    emitIR("  br label %" + mergeLabel)

    emitIR(elseLabel + ":")
    const elseVal = genExpr(nGetI3(id))
    emitIR("  store " + llType + " " + elseVal + ", ptr " + resultAlloca + ", align 8")
    emitIR("  br label %" + mergeLabel)

    emitIR(mergeLabel + ":")
    const result = nextReg()
    emitIR("  " + result + " = load " + llType + ", ptr " + resultAlloca + ", align 8")
    return result
}

// Convert any expression to string for println
function genExprAsString(id: int): string {
    const vType = inferType(id)
    if (vType == "string") {
        const sVal = genExpr(id)
        // If the actual LLVM value is i64 (e.g., from array), inttoptr
        const sNodeKind = nGetKind(id)
        if (sNodeKind == "IDENT" && getVarType(nGetS1(id)) == "i64") {
            const castR = nextReg()
            emitIR("  " + castR + " = inttoptr i64 " + sVal + " to ptr")
            return castR
        }
        return sVal
    }
    const val = genExpr(id)
    if (vType == "double") {
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_double_to_string(double " + val + ")")
        return r
    }
    if (vType == "i64") {
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_i64_to_string(i64 " + val + ")")
        return r
    }
    if (vType == "ptr") {
        const castR = nextReg()
        emitIR("  " + castR + " = ptrtoint ptr " + val + " to i64")
        const r = nextReg()
        emitIR("  " + r + " = call ptr @ym_i64_to_string(i64 " + castR + ")")
        return r
    }
    const r = nextReg()
    emitIR("  " + r + " = call ptr @ym_int_to_string(i32 " + val + ")")
    return r
}

// ── Type inference (simplified) ───────────────────────────────

function inferType(id: int): string {
    if (id <= 0) { return "int" }
    const kind = nGetKind(id)
    if (kind == "INT_LIT") { return "int" }
    if (kind == "DOUBLE_LIT") { return "double" }
    if (kind == "STRING_LIT") { return "string" }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT") { return "int" }
    if (kind == "TEMPLATE_LIT") { return "string" }
    if (kind == "IDENT") {
        const vType = getVarType(nGetS1(id))
        if (vType != "") { return vType }
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
        // Check both operands for double
        const binLt = inferType(nGetI1(id))
        const binRt = inferType(nGetI2(id))
        if (binLt == "double" || binRt == "double") { return "double" }
        if (binLt == "i64") { return "int" }
        return binLt
    }
    if (kind == "CALL") {
        const callee = nGetS1(id)
        if (callee == "Map") { return "ptr" }
        return callReturnType(callee)
    }
    if (kind == "METHOD_CALL") {
        const method = nGetS1(id)
        if (method == "length" || method == "indexOf" || method == "has" || method == "size") { return "int" }
        if (method == "charAt" || method == "substring" || method == "trim" || method == "toUpperCase" || method == "toLowerCase" || method == "replace" || method == "join" || method == "repeat" || method == "padStart" || method == "padEnd") { return "string" }
        if (method == "split" || method == "push" || method == "slice" || method == "concat" || method == "reverse" || method == "sort") { return "ptr" }
        if (method == "keys") { return "string" }
        if (method == "delete") { return "void" }
        if (method == "get") { return "i64" }
        if (method == "getString") { return "string" }
        if (method == "contains" || method == "startsWith" || method == "endsWith") { return "int" }
        // Class method — look up return type
        const mObjId = nGetI1(id)
        let mClassName = ""
        if (nGetKind(mObjId) == "IDENT") { mClassName = getObjClass(nGetS1(mObjId)) }
        if (nGetKind(mObjId) == "THIS" && currentClassName != "") { mClassName = currentClassName }
        if (mClassName != "") {
            // Look up in class and parent chain
            let lookupClass = mClassName
            while (lookupClass != "") {
                if (funcRetTypes.has(lookupClass + "_" + method) == 1) {
                    return funcRetTypes.getString(lookupClass + "_" + method)
                }
                if (classParents.has(lookupClass) == 1) {
                    lookupClass = classParents.getString(lookupClass)
                } else {
                    lookupClass = ""
                }
            }
        }
        return "int"
    }
    if (kind == "MEMBER_ACCESS") {
        const mField = nGetS1(id)
        const mObj = nGetI1(id)
        let maClassName = ""
        if (nGetKind(mObj) == "THIS" && currentClassName != "") { maClassName = currentClassName }
        if (nGetKind(mObj) == "IDENT") { maClassName = getObjClass(nGetS1(mObj)) }
        if (maClassName != "" && classFieldTypes.has(maClassName + "." + mField) == 1) {
            return classFieldTypes.getString(maClassName + "." + mField)
        }
        return "int"
    }
    if (kind == "GROUPING") { return inferType(nGetI1(id)) }
    if (kind == "UNARY") { return inferType(nGetI1(id)) }
    if (kind == "TERNARY") { return inferType(nGetI2(id)) }
    if (kind == "ARRAY_LIT") { return "ptr" }
    if (kind == "INDEX_ACCESS") { return "i64" }
    if (kind == "NEW_EXPR") { return "ptr" }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { return "int" }
    return "int"
}

function callReturnType(callee: string): string {
    if (callee == "readLine" || callee == "readFile" || callee == "arg" || callee == "getenv" || callee == "listDir" || callee == "sha256" || callee == "tcpRead" || callee == "fromCharCode") { return "string" }
    if (callee == "println" || callee == "print" || callee == "writeFile" || callee == "appendFile" || callee == "exit" || callee == "tcpClose") { return "void" }
    if (callee == "parseInt" || callee == "args" || callee == "system" || callee == "tcpListen" || callee == "tcpAccept" || callee == "tcpWrite" || callee == "mkdir" || callee == "mkdirp" || callee == "fileExists" || callee == "removeFile" || callee == "renameFile" || callee == "charCodeAt") { return "int" }
    if (callee == "parseDouble" || callee == "sqrt" || callee == "abs" || callee == "floor" || callee == "ceil" || callee == "round" || callee == "pow" || callee == "log" || callee == "sin" || callee == "cos" || callee == "random" || callee == "min" || callee == "max") { return "double" }
    if (callee == "Map") { return "ptr" }
    if (callee == "timeMs" || callee == "timeUnix" || callee == "fileSize") { return "i64" }
    // User-defined function
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
    if (t == "i64") { return "i64" }
    // Class type names → ptr
    if (classFields.has(t) == 1) { return "ptr" }
    return "i32"
}

function setVarType(name: string, varType: string) {
    varTypes.set(name, varType)
}

function getVarType(name: string): string {
    if (varTypes.has(name) == 1) {
        return varTypes.getString(name)
    }
    return ""
}
