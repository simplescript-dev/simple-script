// interp.ss — SimpleScript AST Interpreter (D087 Phase 1a-1b)
//
// Evaluates AST nodes directly. Core of the comptime system:
// compiler calls interpEval/interpExec on AST nodes to execute
// user code at compile time.
//
// Phase 1a: values (int/string/double/bool/null), scope stack,
// expression evaluation, minimal statement support (const/let).
// Phase 1b: control flow (if/while/for/for-in/do-while),
// break/continue/return, assignment, postfix inc/dec, arrays.

import { nGetKind, nGetS1, nGetS2, nGetI1, nGetI2, nGetI3, nGetI4, nGetList } from "./parser"

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
    if (t == "int") { return interpAsStr(id) }
    if (t == "double") { return interpAsStr(id) }
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

function interpFindScopeKey(name: string): string {
    let i = interpScopes.length() - 1
    while (i >= 0) {
        const key = `${interpScopes[i]}:${name}`
        if (interpVars.has(key) == 1) { return key }
        i = i - 1
    }
    return ""
}

function interpGetVar(name: string): int {
    const key = interpFindScopeKey(name)
    if (key != "") { return parseInt(interpVars.getString(key)) }
    println(`[interp] undefined variable: ${name}`)
    return interpNewNull()
}

// ── Control Flow Flags ────────────────────────────────────────

let interpBreakFlag = 0
let interpContinueFlag = 0
let interpReturnFlag = 0
let interpReturnVal = 0

function interpShouldStop(): int {
    return (interpBreakFlag == 1 || interpContinueFlag == 1 || interpReturnFlag == 1) ? 1 : 0
}

function interpGetReturnFlag(): int { return interpReturnFlag }
function interpGetReturnVal(): int { return interpReturnVal }

function interpCheckLoopExit(): int {
    if (interpReturnFlag == 1) { return 1 }
    if (interpBreakFlag == 1) { interpBreakFlag = 0; return 1 }
    interpContinueFlag = 0
    return 0
}

// ── Variable Update (reassignment) ───────────────────────────

function interpUpdateVar(name: string, valId: int) {
    const key = interpFindScopeKey(name)
    if (key != "") {
        interpVars.set(key, `${valId}`)
    } else {
        interpSetVar(name, valId)
    }
}

// ── Array Values ──────────────────────────────────────────────

function interpNewArray(items: string): int {
    return interpNewVal("array", items)
}

// ── Compound Assignment ───────────────────────────────────────

