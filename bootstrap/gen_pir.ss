// Perceus IR — intermediate representation for RC analysis (D019)
// Core: PIR node storage, accessors, type tracking, state management,
// analysis entry point, schedule emission, REUSE queries.
// Lowering (AST→PIR) and expression scanning are in pir_lower.ss.
// Optimization passes are in pir_opt.ss.

import { pirLowerBlock, pirRegisterParams } from "./pir_lower"

// ── PIR node storage (Map-based, same pattern as AST) ────────────

let pirNextId = 0
let pirKind = ""
let pirStr1 = ""
let pirStr2 = ""
let pirStr3 = ""
let pirInt1 = ""
let pirList = ""
let pirReady = 0

function initPir() {
    pirNextId = 0
    pirKind = Map()
    pirStr1 = Map()
    pirStr2 = Map()
    pirStr3 = Map()
    pirInt1 = Map()
    pirList = Map()
    pirReady = 1
    pirVarTypes = Map()
    pirVarReady = 1
    pirSchedule = Map()
    pirScheduleReady = 1
    pirManagedLLVars = Map()
    pirManagedReady = 1
    pirReleasedVars = Map()
    pirReleasedReady = 1
    pirFuncClassVars = ""
    pirActive = 0
    pirMoveStmts = Map()
    pirMoveReady = 1
    pirUniqueAtRelease = Map()
    pirUniqueReady = 1
}

// ── Node creation + accessors ────────────────────────────────────

function newPir(kind: string): int {
    if (pirReady == 0) { initPir() }
    const id = pirNextId
    pirNextId = pirNextId + 1
    pirKind.set(id + "", kind)
    return id
}

function pirGetKind(id: int): string { return pirKind.getString(id + "") }

function pirGetS1(id: int): string {
    if (pirStr1.has(id + "") == 0) { return "" }
    return pirStr1.getString(id + "")
}
function pirGetS2(id: int): string {
    if (pirStr2.has(id + "") == 0) { return "" }
    return pirStr2.getString(id + "")
}
function pirGetS3(id: int): string {
    if (pirStr3.has(id + "") == 0) { return "" }
    return pirStr3.getString(id + "")
}
function pirGetI1(id: int): int {
    if (pirInt1.has(id + "") == 0) { return 0 }
    return parseInt(pirInt1.getString(id + ""))
}

function pirSetS1(id: int, v: string) { pirStr1.set(id + "", v) }
function pirSetS2(id: int, v: string) { pirStr2.set(id + "", v) }
function pirSetS3(id: int, v: string) { pirStr3.set(id + "", v) }
function pirSetI1(id: int, v: int) { pirInt1.set(id + "", `${v}`) }

function pirAppend(buf: string, id: int): string {
    if (buf == "") { return `${id}` }
    return `${buf},${id}`
}

// ── Per-function type tracking ───────────────────────────────────

let pirVarTypes = ""
let pirVarReady = 0

function pirSetType(name: string, t: string) {
    if (pirVarReady == 0) { pirVarTypes = Map(); pirVarReady = 1 }
    pirVarTypes.set(name, t)
}

function pirGetType(name: string): string {
    if (pirVarReady == 0 || pirVarTypes.has(name) == 0) { return "" }
    return pirVarTypes.getString(name)
}

function pirIsClass(t: string): int {
    if (t == "" || t == "int" || t == "double" || t == "bool") { return 0 }
    if (t == "string" || t == "void" || t == "ptr" || t == "auto" || t == "fn") { return 0 }
    if (t == "i64" || t == "i32" || t == "Map" || t == "Set") { return 0 }
    if (t.startsWith("Array<") == 1 || t.startsWith("Map<") == 1) { return 0 }
    if (t.startsWith("Set<") == 1 || t.startsWith("List<") == 1) { return 0 }
    return isUserClass(t)
}

// ── PIR state: schedule, managed vars, release tracking ──────────

let pirSchedule = ""
let pirScheduleReady = 0
let pirManagedLLVars = ""
let pirManagedReady = 0
let pirReleasedVars = ""
let pirReleasedReady = 0
let pirFuncClassVars = ""
let pirActive = 0
let pirMoveStmts = ""
let pirMoveReady = 0
let pirUniqueAtRelease = ""
let pirUniqueReady = 0
let pirReuseAllocs = ""
let pirReuseAllocsReady = 0
let pirReuseDrops = ""
let pirReuseDropsReady = 0
let pirReuseReg = ""
let pirReuseRegReady = 0
let pirPendingReuseReg = ""
let pirPendingReuseClass = ""

