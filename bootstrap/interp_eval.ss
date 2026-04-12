// interp_eval.ss — Expression evaluation for the AST interpreter
//
// Handles interpEval dispatch, binary/unary operations, and template strings.
// Forward-references interpCall, interpNewExpr, interpMethodCall from interp_calls.ss
// and value/scope helpers from interp.ss.

// ── Expression Evaluation ──────────────────────────────────────

function interpEval(nodeId: int): int {
    const kind = nGetKind(nodeId)
    if (kind == "INT_LIT") { return interpNewInt(parseInt(nGetS1(nodeId))) }
    if (kind == "DOUBLE_LIT") { return interpNewDouble(parseDouble(nGetS1(nodeId))) }
    if (kind == "STRING_LIT") { return interpNewString(nGetS1(nodeId)) }
    if (kind == "TRUE_LIT") { return interpNewBool(1) }
    if (kind == "FALSE_LIT") { return interpNewBool(0) }
    if (kind == "NULL_LIT") { return interpNewNull() }
    if (kind == "IDENT") { return interpGetVar(nGetS1(nodeId)) }
    if (kind == "GROUPING") { return interpEval(nGetI1(nodeId)) }
    if (kind == "BINARY") { return interpBinary(nodeId) }
    if (kind == "UNARY") { return interpUnary(nodeId) }
    if (kind == "TERNARY") {
        if (interpTruthy(interpEval(nGetI1(nodeId))) == 1) {
            return interpEval(nGetI2(nodeId))
        }
        return interpEval(nGetI3(nodeId))
    }
    if (kind == "TEMPLATE_LIT") { return interpTemplate(nodeId) }
    if (kind == "ARRAY_LIT") {
        const list = nGetList(nodeId)
        if (list == "") { return interpNewArray("") }
        const items = list.split(",")
        let valIds = ""
        let ai = 0
        while (ai < items.length()) {
            const elemVal = interpEval(parseInt(items[ai]))
            if (ai > 0) { valIds = `${valIds},` }
            valIds = `${valIds}${elemVal}`
            ai = ai + 1
        }
        return interpNewArray(valIds)
    }
    if (kind == "INDEX_ACCESS") {
        const obj = interpEval(nGetI1(nodeId))
        const idx = interpEval(nGetI2(nodeId))
        if (interpType(obj) == "array") {
            const items = interpAsStr(obj)
            if (items == "") { return interpNewNull() }
            const parts = items.split(",")
            const ii = interpAsInt(idx)
            if (ii >= 0 && ii < parts.length()) {
                return parseInt(parts[ii])
            }
        }
        return interpNewNull()
    }
    if (kind == "POSTFIX_INC") {
        const name = nGetS1(nodeId)
        const old = interpGetVar(name)
        interpUpdateVar(name, interpNewInt(interpAsInt(old) + 1))
        return old
    }
    if (kind == "POSTFIX_DEC") {
        const name = nGetS1(nodeId)
        const old = interpGetVar(name)
        interpUpdateVar(name, interpNewInt(interpAsInt(old) - 1))
        return old
    }
    if (kind == "CALL") { return interpCall(nodeId) }
    if (kind == "THIS") {
        if (interpThisVal > 0) { return interpThisVal }
        println("[interp] 'this' used outside method")
        return interpNewNull()
    }
    if (kind == "NEW_EXPR") { return interpNewExpr(nodeId) }
    if (kind == "MEMBER_ACCESS") { return interpMemberAccess(nodeId) }
    if (kind == "METHOD_CALL") { return interpMethodCall(nodeId) }
    if (kind == "ARROW_FUNC") { return interpNewVal("fn", `${nodeId}`) }
    if (kind == "TYPEINFO_EXPR") { return interpBuildTypeInfo(nGetS1(nodeId)) }
    // @comptimeEmit(ssSource) — accumulate SS source for post-block compilation (D087 Phase 3c)
    if (kind == "COMPTIME_EMIT") {
        const ssCode = interpAsStr(interpEval(nGetI1(nodeId)))
        comptimeSS = `${comptimeSS}${ssCode}`
        return interpNewNull()
    }
    println(`[interp] unsupported expr: ${kind}`)
    return interpNewNull()
}

// ── Binary Operations ──────────────────────────────────────────