function interpCompoundOp(op: string, lv: int, rv: int): int {
    const lt = interpType(lv)
    const rt = interpType(rv)
    let binOp = ""
    if (op == "PLUS_ASSIGN") { binOp = "Add" }
    if (op == "MINUS_ASSIGN") { binOp = "Sub" }
    if (op == "STAR_ASSIGN") { binOp = "Mul" }
    if (op == "SLASH_ASSIGN") { binOp = "Div" }
    if (op == "PERCENT_ASSIGN") { binOp = "Mod" }
    if (binOp == "Add" && (lt == "string" || rt == "string")) {
        return interpNewString(`${interpToStr(lv)}${interpToStr(rv)}`)
    }
    if (lt == "double" || rt == "double") {
        const ld = lt == "double" ? interpAsDouble(lv) : parseDouble(`${interpAsInt(lv)}`)
        const rd = rt == "double" ? interpAsDouble(rv) : parseDouble(`${interpAsInt(rv)}`)
        return interpDoubleOp(binOp, ld, rd)
    }
    return interpIntOp(binOp, interpAsInt(lv), interpAsInt(rv))
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

// ── Statement Execution ───────────────────────────────────────

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
                if (interpShouldStop() == 1) { break }
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

    if (kind == "IF") {
        const cond = interpEval(nGetI1(nodeId))
        if (interpTruthy(cond) == 1) {
            interpExec(nGetI2(nodeId))
        } else if (nGetI3(nodeId) > 0) {
            interpExec(nGetI3(nodeId))
        }
        return
    }

    if (kind == "WHILE") {
        while (true) {
            const cond = interpEval(nGetI1(nodeId))
            if (interpTruthy(cond) == 0) { break }
            interpExec(nGetI2(nodeId))
            if (interpCheckLoopExit() == 1) { break }
        }
        return
    }

    if (kind == "DO_WHILE") {
        while (true) {
            interpExec(nGetI1(nodeId))
            if (interpCheckLoopExit() == 1) { break }
            const cond = interpEval(nGetI2(nodeId))
            if (interpTruthy(cond) == 0) { break }
        }
        return
    }

    if (kind == "FOR") {
        interpPushScope()
        if (nGetI1(nodeId) > 0) { interpExec(nGetI1(nodeId)) }
        while (true) {
            if (nGetI2(nodeId) > 0) {
                const cond = interpEval(nGetI2(nodeId))
                if (interpTruthy(cond) == 0) { break }
            }
            interpExec(nGetI4(nodeId))
            if (interpCheckLoopExit() == 1) { break }
            if (nGetI3(nodeId) > 0) { interpExec(nGetI3(nodeId)) }
        }
        interpPopScope()
        return
    }

    if (kind == "FOR_IN" || kind == "FOR_OF") {
        const iterVal = interpEval(nGetI1(nodeId))
        if (interpType(iterVal) == "array") {
            const items = interpAsStr(iterVal)
            if (items != "") {
                const parts = items.split(",")
                interpPushScope()
                let fi = 0
                while (fi < parts.length()) {
                    interpSetVar(nGetS1(nodeId), parseInt(parts[fi]))
                    interpExec(nGetI2(nodeId))
                    if (interpCheckLoopExit() == 1) { break }
                    fi = fi + 1
                }
                interpPopScope()
            }
        }
        return
    }

    if (kind == "BREAK") {
        interpBreakFlag = 1
        return
    }

    if (kind == "CONTINUE") {
        interpContinueFlag = 1
        return
    }

    if (kind == "RETURN") {
        interpReturnFlag = 1
        if (nGetI1(nodeId) > 0) {
            interpReturnVal = interpEval(nGetI1(nodeId))
        } else {
            interpReturnVal = interpNewNull()
        }
        return
    }

    if (kind == "ASSIGN") {
        const name = nGetS1(nodeId)
        const op = nGetS2(nodeId)
        const rhs = interpEval(nGetI1(nodeId))
        if (op == "ASSIGN") {
            interpUpdateVar(name, rhs)
        } else {
            const old = interpGetVar(name)
            interpUpdateVar(name, interpCompoundOp(op, old, rhs))
        }
        return
    }

    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") {
        interpEval(nodeId)
        return
    }

    if (kind == "INDEX_ASSIGN") {
        const arrName = nGetS1(nodeId)
        const idxVal = interpEval(nGetI1(nodeId))
        const rhs = interpEval(nGetI2(nodeId))
        const arrId = interpGetVar(arrName)
        if (interpType(arrId) == "array") {
            const items = interpAsStr(arrId)
            if (items != "") {
                const parts = items.split(",")
                const idx = interpAsInt(idxVal)
                if (idx >= 0 && idx < parts.length()) {
                    let newItems = ""
                    let ni = 0
                    while (ni < parts.length()) {
                        if (ni > 0) { newItems = `${newItems},` }
                        if (ni == idx) {
                            newItems = `${newItems}${rhs}`
                        } else {
                            newItems = `${newItems}${parts[ni]}`
                        }
                        ni = ni + 1
                    }
                    interpUpdateVar(arrName, interpNewArray(newItems))
                }
            }
        }
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
    interpBreakFlag = 0
    interpContinueFlag = 0
    interpReturnFlag = 0
    interpReturnVal = 0
}
