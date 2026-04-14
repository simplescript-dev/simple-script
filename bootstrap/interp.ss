// interp.ss — comptime value/scope/buffer core
//
// Owns the comptime value heap, the comptime scope stack (with persistent root),
// control-flow flags, and the IR / SS emit buffers. Also hosts the class, object,
// enum and Map registries that the comptime execution path (gen_exprs.ss,
// gen_stmts.ss, gen_decls.ss, gen_assigns.ss, gen_reflect.ss) reads and writes
// directly. Pure value-layer primitives — no AST walking beyond field/method
// lookup helpers. Reflection builders live in gen_reflect.ss.

import { nGetS1, nGetI2, nGetList } from "./parser"

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
let comptimeReleaseMode = 0

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

// ── Enum Support ─────────────────────────────────────────────
// interpEnumValues: "EnumName.VariantName" → value string
// interpEnumTypes: "EnumName" → "1" for string enums
// interpEnumNodes: "EnumName" → AST node ID string

let interpEnumValues = new Map()
let interpEnumTypes = new Map()
let interpEnumNodes = new Map()

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

// ── Binary Op Helpers ────────────────────────────────────────

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

// ── Map Value Storage ────────────────────────────────────────
// Used by the comptime path (gen_exprs.ss) for Map literals and method calls.

let interpMapEntries = new Map()
let interpMapKeyIds = new Map()

function interpNewMap(): int {
    return interpNewVal("map", "")
}

function interpMapSet(mapId: int, keyStr: string, valId: int) {
    const entryKey = `${mapId}:${keyStr}`
    if (interpMapEntries.has(entryKey) != 1) {
        const keyValId = interpNewString(keyStr)
        const listKey = `${mapId}`
        if (interpMapKeyIds.has(listKey) == 1) {
            interpMapKeyIds.set(listKey, `${interpMapKeyIds.getString(listKey)},${keyValId}`)
        } else {
            interpMapKeyIds.set(listKey, `${keyValId}`)
        }
    }
    interpMapEntries.set(entryKey, `${valId}`)
}

function interpMapGet(mapId: int, keyStr: string): int {
    const entryKey = `${mapId}:${keyStr}`
    if (interpMapEntries.has(entryKey) == 1) {
        return parseInt(interpMapEntries.getString(entryKey))
    }
    return interpNewNull()
}

function interpMapHas(mapId: int, keyStr: string): int {
    return interpMapEntries.has(`${mapId}:${keyStr}`)
}

function interpMapDelete(mapId: int, keyStr: string) {
    const entryKey = `${mapId}:${keyStr}`
    if (interpMapEntries.has(entryKey) != 1) { return }
    interpMapEntries.delete(entryKey)
    const listKey = `${mapId}`
    if (interpMapKeyIds.has(listKey) != 1) { return }
    const keyIds = interpMapKeyIds.getString(listKey)
    if (keyIds == "") { return }
    let newIds = ""
    const parts = keyIds.split(",")
    let i = 0
    while (i < parts.length()) {
        if (interpAsStr(parseInt(parts[i])) != keyStr) {
            if (newIds != "") { newIds = `${newIds},` }
            newIds = `${newIds}${parts[i]}`
        }
        i = i + 1
    }
    interpMapKeyIds.set(listKey, newIds)
}

function interpMapGetKeys(mapId: int): int {
    const listKey = `${mapId}`
    if (interpMapKeyIds.has(listKey) != 1) { return interpNewArray("") }
    return interpNewArray(interpMapKeyIds.getString(listKey))
}

function interpMapGetSize(mapId: int): int {
    const listKey = `${mapId}`
    if (interpMapKeyIds.has(listKey) != 1) { return 0 }
    const keyIds = interpMapKeyIds.getString(listKey)
    if (keyIds == "") { return 0 }
    return keyIds.split(",").length()
}

// ── Value Equality ───────────────────────────────────────────

function interpValEquals(a: int, b: int): int {
    const ta = interpType(a)
    const tb = interpType(b)
    if (ta != tb) { return 0 }
    if (ta == "null") { return 1 }
    if (ta == "object" || ta == "array" || ta == "map" || ta == "fn") {
        return a == b ? 1 : 0
    }
    return interpAsStr(a) == interpAsStr(b) ? 1 : 0
}

// ── Comptime Root Scope ───────────────────────────────────────
// Persistent root scope survives across comptime blocks within one compilation.

let interpComptimeRootScope = 0

function interpEnsureComptimeRoot() {
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
    } else {
        interpScopes = [`${interpComptimeRootScope}`]
    }
}