function interpBinary(nodeId: int): int {
    const op = nGetS1(nodeId)

    // Short-circuit: And, Or, NullCoalesce
    if (op == "And") {
        const lv = interpEval(nGetI1(nodeId))
        if (interpTruthy(lv) == 0) { return interpNewBool(0) }
        return interpNewBool(interpTruthy(interpEval(nGetI2(nodeId))))
    }
    if (op == "Or") {
        const lv = interpEval(nGetI1(nodeId))
        if (interpTruthy(lv) == 1) { return interpNewBool(1) }
        return interpNewBool(interpTruthy(interpEval(nGetI2(nodeId))))
    }
    if (op == "NullCoalesce") {
        const lv = interpEval(nGetI1(nodeId))
        if (interpType(lv) != "null") { return lv }
        return interpEval(nGetI2(nodeId))
    }

    const lv = interpEval(nGetI1(nodeId))
    const rv = interpEval(nGetI2(nodeId))
    const lt = interpType(lv)
    const rt = interpType(rv)

    // Null equality
    if (lt == "null" || rt == "null") {
        if (op == "Eq") { return interpNewBool(lt == "null" && rt == "null" ? 1 : 0) }
        if (op == "Ne") { return interpNewBool(lt == "null" && rt == "null" ? 0 : 1) }
        return interpNewNull()
    }

    // String concat
    if (op == "Add" && (lt == "string" || rt == "string")) {
        return interpNewString(`${interpToStr(lv)}${interpToStr(rv)}`)
    }

    // String comparison
    if (lt == "string" && rt == "string") {
        if (op == "Eq") { return interpNewBool(interpAsStr(lv) == interpAsStr(rv) ? 1 : 0) }
        if (op == "Ne") { return interpNewBool(interpAsStr(lv) != interpAsStr(rv) ? 1 : 0) }
    }

    // Bool comparison
    if (lt == "bool" && rt == "bool") {
        if (op == "Eq") { return interpNewBool(interpAsBool(lv) == interpAsBool(rv) ? 1 : 0) }
        if (op == "Ne") { return interpNewBool(interpAsBool(lv) != interpAsBool(rv) ? 1 : 0) }
    }

    // Double promotion
    if (lt == "double" || rt == "double") {
        const ld = lt == "double" ? parseDouble(interpAsStr(lv)) : parseDouble(`${interpAsInt(lv)}`)
        const rd = rt == "double" ? parseDouble(interpAsStr(rv)) : parseDouble(`${interpAsInt(rv)}`)
        return interpDoubleOp(op, ld, rd)
    }

    // Int operations
    if (lt == "int" && rt == "int") {
        return interpIntOp(op, interpAsInt(lv), interpAsInt(rv))
    }

    println(`[interp] unsupported binary: ${lt} ${op} ${rt}`)
    return interpNewNull()
}

function interpIntOp(op: string, a: int, b: int): int {
    if (op == "Add") { return interpNewInt(a + b) }
    if (op == "Sub") { return interpNewInt(a - b) }
    if (op == "Mul") { return interpNewInt(a * b) }
    if (op == "Div") {
        if (b == 0) { println("[interp] division by zero"); return interpNewInt(0) }
        return interpNewInt(a / b)
    }
    if (op == "Mod") { return interpNewInt(a % b) }
    if (op == "Eq") { return interpNewBool(a == b ? 1 : 0) }
    if (op == "Ne") { return interpNewBool(a != b ? 1 : 0) }
    if (op == "Lt") { return interpNewBool(a < b ? 1 : 0) }
    if (op == "Gt") { return interpNewBool(a > b ? 1 : 0) }
    if (op == "Le") { return interpNewBool(a <= b ? 1 : 0) }
    if (op == "Ge") { return interpNewBool(a >= b ? 1 : 0) }
    if (op == "BitAnd") { return interpNewInt(a & b) }
    if (op == "BitOr") { return interpNewInt(a | b) }
    if (op == "BitXor") { return interpNewInt(a ^ b) }
    if (op == "Shl") { return interpNewInt(a << b) }
    if (op == "Shr") { return interpNewInt(a >> b) }
    println(`[interp] unsupported int op: ${op}`)
    return interpNewNull()
}

function interpDoubleOp(op: string, a: double, b: double): int {
    if (op == "Add") { return interpNewDouble(a + b) }
    if (op == "Sub") { return interpNewDouble(a - b) }
    if (op == "Mul") { return interpNewDouble(a * b) }
    if (op == "Div") {
        if (b == 0.0) { println("[interp] division by zero"); return interpNewDouble(0.0) }
        return interpNewDouble(a / b)
    }
    if (op == "Eq") { return interpNewBool(a == b ? 1 : 0) }
    if (op == "Ne") { return interpNewBool(a != b ? 1 : 0) }
    if (op == "Lt") { return interpNewBool(a < b ? 1 : 0) }
    if (op == "Gt") { return interpNewBool(a > b ? 1 : 0) }
    if (op == "Le") { return interpNewBool(a <= b ? 1 : 0) }
    if (op == "Ge") { return interpNewBool(a >= b ? 1 : 0) }
    println(`[interp] unsupported double op: ${op}`)
    return interpNewNull()
}

// ── Unary Operations ───────────────────────────────────────────

function interpUnary(nodeId: int): int {
    const op = nGetS1(nodeId)
    const val = interpEval(nGetI1(nodeId))
    const t = interpType(val)
    if (op == "Neg") {
        if (t == "int") { return interpNewInt(0 - interpAsInt(val)) }
        if (t == "double") { return interpNewDouble(0.0 - parseDouble(interpAsStr(val))) }
    }
    if (op == "Not") {
        return interpNewBool(interpTruthy(val) == 1 ? 0 : 1)
    }
    if (op == "BitNot") {
        if (t == "int") { return interpNewInt(~interpAsInt(val)) }
    }
    println(`[interp] unsupported unary: ${op} on ${t}`)
    return interpNewNull()
}

// ── Template String ────────────────────────────────────────────

function interpTemplate(nodeId: int): int {
    const list = nGetList(nodeId)
    if (list == "") { return interpNewString("") }
    let result = ""
    const parts = list.split(",")
    let i = 0
    while (i < parts.length()) {
        const fragId = parseInt(parts[i])
        const fk = nGetKind(fragId)
        if (fk == "TMPL_FRAG_LIT") {
            result = `${result}${nGetS1(fragId)}`
        } else if (fk == "TMPL_FRAG_EXPR") {
            result = `${result}${interpToStr(interpEval(nGetI1(fragId)))}`
        }
        i = i + 1
    }
    return interpNewString(result)
}
