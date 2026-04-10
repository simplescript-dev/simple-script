// interp.ss — SimpleScript AST Interpreter (D087 Phase 1a)
//
// Evaluates AST nodes directly. Core of the comptime system:
// compiler calls interpEval/interpExec on AST nodes to execute
// user code at compile time.
//
// Phase 1a: values (int/string/double/bool/null), scope stack,
// expression evaluation, minimal statement support (const/let).

import { nGetKind, nGetS1, nGetS2, nGetI1, nGetI2, nGetI3, nGetList } from "./parser"

// ── Value Storage ──────────────────────────────────────────────
// Each value has a unique int ID. Type and data stored in Maps.

let interpVT = new Map()
let interpVD = new Map()
let interpVC = 0

function interpNewVal(t: string, d: string): int {
    interpVC = interpVC + 1
    interpVT.set(`${interpVC}`, t)
    interpVD.set(`${interpVC}`, d)
    return interpVC
}

function interpNewInt(n: int): int {
    return interpNewVal("int", `${n}`)
}

function interpNewDouble(d: double): int {
    return interpNewVal("double", `${d}`)
}

function interpNewString(s: string): int {
    return interpNewVal("string", s)
}

function interpNewBool(b: int): int {
    return interpNewVal("bool", b == 1 ? "1" : "0")
}

function interpNewNull(): int {
    return interpNewVal("null", "")
}

// ── Value Access ───────────────────────────────────────────────

function interpType(id: int): string {
    return interpVT.getString(`${id}`)
}

function interpAsInt(id: int): int {
    return parseInt(interpVD.getString(`${id}`))
}

function interpAsDouble(id: int): double {
    return parseDouble(interpVD.getString(`${id}`))
}

function interpAsStr(id: int): string {
    return interpVD.getString(`${id}`)
}

function interpAsBool(id: int): int {
    return interpVD.getString(`${id}`) == "1" ? 1 : 0
}

function interpToStr(id: int): string {
    const t = interpType(id)
    if (t == "string") { return interpAsStr(id) }
    if (t == "int") { return interpVD.getString(`${id}`) }
    if (t == "double") { return interpVD.getString(`${id}`) }
    if (t == "bool") { return interpAsBool(id) == 1 ? "true" : "false" }
    return "null"
}

function interpTruthy(id: int): int {
    const t = interpType(id)
    if (t == "null") { return 0 }
    if (t == "bool") { return interpAsBool(id) }
    if (t == "int") { return interpAsInt(id) != 0 ? 1 : 0 }
    if (t == "string") { return interpAsStr(id) != "" ? 1 : 0 }
    return 1
}

// ── Scope Stack ────────────────────────────────────────────────
// Each scope gets a unique ID. Variables stored as "scopeId:name" → valId.

let interpScopes: Array<string> = []
let interpScopeNext = 0
let interpVars = new Map()

function interpPushScope() {
    interpScopeNext = interpScopeNext + 1
    interpScopes = interpScopes.push(`${interpScopeNext}`)
}

function interpPopScope() {
    let ns: Array<string> = []
    let i = 0
    while (i < interpScopes.length() - 1) {
        ns = ns.push(interpScopes[i])
        i = i + 1
    }
    interpScopes = ns
}

function interpSetVar(name: string, valId: int) {
    const sid = interpScopes[interpScopes.length() - 1]
    interpVars.set(`${sid}:${name}`, `${valId}`)
}

function interpGetVar(name: string): int {
    let i = interpScopes.length() - 1
    while (i >= 0) {
        const key = `${interpScopes[i]}:${name}`
        if (interpVars.has(key) == 1) {
            return parseInt(interpVars.getString(key))
        }
        i = i - 1
    }
    println(`[interp] undefined variable: ${name}`)
    return interpNewNull()
}

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
    println(`[interp] unsupported expr: ${kind}`)
    return interpNewNull()
}

// ── Binary Operations ──────────────────────────────────────────

function interpBinary(nodeId: int): int {
    const op = nGetS1(nodeId)

    // Short-circuit logical
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

    const lv = interpEval(nGetI1(nodeId))
    const rv = interpEval(nGetI2(nodeId))
    const lt = interpType(lv)
    const rt = interpType(rv)

    // Null coalescing
    if (op == "NullCoalesce") {
        if (lt == "null") { return rv }
        return lv
    }

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
        const ld = lt == "double" ? interpAsDouble(lv) : parseDouble(`${interpAsInt(lv)}`)
        const rd = rt == "double" ? interpAsDouble(rv) : parseDouble(`${interpAsInt(rv)}`)
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
    if (op == "Div") { return interpNewDouble(a / b) }
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
        if (t == "double") { return interpNewDouble(0.0 - interpAsDouble(val)) }
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

// ── Statement Execution (minimal for Phase 1a) ────────────────

function interpExec(nodeId: int) {
    if (nodeId <= 0) { return }
    const kind = nGetKind(nodeId)

    if (kind == "BLOCK") {
        interpPushScope()
        const list = nGetList(nodeId)
        if (list != "") {
            const stmts = list.split(",")
            let i = 0
            while (i < stmts.length()) {
                interpExec(parseInt(stmts[i]))
                i = i + 1
            }
        }
        interpPopScope()
        return
    }

    if (kind == "VAR_DECL") {
        const name = nGetS1(nodeId)
        const initId = nGetI1(nodeId)
        let val = interpNewNull()
        if (initId > 0) { val = interpEval(initId) }
        interpSetVar(name, val)
        return
    }

    if (kind == "EXPR_STMT") {
        if (nGetI1(nodeId) > 0) { interpEval(nGetI1(nodeId)) }
        return
    }

    println(`[interp] unsupported stmt: ${kind}`)
}

// ── Reset ──────────────────────────────────────────────────────

function interpReset() {
    interpVT = new Map()
    interpVD = new Map()
    interpVC = 0
    interpScopes = []
    interpScopeNext = 0
    interpVars = new Map()
}
