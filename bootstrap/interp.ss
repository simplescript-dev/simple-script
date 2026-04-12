// interp.ss — SimpleScript AST Interpreter (D087 Phase 1a-1e)
//
// Evaluates AST nodes directly. Core of the comptime system:
// compiler calls interpEval/interpExec on AST nodes to execute
// user code at compile time.
//
// Phase 1a: values (int/string/double/bool/null), scope stack,
// expression evaluation, minimal statement support (const/let).
// Phase 1b: control flow (if/while/for/for-in/do-while),
// break/continue/return, assignment, postfix inc/dec, arrays.
// Phase 1c: function declaration, function call (positional +
// named args + defaults), recursion, builtin println.
// Phase 1d: class (new, fields, methods, this, inheritance).
// Phase 1e: built-in type methods (string/Array/Map), arrow
// functions, parseInt/parseDouble/toString.

import { nGetKind, nGetS1, nGetS2, nGetI1, nGetI2, nGetI3, nGetI4, nGetList } from "./parser"
import { interpBuiltinMethod, interpNewMap, interpResetBuiltins } from "./interp_builtins"

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
    if (t == "object") { return `${interpAsStr(id)}{...}` }
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

// ── Comptime IR Buffer (D087 Phase 3b) ──────────────────────
// Accumulates LLVM IR emitted by comptime blocks via emit().
// NOT reset between comptime blocks — persists across all blocks in a compilation.

let comptimeIR = ""

function interpGetComptimeIR(): string { return comptimeIR }
function interpClearComptimeIR() { comptimeIR = "" }

// ── Comptime SS Buffer (D087 Phase 3c) ──────────────────────
// Accumulates SS source strings emitted by @comptimeEmit(str).
// Flushed after each comptime block: tokenize → parse → register → genStmt.

let comptimeSS = ""

function interpGetComptimeSS(): string { return comptimeSS }
function interpClearComptimeSS() { comptimeSS = "" }

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

function interpArrayPush(arrValId: int, itemValId: int): int {
    const items = interpAsStr(arrValId)
    if (items == "") {
        interpVD.set(`${arrValId}`, `${itemValId}`)
    } else {
        interpVD.set(`${arrValId}`, `${items},${itemValId}`)
    }
    return arrValId
}

// ── Class & Object Support ───────────────────────────────────

let interpClasses = new Map()
let interpClassParents = new Map()
let interpObjFields = new Map()
let interpThisVal = 0

function interpGetField(objId: int, fieldName: string): int {
    const key = `${objId}:${fieldName}`
    if (interpObjFields.has(key) == 1) {
        return parseInt(interpObjFields.getString(key))
    }
    return interpNewNull()
}

function interpSetField(objId: int, fieldName: string, valId: int) {
    interpObjFields.set(`${objId}:${fieldName}`, `${valId}`)
}

function interpCollectFields(className: string): string {
    let fields = ""
    if (interpClassParents.has(className) == 1) {
        fields = interpCollectFields(interpClassParents.getString(className))
    }
    if (interpClasses.has(className) != 1) { return fields }
    const classNodeId = parseInt(interpClasses.getString(className))
    const fieldList = nGetList(classNodeId)
    if (fieldList != "") {
        if (fields != "") {
            fields = `${fields},${fieldList}`
        } else {
            fields = fieldList
        }
    }
    return fields
}