// ── Analysis entry point ─────────────────────────────────────────

function pirAnalyzeFunc(bodyId: int, paramList: string, fName: string): int {
    if (pirReady == 0) { initPir() }
    pirNextId = 0
    pirVarTypes = Map()
    pirVarReady = 1
    pirSchedule = Map()
    pirScheduleReady = 1
    pirManagedLLVars = Map()
    pirManagedReady = 1
    pirReleasedVars = Map()
    pirReleasedReady = 1
    pirFuncClassVars = ""
    pirActive = 0
    pirMoveStmts = Map()
    pirMoveReady = 1
    pirUniqueAtRelease = Map()
    pirUniqueReady = 1
    pirReuseAllocs = Map()
    pirReuseAllocsReady = 1
    pirReuseDrops = Map()
    pirReuseDropsReady = 1
    pirReuseReg = Map()
    pirReuseRegReady = 1
    pirPendingReuseReg = ""
    pirPendingReuseClass = ""

    if (pirScanForClassOps(bodyId) == 0) { return 0 }
    pirRegisterParams(paramList)

    const pirBuf = pirLowerBlock(bodyId, "")
    if (pirBuf == "") { return 0 }

    pirLivenessPass(pirBuf, fName)
    pirMoveAnalysis(pirBuf)
    pirUniquenessPass(pirBuf)
    pirReusePass(pirBuf)
    pirActive = 1
    return 1
}

// ── Quick scan: does function body contain class operations? ─────

function pirScanForClassOps(blockId: int): int {
    if (blockId <= 0) { return 0 }
    const sl = nGetList(blockId)
    if (sl == "") { return 0 }
    const parts = sl.split(",")
    for (p in parts) {
        const sid = parseInt(p)
        if (sid <= 0) { continue }
        if (pirStmtHasClassOp(sid) == 1) { return 1 }
    }
    return 0
}

function pirStmtHasClassOp(id: int): int {
    const kind = nGetKind(id)
    if (kind == "VAR_DECL") {
        const initId = nGetI1(id)
        if (initId > 0) {
            const initKind = nGetKind(initId)
            if (initKind == "NEW_EXPR") {
                const cn = nGetS1(initId)
                if (cn != "Map" && cn != "Set" && cn != "Math" && classFields.has(cn) == 1) {
                    return 1
                }
            }
            // CALL/METHOD_CALL returning a class type
            if (initKind == "CALL" || initKind == "METHOD_CALL" || initKind == "IDENT") {
                const retType = inferType(initId)
                if (pirIsClass(retType) == 1) { return 1 }
            }
        }
        const ta = nGetS3(id)
        if (ta != "" && pirIsClass(ta) == 1) { return 1 }
    }
    if (kind == "IF") {
        if (pirScanForClassOps(nGetI2(id)) == 1) { return 1 }
        if (nGetI3(id) > 0) { return pirScanForClassOps(nGetI3(id)) }
    }
    if (kind == "FOR") { return pirScanForClassOps(nGetI4(id)) }
    if (kind == "FOR_IN") { return pirScanForClassOps(nGetI2(id)) }
    if (kind == "WHILE") { return pirScanForClassOps(nGetI2(id)) }
    if (kind == "DO_WHILE") { return pirScanForClassOps(nGetI1(id)) }
    return 0
}

// ── Schedule emission ────────────────────────────────────────────

// Emit RC_DEC for variables scheduled after this AST statement
function pirEmitScheduled(stmtId: int) {
    if (pirActive == 0 || pirScheduleReady == 0) { return }
    if (pirSchedule.has(stmtId + "") == 0) { return }
    const schedule = pirSchedule.getString(stmtId + "")
    if (schedule == "") { return }
    const parts = schedule.split("|")
    for (p in parts) {
        if (p == "") { continue }
        const varName = pirParseEntryVar(p)
        const ssType = pirParseEntryType(p)
        if (varName == "" || ssType == "") { continue }
        const llName = llVarName(varName)
        if (llName == varName) { continue }
        const r = nextReg()
        emitIR(`  ${r} = load ptr, ptr %${llName}, align 8`)
        if (pirIsUniqueAtRelease(varName) == 1) {
            if (pirIsReuseDrop(varName) == 1) {
                // REUSE: drop fields only, keep memory for upcoming allocation
                emitIR(`  call void @ss_drop_fields_${ssType}(ptr ${r})`)
                const reuseAllocVar = pirReuseDrops.getString(varName)
                pirSetReuseReg(reuseAllocVar, r)
            } else {
                // Provably unique (rc==1) — direct drop, skip ss_release overhead
                emitIR(`  call void @ss_drop_${ssType}(ptr ${r})`)
            }
        } else {
            emitReleaseForType(r, ssType)
        }
        pirReleasedVars.set(varName, "1")
    }
}

