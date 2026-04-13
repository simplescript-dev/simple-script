// interp.ss — SimpleScript AST Interpreter core
//
// Value storage, scope stack, class/object infrastructure, control flow flags,
// comptime buffers, and reset/entry points. Expression evaluation, function calls,
// statement execution, and reflection are in separate files.

import { nGetKind, nGetS1, nGetS2, nGetI1, nGetI2, nGetI3, nGetI4, nGetList } from "./parser"
import { interpBuiltinMethod, interpNewMap, interpResetBuiltins } from "./interp_builtins"
import { interpEval } from "./interp_eval"
import { interpCall, interpCallValue } from "./interp_calls"
import { interpExec } from "./interp_exec"
import { interpBuildTypeInfo, interpBuildAnnotationArray } from "./interp_reflect"

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
let interpThrowFlag = 0
let interpThrowVal = 0

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
let comptimeReleaseMode = 0

function interpGetComptimeSS(): string { return comptimeSS }
function interpClearComptimeSS() { comptimeSS = "" }

function interpShouldStop(): int {
    return (interpBreakFlag == 1 || interpContinueFlag == 1 || interpReturnFlag == 1 || interpThrowFlag == 1) ? 1 : 0
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

// ── Reset ──────────────────────────────────────────────────────

// Persistent comptime root scope — survives across comptime blocks
let interpComptimeRootScope = 0

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
    interpThrowFlag = 0
    interpThrowVal = 0
    comptimeIR = ""
    comptimeSS = ""
    interpClasses = new Map()
    interpClassParents = new Map()
    interpObjFields = new Map()
    interpThisVal = 0
    interpComptimeRootScope = 0
    interpResetBuiltins()
}

function interpExecComptime(bodyId: int) {
    interpBreakFlag = 0
    interpContinueFlag = 0
    interpReturnFlag = 0
    interpReturnVal = 0
    interpThrowFlag = 0
    interpThrowVal = 0
    // Ensure persistent root scope exists
    if (interpComptimeRootScope == 0) {
        interpScopeNext = interpScopeNext + 1
        interpComptimeRootScope = interpScopeNext
        interpScopes = [`${interpComptimeRootScope}`]
        // Inject predefined compile-time constants
        let targetOS = getenv("SS_TARGET_OS")
        if (targetOS == "") { targetOS = "linux" }
        let targetArch = getenv("SS_TARGET_ARCH")
        if (targetArch == "") { targetArch = "x86_64" }
        interpSetVar("OS", interpNewString(targetOS))
        interpSetVar("ARCH", interpNewString(targetArch))
        interpSetVar("DEBUG", interpNewInt(comptimeReleaseMode == 0 ? 1 : 0))
        interpSetVar("COMPILER_VERSION", interpNewString("0.1.0"))
    }
    interpScopes = [`${interpComptimeRootScope}`]
    // Execute body statements directly in root scope (skip BLOCK push/pop)
    if (nGetKind(bodyId) == "BLOCK") {
        const list = nGetList(bodyId)
        if (list != "") {
            const stmts = list.split(",")
            let i = 0
            while (i < stmts.length()) {
                interpExec(parseInt(stmts[i]))
                if (interpShouldStop() == 1) { break }
                i = i + 1
            }
        }
    } else {
        interpExec(bodyId)
    }
    // Root scope persists for next comptime block
    interpScopes = [`${interpComptimeRootScope}`]
}
