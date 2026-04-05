// gen_exprs.ss — Expression codegen: dispatcher, simple handlers, binary ops, ternary, string conversion
// Function calls in gen_calls.ss, method calls in gen_methods.ss.

import { genCall, genTemplateLit, genArrowFunc, flushArrowDefs, genArrayLit } from "./gen_calls"
import { genMethodCall, genOptionalMethodCall } from "./gen_methods"

// ── Simple expression handlers ──────────────────────────────────

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
    // Tuple type: use positional element type
    let idxElem = ""
    if (nGetKind(nGetI1(id)) == "IDENT") {
        const tvt = getVarType(nGetS1(nGetI1(id)))
        if (isTupleType(tvt) == 1 && nGetKind(nGetI2(id)) == "INT_LIT") {
            idxElem = tupleElemTypeAtIndex(tvt, parseInt(nGetS1(nGetI2(id))))
        }
    }
    if (idxElem == "") { idxElem = inferArrayElemType(nGetI1(id)) }
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
    if (idxElem == "double") {
        const castR = nextReg()
        emitIR(`  ${castR} = bitcast i64 ${rawR} to double`)
        return castR
    }
    if (ssTypeToLLVM(idxElem) == "ptr") {
        const castR = nextReg()
        emitIR(`  ${castR} = inttoptr i64 ${rawR} to ptr`)
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

// ── Expression dispatcher ───────────────────────────────────────

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
    if (kind == "SUPER") { return genThisExpr() }
    if (kind == "IDENT") { return genIdent(id) }
    if (kind == "BINARY") { return genBinary(id) }
    if (kind == "UNARY") { return genUnary(id) }
    if (kind == "CALL") { return genCall(id) }
    if (kind == "METHOD_CALL") {
        if (nGetI3(id) > 0) { return genOptionalMethodCall(id) }
        return genMethodCall(id)
    }
    if (kind == "MEMBER_ACCESS") {
        if (nGetI3(id) > 0) { return genOptionalMemberAccess(id) }
        return genMemberAccess(id)
    }
    if (kind == "NEW_EXPR") { return genNewExpr(id) }
    if (kind == "GROUPING") { return genExpr(nGetI1(id)) }
    if (kind == "TERNARY") { return genTernary(id) }
    if (kind == "TEMPLATE_LIT") { return genTemplateLit(id) }
    if (kind == "ARRAY_LIT") { return genArrayLit(id) }
    if (kind == "ARROW_FUNC") { return genArrowFunc(id) }
    if (kind == "INDEX_ACCESS") { return genIndexAccess(id) }
    if (kind == "POSTFIX_INC") { return genPostfixExpr(id) }
    if (kind == "NAMED_ARG") { return genExpr(nGetI1(id)) }
    return "0"
}

// ── Binary operation helpers ────────────────────────────────────

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
    // String: check length == 0; class/other ptr: check == null (D067)
    const ncLType = inferType(leftId)
    let ncCmp = ""
    if (ncLType == "string") {
        const ncLen = nextReg()
        emitIR(`  ${ncLen} = call i32 @ss_stringLength(ptr ${ncLeft})`)
        ncCmp = nextReg()
        emitIR(`  ${ncCmp} = icmp eq i32 ${ncLen}, 0`)
    } else {
        ncCmp = nextReg()
        emitIR(`  ${ncCmp} = icmp eq ptr ${ncLeft}, null`)
    }
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
    // instanceof: call ss_isinstance(obj, className)
    if (op == "Instanceof") {
        const objReg = genExpr(leftId)
        const className = nGetS1(rightId)
        const nameStr = addStringConst(className)
        const r = nextReg()
        emitIR(`  ${r} = call i32 @ss_isinstance(ptr ${objReg}, ptr ${nameStr})`)
        return r
    }

    // Numeric: evaluate operands
    let left = genExpr(leftId)
    let right = genExpr(rightId)
    if (blt == "i64") { const tr = nextReg(); emitIR(`  ${tr} = trunc i64 ${left} to i32`); left = tr }
    if (brt == "i64") { const tr = nextReg(); emitIR(`  ${tr} = trunc i64 ${right} to i32`); right = tr }

    // Pow: always use double math via ss_pow, convert back if both operands are int
    if (op == "Pow") {
        let dl = left
        let dr = right
        if (blt != "double") {
            const cv = nextReg()
            emitIR(`  ${cv} = sitofp i32 ${dl} to double`)
            dl = cv
        }
        if (brt != "double") {
            const cv = nextReg()
            emitIR(`  ${cv} = sitofp i32 ${dr} to double`)
            dr = cv
        }
        const powR = nextReg()
        emitIR(`  ${powR} = call double @ss_pow(double ${dl}, double ${dr})`)
        if (blt != "double" && brt != "double") {
            const intR = nextReg()
            emitIR(`  ${intR} = fptosi double ${powR} to i32`)
            return intR
        }
        return powR
    }

    if (blt == "double" || brt == "double") {
        return genDoubleBinary(op, left, right, blt, brt)
    }
    // Pointer comparison: class/null Eq/Ne — both sides must be ptr (D067)
    if ((op == "Eq" || op == "Ne") && ssTypeToLLVM(blt) == "ptr" && ssTypeToLLVM(brt) == "ptr") {
        const pcOp = op == "Eq" ? "eq" : "ne"
        const pcR = nextReg()
        emitIR(`  ${pcR} = icmp ${pcOp} ptr ${left}, ${right}`)
        const pcR2 = nextReg()
        emitIR(`  ${pcR2} = zext i1 ${pcR} to i32`)
        return pcR2
    }
    return genIntBinary(op, left, right)
}

// ── Ternary expression ──────────────────────────────────────────

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

// ── Expression to string conversion ─────────────────────────────

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