// Emit RC_DEC for all unreleased PIR-managed vars (at return / function exit)
// NOTE: always use ss_release here, never direct drop — unreleased vars at
// function exit include escaped (returned) vars whose rc was already bumped
// by ss_retain. Direct drop would ignore rc and destroy a live object.
function pirEmitReturnCleanup() {
    if (pirActive == 0 || pirFuncClassVars == "") { return }
    const parts = pirFuncClassVars.split(",")
    for (v in parts) {
        if (v == "") { continue }
        if (pirReleasedVars.has(v) == 1) { continue }
        const ssType = pirGetType(v)
        if (ssType == "" || pirIsClass(ssType) == 0) { continue }
        const llName = llVarName(v)
        if (llName == v) { continue }
        const r = nextReg()
        emitIR(`  ${r} = load ptr, ptr %${llName}, align 8`)
        emitReleaseForType(r, ssType)
    }
}

// Check if LLVM variable name is PIR-managed (skip old RC tracking)
function pirIsManaged(llName: string): int {
    if (pirActive == 0 || pirManagedReady == 0) { return 0 }
    return pirManagedLLVars.has(llName)
}

// Check if variable is provably unique (rc==1) at release time
function pirIsUniqueAtRelease(varName: string): int {
    if (pirActive == 0 || pirUniqueReady == 0) { return 0 }
    return pirUniqueAtRelease.has(varName)
}

// Check if AST stmt is a move assignment (skip retain in genVarDecl)
function pirIsMoveStmt(astId: int): int {
    if (pirActive == 0 || pirMoveReady == 0) { return 0 }
    return pirMoveStmts.has(astId + "")
}

function pirMarkManaged(llName: string) {
    if (pirManagedReady == 0) { pirManagedLLVars = Map(); pirManagedReady = 1 }
    pirManagedLLVars.set(llName, "1")
}

// ── Schedule entry parsing ("var:type" format) ─────────────────

function pirParseEntryVar(entry: string): string {
    const ci = entry.indexOf(":")
    if (ci < 0) { return "" }
    return entry.substring(0, ci)
}

function pirParseEntryType(entry: string): string {
    const ci = entry.indexOf(":")
    if (ci < 0) { return "" }
    return entry.substring(ci + 1, entry.length() - ci - 1)
}

// ── REUSE queries ───────────────────────────────────────────────

// Check if this allocation should use reuse constructor
function pirIsReuseAlloc(allocVar: string): int {
    if (pirActive == 0 || pirReuseAllocsReady == 0) { return 0 }
    return pirReuseAllocs.has(allocVar)
}

// Get reuse info: returns "dropVarName:className" or ""
function pirGetReuseInfo(allocVar: string): string {
    if (pirReuseAllocsReady == 0 || pirReuseAllocs.has(allocVar) == 0) { return "" }
    return pirReuseAllocs.getString(allocVar)
}

// Check if this drop should use fields-only release (keep memory for reuse)
function pirIsReuseDrop(dropVar: string): int {
    if (pirReuseDropsReady == 0 || pirReuseDrops.has(dropVar) == 0) { return 0 }
    return 1
}

// Store LLVM register from drop for later use by reuse constructor
function pirSetReuseReg(allocVar: string, reg: string) {
    if (pirReuseRegReady == 0) { pirReuseReg = Map(); pirReuseRegReady = 1 }
    pirReuseReg.set(allocVar, reg)
}

// Retrieve stored LLVM register for reuse constructor
function pirGetReuseReg(allocVar: string): string {
    if (pirReuseRegReady == 0 || pirReuseReg.has(allocVar) == 0) { return "" }
    return pirReuseReg.getString(allocVar)
}