function interpFindMethod(className: string, methodName: string): int {
    if (interpClasses.has(className) != 1) { return 0 }
    const classNodeId = parseInt(interpClasses.getString(className))
    const methodsBlock = nGetI2(classNodeId)
    if (methodsBlock > 0) {
        const methodList = nGetList(methodsBlock)
        if (methodList != "") {
            const methods = methodList.split(",")
            let i = 0
            while (i < methods.length()) {
                const mId = parseInt(methods[i])
                if (nGetS1(mId) == methodName) { return mId }
                i = i + 1
            }
        }
    }
    if (interpClassParents.has(className) == 1) {
        return interpFindMethod(interpClassParents.getString(className), methodName)
    }
    return 0
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
        const ld = lt == "double" ? parseDouble(interpAsStr(lv)) : parseDouble(`${interpAsInt(lv)}`)
        const rd = rt == "double" ? parseDouble(interpAsStr(rv)) : parseDouble(`${interpAsInt(rv)}`)
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

// ── Function Calls ────────────────────────────────────────────

function interpCall(nodeId: int): int {
    const name = nGetS1(nodeId)
    const argList = nGetList(nodeId)

    // Built-in: println (allowed for comptime debugging)
    if (name == "println") {
        if (argList != "") {
            const argIds = argList.split(",")
            println(interpToStr(interpEval(parseInt(argIds[0]))))
        } else {
            println("")
        }
        return interpNewNull()
    }
    // Built-in: parseInt, parseDouble, toString
    if (name == "parseInt") {
        if (argList != "") {
            const val = interpEval(parseInt(argList.split(",")[0]))
            return interpNewInt(parseInt(interpAsStr(val)))
        }
        return interpNewInt(0)
    }
    if (name == "parseDouble") {
        if (argList != "") {
            const val = interpEval(parseInt(argList.split(",")[0]))
            return interpNewDouble(parseDouble(interpAsStr(val)))
        }
        return interpNewDouble(0.0)
    }
    if (name == "toString") {
        if (argList != "") {
            const val = interpEval(parseInt(argList.split(",")[0]))
            return interpNewString(interpToStr(val))
        }
        return interpNewString("")
    }
    // Built-in: emit(irString) — append LLVM IR to comptime output (D087 Phase 3b)
    if (name == "emit") {
        if (argList != "") {
            const val = interpEval(parseInt(argList.split(",")[0]))
            comptimeIR = `${comptimeIR}${interpAsStr(val)}`
        }
        return interpNewNull()
    }
    // Built-in: registerFunction(name, retType, paramCount) — register in compiler tables (D087 Phase 3b)
    if (name == "registerFunction") {
        if (argList == "") {
            println("[comptime] registerFunction requires at least 1 argument: name")
            return interpNewNull()
        }
        const rfArgs = argList.split(",")
        const rfName = interpAsStr(interpEval(parseInt(rfArgs[0])))
        const rfRetType = rfArgs.length() > 1 ? interpAsStr(interpEval(parseInt(rfArgs[1]))) : "void"
        const rfParamCount = rfArgs.length() > 2 ? interpAsInt(interpEval(parseInt(rfArgs[2]))) : 0
        funcRetTypes.set(rfName, rfRetType)
        funcParamCount.set(rfName, `${rfParamCount}`)
        return interpNewNull()
    }
    // Built-in: getAnnotatedClasses(annName) — return array of class names with annotation (D087 Phase 4a)
    if (name == "getAnnotatedClasses") {
        if (argList == "") {
            println("[comptime] getAnnotatedClasses requires 1 argument: annName")
            return interpNewArray("")
        }
        const gacName = interpAsStr(interpEval(parseInt(argList.split(",")[0])))
        const gacResult = interpNewArray("")
        let gacSeen = new Map()
        let gacI = 0
        while (gacI < annClassAnnNames.length()) {
            if (annClassAnnNames[gacI] == gacName) {
                const gacClassId = parseInt(annClassNodeIds[gacI])
                const gacClassName = nGetS1(gacClassId)
                if (gacSeen.has(gacClassName) == 0) {
                    interpArrayPush(gacResult, interpNewString(gacClassName))
                    gacSeen.set(gacClassName, "1")
                }
            }
            gacI = gacI + 1
        }
        return gacResult
    }
    // Built-in: addStringConst(str) — calls compiler's addStringConst, returns IR ref (D087 Phase 4b)
    if (name == "addStringConst") {
        if (argList == "") {
            println("[comptime] addStringConst requires 1 argument: str")
            return interpNewString("")
        }
        const ascVal = interpEval(parseInt(argList.split(",")[0]))
        const ascRef = addStringConst(interpAsStr(ascVal))
        return interpNewString(ascRef)
    }
    // Built-in: getTypeInfo(className) — like @typeInfo but takes a string arg (D087 Phase 4a)
    if (name == "getTypeInfo") {
        if (argList == "") {
            println("[comptime] getTypeInfo requires 1 argument: className")
            return interpNewNull()
        }
        const gtiName = interpAsStr(interpEval(parseInt(argList.split(",")[0])))
        return interpBuildTypeInfo(gtiName)
    }

    // Look up function value
    const fnVal = interpGetVar(name)
    if (interpType(fnVal) != "fn") {
        println(`[interp] not a function: ${name}`)
        return interpNewNull()
    }

    const funcNodeId = parseInt(interpAsStr(fnVal))
    const paramList = nGetList(funcNodeId)
    const bodyId = nGetI1(funcNodeId)

    // Evaluate all arguments before pushing scope
    let argVals: Array<string> = []
    let namedArgs = new Map()
    let hasNamed = 0
    if (argList != "") {
        const argIds = argList.split(",")
        let i = 0
        while (i < argIds.length()) {
            const argNodeId = parseInt(argIds[i])
            if (nGetKind(argNodeId) == "NAMED_ARG") {
                hasNamed = 1
                const argVal = interpEval(nGetI1(argNodeId))
                namedArgs.set(nGetS1(argNodeId), `${argVal}`)
            } else {
                const argVal = interpEval(argNodeId)
                argVals = argVals.push(`${argVal}`)
            }
            i = i + 1
        }
    }

    // Save and reset control flow flags (isolate function body)
    const savedBreak = interpBreakFlag
    const savedContinue = interpContinueFlag
    interpBreakFlag = 0
    interpContinueFlag = 0

    // Push scope and bind parameters
    interpPushScope()
    if (paramList != "") {
        const params = paramList.split(",")
        let posIdx = 0
        let pi = 0
        while (pi < params.length()) {
            const paramId = parseInt(params[pi])
            const pName = nGetS1(paramId)
            if (hasNamed == 1 && namedArgs.has(pName) == 1) {
                interpSetVar(pName, parseInt(namedArgs.getString(pName)))
            } else if (posIdx < argVals.length()) {
                interpSetVar(pName, parseInt(argVals[posIdx]))
                posIdx = posIdx + 1
            } else {
                // Default parameter value
                const defaultId = nGetI1(paramId)
                if (defaultId > 0) {
                    interpSetVar(pName, interpEval(defaultId))
                } else {
                    interpSetVar(pName, interpNewNull())
                }
            }
            pi = pi + 1
        }
    }

    // Execute function body
    if (bodyId > 0) { interpExec(bodyId) }

    // Capture return value and reset return flag
    let result = interpNewNull()
    if (interpReturnFlag == 1) {
        result = interpReturnVal
        interpReturnFlag = 0
        interpReturnVal = 0
    }

    interpPopScope()

    // Restore caller's control flow flags
    interpBreakFlag = savedBreak
    interpContinueFlag = savedContinue

    return result
}

// ── New Expression ────────────────────────────────────────────

function interpNewExpr(nodeId: int): int {
    const className = nGetS1(nodeId)
    if (className == "Map") { return interpNewMap() }
    if (interpClasses.has(className) != 1) {
        println(`[interp] unknown class: ${className}`)
        return interpNewNull()
    }
    const objId = interpNewVal("object", className)
    const allFields = interpCollectFields(className)
    let fieldNames: Array<string> = []
    if (allFields != "") {
        const fieldParts = allFields.split(",")
        let fi = 0
        while (fi < fieldParts.length()) {
            const fId = parseInt(fieldParts[fi])
            const fName = nGetS1(fId)
            fieldNames = fieldNames.push(fName)
            const defaultId = nGetI1(fId)
            if (defaultId > 0) {
                interpSetField(objId, fName, interpEval(defaultId))
            } else {
                interpSetField(objId, fName, interpNewNull())
            }
            fi = fi + 1
        }
    }
    const argList = nGetList(nodeId)
    if (argList != "") {
        const argIds = argList.split(",")
        let posIdx = 0
        let i = 0
        while (i < argIds.length()) {
            const argNodeId = parseInt(argIds[i])
            if (nGetKind(argNodeId) == "NAMED_ARG") {
                interpSetField(objId, nGetS1(argNodeId), interpEval(nGetI1(argNodeId)))
            } else {
                const argVal = interpEval(argNodeId)
                if (posIdx < fieldNames.length()) {
                    interpSetField(objId, fieldNames[posIdx], argVal)
                }
                posIdx = posIdx + 1
            }
            i = i + 1
        }
    }
    return objId
}

// ── Member Access ─────────────────────────────────────────────

function interpMemberAccess(nodeId: int): int {
    const objVal = interpEval(nGetI1(nodeId))
    const fieldName = nGetS1(nodeId)
    if (interpType(objVal) == "object") {
        return interpGetField(objVal, fieldName)
    }
    println(`[interp] no field '${fieldName}' on ${interpType(objVal)}`)
    return interpNewNull()
}

// ── Method Call ───────────────────────────────────────────────

function interpMethodCall(nodeId: int): int {
    const methodName = nGetS1(nodeId)
    const objVal = interpEval(nGetI1(nodeId))
    const objType = interpType(objVal)

    // Built-in type methods (string, array, map)
    if (objType == "string" || objType == "array" || objType == "map") {
        const bArgList = nGetList(nodeId)
        let bArgs: Array<string> = []
        if (bArgList != "") {
            const bArgIds = bArgList.split(",")
            let bi = 0
            while (bi < bArgIds.length()) {
                bArgs = bArgs.push(`${interpEval(parseInt(bArgIds[bi]))}`)
                bi = bi + 1
            }
        }
        return interpBuiltinMethod(objType, objVal, methodName, bArgs)
    }

    if (objType != "object") {
        println(`[interp] cannot call method '${methodName}' on ${objType}`)
        return interpNewNull()
    }
    const className = interpAsStr(objVal)
    const methodNode = interpFindMethod(className, methodName)
    if (methodNode == 0) {
        println(`[interp] no method '${methodName}' on class ${className}`)
        return interpNewNull()
    }
    const argList = nGetList(nodeId)
    let argVals: Array<string> = []
    let namedArgs = new Map()
    let hasNamed = 0
    if (argList != "") {
        const argIds = argList.split(",")
        let i = 0
        while (i < argIds.length()) {
            const argNodeId = parseInt(argIds[i])
            if (nGetKind(argNodeId) == "NAMED_ARG") {
                hasNamed = 1
                namedArgs.set(nGetS1(argNodeId), `${interpEval(nGetI1(argNodeId))}`)
            } else {
                argVals = argVals.push(`${interpEval(argNodeId)}`)
            }
            i = i + 1
        }
    }
    const savedThis = interpThisVal
    const savedBreak = interpBreakFlag
    const savedContinue = interpContinueFlag
    interpBreakFlag = 0
    interpContinueFlag = 0
    interpThisVal = objVal
    interpPushScope()
    const paramList = nGetList(methodNode)
    if (paramList != "") {
        const params = paramList.split(",")
        let posIdx = 0
        let pi = 0
        while (pi < params.length()) {
            const paramId = parseInt(params[pi])
            const pName = nGetS1(paramId)
            if (hasNamed == 1 && namedArgs.has(pName) == 1) {
                interpSetVar(pName, parseInt(namedArgs.getString(pName)))
            } else if (posIdx < argVals.length()) {
                interpSetVar(pName, parseInt(argVals[posIdx]))
                posIdx = posIdx + 1
            } else {
                const defaultId = nGetI1(paramId)
                if (defaultId > 0) {
                    interpSetVar(pName, interpEval(defaultId))
                } else {
                    interpSetVar(pName, interpNewNull())
                }
            }
            pi = pi + 1
        }
    }
    const bodyId = nGetI1(methodNode)
    if (bodyId > 0) { interpExec(bodyId) }
    let result = interpNewNull()
    if (interpReturnFlag == 1) {
        result = interpReturnVal
        interpReturnFlag = 0
        interpReturnVal = 0
    }
    interpPopScope()
    interpThisVal = savedThis
    interpBreakFlag = savedBreak
    interpContinueFlag = savedContinue
    return result
}

// ── Call Function Value (for higher-order methods) ────────────

function interpCallValue(fnValId: int, args: Array<string>): int {
    if (interpType(fnValId) != "fn") {
        println("[interp] interpCallValue: not a function")
        return interpNewNull()
    }
    const funcNodeId = parseInt(interpAsStr(fnValId))
    const paramList = nGetList(funcNodeId)
    const bodyId = nGetI1(funcNodeId)

    const savedBreak = interpBreakFlag
    const savedContinue = interpContinueFlag
    interpBreakFlag = 0
    interpContinueFlag = 0

    interpPushScope()
    if (paramList != "") {
        const params = paramList.split(",")
        let pi = 0
        while (pi < params.length() && pi < args.length()) {
            interpSetVar(nGetS1(parseInt(params[pi])), parseInt(args[pi]))
            pi = pi + 1
        }
    }

    if (bodyId > 0) { interpExec(bodyId) }

    let result = interpNewNull()
    if (interpReturnFlag == 1) {
        result = interpReturnVal
        interpReturnFlag = 0
        interpReturnVal = 0
    }

    interpPopScope()
    interpBreakFlag = savedBreak
    interpContinueFlag = savedContinue
    return result
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

    if (kind == "FUNC_DECL") {
        const name = nGetS1(nodeId)
        interpSetVar(name, interpNewVal("fn", `${nodeId}`))
        return
    }

    if (kind == "CLASS_DECL") {
        const className = nGetS1(nodeId)
        interpClasses.set(className, `${nodeId}`)
        const parentName = nGetS2(nodeId)
        if (parentName != "") {
            interpClassParents.set(className, parentName)
        }
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
        if (nGetI1(nodeId) > 0) {
            interpReturnVal = interpEval(nGetI1(nodeId))
        } else {
            interpReturnVal = interpNewNull()
        }
        interpReturnFlag = 1
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

    if (kind == "MEMBER_ASSIGN") {
        const objVal = interpEval(nGetI1(nodeId))
        const fieldName = nGetS1(nodeId)
        const op = nGetS2(nodeId)
        const rhs = interpEval(nGetI2(nodeId))
        if (interpType(objVal) == "object") {
            if (op == "ASSIGN") {
                interpSetField(objVal, fieldName, rhs)
            } else {
                const old = interpGetField(objVal, fieldName)
                interpSetField(objVal, fieldName, interpCompoundOp(op, old, rhs))
            }
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

// ── @typeInfo Reflection (D087 Phase 3a) ─────────────────────

function interpBuildMethodParams(mdParts: Array<string>, mName: string): int {
    const paramsArr = interpNewArray("")
    let mdi = 0
    while (mdi < mdParts.length()) {
        const mdId = parseInt(mdParts[mdi])
        if (nGetKind(mdId) == "FUNC_DECL" && nGetS1(mdId) == mName) {
            const pList = nGetList(mdId)
            if (pList != "") {
                const pParts = pList.split(",")
                let pi = 0
                while (pi < pParts.length()) {
                    const pId = parseInt(pParts[pi])
                    if (nGetKind(pId) == "PARAM") {
                        const pObj = interpNewVal("object", "ParamInfo")
                        interpSetField(pObj, "name", interpNewString(nGetS1(pId)))
                        interpSetField(pObj, "type", interpNewString(nGetS2(pId)))
                        // Param annotation (e.g., @PathVariable) — PARAM I4
                        const pAnnId = nGetI4(pId)
                        let pAnnName = ""
                        if (pAnnId > 0 && nGetKind(pAnnId) == "ANNOTATION") {
                            pAnnName = nGetS1(pAnnId)
                        }
                        interpSetField(pObj, "annotation", interpNewString(pAnnName))
                        interpArrayPush(paramsArr, pObj)
                    }
                    pi = pi + 1
                }
            }
            return paramsArr
        }
        mdi = mdi + 1
    }
    return paramsArr
}

// Build interpreter array of AnnotationInfo {name, args} from ANNOTATION_LIST node
function interpBuildAnnotationArray(annListId: int): int {
    const annArr = interpNewArray("")
    if (annListId <= 0 || nGetKind(annListId) != "ANNOTATION_LIST") { return annArr }
    const annListStr = nGetList(annListId)
    if (annListStr == "") { return annArr }
    const annParts = annListStr.split(",")
    let ai = 0
    while (ai < annParts.length()) {
        const aId = parseInt(annParts[ai])
        if (aId > 0 && nGetKind(aId) == "ANNOTATION") {
            const aObj = interpNewVal("object", "AnnotationInfo")
            interpSetField(aObj, "name", interpNewString(nGetS1(aId)))
            interpSetField(aObj, "args", interpNewString(nGetS2(aId)))
            interpArrayPush(annArr, aObj)
        }
        ai = ai + 1
    }
    return annArr
}

function interpBuildTypeInfo(className: string): int {
    if (classFields.has(className) == 0) {
        println(`[interp] @typeInfo: unknown class '${className}'`)
        return interpNewNull()
    }
    const infoId = interpNewVal("object", "ClassInfo")
    interpSetField(infoId, "name", interpNewString(className))

    // Fields
    const fieldsArr = interpNewArray("")
    const fieldStr = classFields.getString(className)
    if (fieldStr != "") {
        const fParts = fieldStr.split(",")
        let fi = 0
        while (fi < fParts.length()) {
            const fName = fParts[fi]
            let fType = "unknown"
            if (classFieldTypes.has(`${className}.${fName}`) == 1) {
                fType = classFieldTypes.getString(`${className}.${fName}`)
            }
            const fieldObj = interpNewVal("object", "FieldInfo")
            interpSetField(fieldObj, "name", interpNewString(fName))
            interpSetField(fieldObj, "type", interpNewString(fType))
            interpArrayPush(fieldsArr, fieldObj)
            fi = fi + 1
        }
    }
    interpSetField(infoId, "fields", fieldsArr)

    // Methods — cache AST method list outside loop
    const methodsArr = interpNewArray("")
    let mdParts: Array<string> = []
    if (classNodeIds.has(className) == 1) {
        const cNodeId = parseInt(classNodeIds.getString(className))
        const mBlock = nGetI2(cNodeId)
        if (mBlock > 0) {
            const mList = nGetList(mBlock)
            if (mList != "") { mdParts = mList.split(",") }
        }
    }
    const methodStr = classMethods.getString(className)
    if (methodStr != "") {
        const mParts = methodStr.split(",")
        let mi = 0
        while (mi < mParts.length()) {
            const mName = mParts[mi]
            let mRetType = "void"
            if (funcRetTypes.has(`${className}_${mName}`) == 1) {
                mRetType = funcRetTypes.getString(`${className}_${mName}`)
            }
            const methodObj = interpNewVal("object", "MethodInfo")
            interpSetField(methodObj, "name", interpNewString(mName))
            interpSetField(methodObj, "returnType", interpNewString(mRetType))
            interpSetField(methodObj, "params", interpBuildMethodParams(mdParts, mName))
            // Method annotations — find FUNC_DECL for this method, extract I4
            let mAnnListId = 0
            let mdx = 0
            while (mdx < mdParts.length()) {
                const mdxId = parseInt(mdParts[mdx])
                if (nGetKind(mdxId) == "FUNC_DECL" && nGetS1(mdxId) == mName) {
                    mAnnListId = nGetI4(mdxId)
                    mdx = mdParts.length()
                } else {
                    mdx = mdx + 1
                }
            }
            interpSetField(methodObj, "annotations", interpBuildAnnotationArray(mAnnListId))
            interpArrayPush(methodsArr, methodObj)
            mi = mi + 1
        }
    }
    interpSetField(infoId, "methods", methodsArr)

    // Class annotations
    let caAnnListId = 0
    if (classNodeIds.has(className) == 1) {
        caAnnListId = nGetI4(parseInt(classNodeIds.getString(className)))
    }
    interpSetField(infoId, "annotations", interpBuildAnnotationArray(caAnnListId))
    return infoId
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
    interpClasses = new Map()
    interpClassParents = new Map()
    interpObjFields = new Map()
    interpThisVal = 0
    interpResetBuiltins()
}

function interpExecComptime(bodyId: int) {
    interpReset()
    interpExec(bodyId)
}
