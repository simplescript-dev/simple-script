// SimpleScript Bootstrap Code Generator
// Walks the Map-based AST and produces LLVM IR text (.ll format).
// Uses SSA registers (%1, %2, ...) and named allocas for variables.

import { nGetKind, nGetS1, nGetS2, nGetS3, nGetI1, nGetI2, nGetI3, nGetI4, nGetList, classTypeParams } from "./parser"
import { interpClearComptimeIR, interpClearComptimeSS } from "./interp"

// ── State ─────────────────────────────────────────────────────

let irBuf = ""
let strConsts = ""
let strCount = 0
let irOutFile = ""
let strOutFile = ""
let regCount = 0
let regTable: Array<string> = []
let ctVars = new Map()
let ctInvalidated = new Map()
let ctFuncNodes = new Map()
let ctScopeStack: Array<string> = []
let ctCallCounter = 0
let comptimeDepth = 0
let labelCount = 0
let varTypes = ""
let varTypesReady = 0
let currentFunc = ""
let terminated = 0
let varCounter = 0
let varAliases = ""
let globalAliases = ""
let varAliasReady = 0

function initVarAliases() {
    if (varAliasReady == 1) { return }
    varAliases = Map()
    globalAliases = Map()
    varAliasReady = 1
}

function allocVarName(name: string): string {
    initVarAliases()
    varCounter = varCounter + 1
    const llName = `${name}.${varCounter}`
    varAliases.set(name, llName)
    return llName
}

function llVarName(name: string): string {
    initVarAliases()
    if (varAliases.has(name) == 1) {
        return varAliases.getString(name)
    }
    if (globalAliases.has(name) == 1) {
        return globalAliases.getString(name)
    }
    return name
}
// Returns "%" + name or "@name" for globals
function varRef(name: string): string {
    const ln = llVarName(name)
    if (ln.startsWith("@") == 1) { return ln }
    return `%${ln}`
}

// Function registry moved to gen_registry.ss (funcRetTypes, funcDefaults, funcParamCount, etc.)
let breakLabel = ""
let continueLabel = ""
// RC state moved to gen_rc.ss (localPtrVars, rcBlockDepth, blockPtrVarStack, etc.)
let enumValues = ""
let enumTypes = ""
let enumDeclNodes = ""
let enumReady = 0
let isThreadClosure = 0    // D082 Phase 3: set to 1 when generating Thread.start arrow

// Inline comptime expression cache (evaluated once in inferType, read in genExpr)
let comptimeExprType = new Map()
let comptimeExprLiteral = new Map()

// Compile-time constant bindings (D088: for-in unrolling propagates field names)
let comptimeConsts = new Map()

// Generic function state (monomorphization)
let genericFuncNodes = ""
let specializedFuncs = ""
let genericTypeSubs = ""
let genericSpecDefs = ""
let specFuncName = ""
// Generic class state (monomorphization)
let genericClassNodes = ""
let specializedClasses = ""
let specClassName = ""

function initCodegen() {
    if (varTypesReady == 1) { return }
    varTypes = Map()
    varTypesReady = 1
}

function emitIR(s: string) {
    if (irOutFile != "") {
        appendFile(irOutFile, `${s}\n`)
    } else {
        irBuf = `${irBuf}${s}\n`
    }
}

function nextReg(): string {
    regCount = regCount + 1
    return `%${regCount}`
}

function nextLabel(prefix: string): string {
    labelCount = labelCount + 1
    return `${prefix}.${labelCount}`
}

// ── Tagged Value Infrastructure (D089) ──────────────────────

function ctVal(interpId: int): int {
    return interpId | 1073741824  // bit 30
}

function isCt(v: int): int {
    return (v & 1073741824) != 0 ? 1 : 0  // bit 30
}

function payload(v: int): int {
    return v & 1073741823  // bits 0-29
}

function constVal(s: string): int {
    regTable.push(s)
    return regTable.length()
}

function reg(v: int): string {
    if (isCt(v) == 1) { return materialize(payload(v)) }
    return regTable[payload(v) - 1]
}

function materialize(interpValId: int): string {
    const t = interpType(interpValId)
    if (t == "int") { return `${interpAsInt(interpValId)}` }
    if (t == "string") { return addStringConst(interpAsStr(interpValId)) }
    if (t == "bool") { return interpAsBool(interpValId) == 1 ? "1" : "0" }
    if (t == "double") {
        const dStr = tvD1.getString(interpValId + "")
        if (dStr.indexOf(".") < 0) { return `${dStr}.0` }
        return dStr
    }
    if (t == "null") { return "null" }
    return "0"
}

// ── TypedValue Storage (D092 Phase 0) ────────────────────────

let nextTvId = 1
let tvKind = ""
let tvI1: Array<int> = []
let tvI2: Array<int> = []
let tvI3: Array<int> = []
let tvS1 = ""
let tvS2 = ""
let tvD1 = ""
let tvList = ""
let tvArrElem = ""
let tvMap = ""
let tvReady = 0

function initTypedValue() {
    if (tvReady == 1) { return }
    tvKind = new Map()
    tvS1 = new Map()
    tvS2 = new Map()
    tvD1 = new Map()
    tvList = new Map()
    tvArrElem = new Map()
    tvMap = new Map()
    // index 0 is unused (tv IDs start at 1)
    tvI1.push(0)
    tvI2.push(0)
    tvI3.push(0)
    tvReady = 1
}

function allocTv(kind: string): int {
    initTypedValue()
    const id = nextTvId
    nextTvId = nextTvId + 1
    tvKind.set(id + "", kind)
    tvI1.push(0)
    tvI2.push(0)
    tvI3.push(0)
    return id
}

function newTvInt(n: int): int {
    const id = allocTv("int")
    tvI1[id] = n
    return id
}

function newTvString(s: string): int {
    const id = allocTv("string")
    tvS1.set(id + "", s)
    return id
}

function newTvBool(b: int): int {
    const id = allocTv("bool")
    tvI1[id] = b
    return id
}

function newTvNull(): int {
    return allocTv("null")
}

function newTvArray(initCsv: string): int {
    const id = allocTv("array")
    if (initCsv != "") {
        const parts = initCsv.split(",")
        let i = 0
        while (i < parts.length()) {
            tvArrElem.set(`${id}:${i}`, parts[i])
            i = i + 1
        }
        tvI2[id] = parts.length()
    }
    return id
}

// ── TypedValue Accessor Primitive (D092 Phase 1 最小子集) ────
// 仅含 Phase 2 sub-a 的 4 个 delegate 所需 scalar accessor。
// tvField* / tvArray* / tvKeys / tvSize 留给 Phase 3-5 消费者
// 按需添加，避免 API 设计基于猜测。

function tvKindOf(id: int): string {
    initTypedValue()
    return tvKind.getString(id + "")
}

function tvIntOf(id: int): int {
    initTypedValue()
    return tvI1[id]
}

function tvStringOf(id: int): string {
    initTypedValue()
    return tvS1.getString(id + "")
}

// ── interp* delegate (D092 Phase 2 sub-a) ────────────────────
// 保留 interp* 前缀让现有 callsite 自动 resolve，定义搬到 codegen.ss
// 内部，底层改走 Phase 1 的 TypedValue accessor。参数是 ctVal payload，
// clean slate 后语义迁移为 TypedValue id。

function interpType(id: int): string {
    return tvKindOf(id)
}

function interpAsInt(id: int): int {
    return tvIntOf(id)
}

function interpAsStr(id: int): string {
    return tvStringOf(id)
}

function interpAsBool(id: int): int {
    return tvIntOf(id)
}

// ── interp* value/compound delegate (D092 Phase 2 sub-b) ─────
// 保留 interp* 前缀让 gen_exprs.ss / gen_assigns.ss / gen_stmts.ss
// 的调用点自动 resolve，底层走 Phase 0/1 的 TypedValue 存储层。

function interpNewInt(n: int): int {
    return newTvInt(n)
}

function interpNewString(s: string): int {
    return newTvString(s)
}

function interpNewBool(b: int): int {
    return newTvBool(b)
}

function interpNewNull(): int {
    return newTvNull()
}

function interpNewArray(init: string): int {
    return newTvArray(init)
}

// op 是 parse_stmts.ss 里 ASSIGN/MEMBER_ASSIGN 的 raw token 名
// (PLUS_ASSIGN / MINUS_ASSIGN / STAR_ASSIGN / ...)，不是 BINARY 的 Add/Sub
function interpCompoundOp(op: string, lid: int, rid: int): int {
    if (tvKindOf(lid) == "int" && tvKindOf(rid) == "int") {
        const a = tvIntOf(lid)
        const b = tvIntOf(rid)
        if (op == "PLUS_ASSIGN") { return newTvInt(a + b) }
        if (op == "MINUS_ASSIGN") { return newTvInt(a - b) }
        if (op == "STAR_ASSIGN") { return newTvInt(a * b) }
        if (op == "SLASH_ASSIGN") { return newTvInt(a / b) }
        if (op == "PERCENT_ASSIGN") { return newTvInt(a % b) }
    }
    return newTvNull()
}

// ── interp* state (D092 Phase 2 sub-c) ───────────────────────
// tvI3[id] 锁定为 object/map 的 field/entry 个数（Phase 0 第二次锁定）。

let interpReturnFlag = 0
let interpReturnVal = 0
let interpBreakFlag = 0
let interpContinueFlag = 0
let interpCurrentMethodClass = ""
let interpClasses = new Map()
let interpClassParents = new Map()
let interpEnumValues = new Map()
let interpEnumTypes = new Map()
let interpEnumNodes = new Map()

function interpShouldStop(): int {
    if (interpReturnFlag == 1) { return 1 }
    if (interpBreakFlag == 1) { return 1 }
    if (interpContinueFlag == 1) { return 1 }
    return 0
}

// continue 由循环体自行消费，不向循环外层冒泡，因此不计入 exit 判据
function interpCheckLoopExit(): int {
    if (interpReturnFlag == 1) { return 1 }
    if (interpBreakFlag == 1) { return 1 }
    return 0
}

// ── interp* field / collection delegate (D092 Phase 2 sub-c) ─
// object 和 map 共享 tvList[id] = CSV of keys、tvMap[id|key] = child tvId、
// tvI3[id] = entry count 的存储契约。array 用 tvList[id] = CSV of tvIds、
// tvI2[id] = length，由 sub-b 锁定。

function interpGetField(objId: int, name: string): int {
    const key = objId + "|" + name
    if (tvMap.has(key) == 0) { return newTvNull() }
    return parseInt(tvMap.getString(key))
}

function interpSetField(objId: int, name: string, valTvId: int) {
    const key = objId + "|" + name
    if (tvMap.has(key) == 0) {
        const idStr = objId + ""
        tvList.set(idStr, listAppendStr(tvList.getString(idStr), name))
        tvI3[objId] = tvI3[objId] + 1
    }
    tvMap.set(key, valTvId + "")
}

function interpArrayPush(arrId: int, valTvId: int): int {
    const len = tvI2[arrId]
    tvArrElem.set(`${arrId}:${len}`, `${valTvId}`)
    tvI2[arrId] = len + 1
    return arrId
}

function interpArraySet(arrId: int, idx: int, valTvId: int) {
    if (idx < 0 || idx >= tvI2[arrId]) { return }
    tvArrElem.set(`${arrId}:${idx}`, `${valTvId}`)
}

function interpArrayLen(arrId: int): int {
    return tvI2[arrId]
}

function interpArrayGet(arrId: int, idx: int): int {
    if (idx < 0 || idx >= tvI2[arrId]) { return newTvNull() }
    const key = `${arrId}:${idx}`
    if (tvArrElem.has(key) == 0) { return newTvNull() }
    return parseInt(tvArrElem.getString(key))
}

function interpNewMap(): int {
    const id = allocTv("map")
    tvList.set(id + "", "")
    return id
}

function interpMapSet(mapId: int, key: string, valTvId: int) {
    interpSetField(mapId, key, valTvId)
}

function interpMapGet(mapId: int, key: string): int {
    return interpGetField(mapId, key)
}

function interpMapHas(mapId: int, key: string): int {
    return tvMap.has(mapId + "|" + key)
}

function interpMapDelete(mapId: int, key: string) {
    const fullKey = mapId + "|" + key
    if (tvMap.has(fullKey) == 0) { return }
    const cur = tvList.getString(mapId + "")
    const parts = cur.split(",")
    let newCsv = ""
    let i = 0
    while (i < parts.length()) {
        if (parts[i] != key) {
            if (newCsv == "") { newCsv = parts[i] }
            else { newCsv = newCsv + "," + parts[i] }
        }
        i = i + 1
    }
    tvList.set(mapId + "", newCsv)
    tvMap.delete(fullKey)
    tvI3[mapId] = tvI3[mapId] - 1
}

function interpMapGetKeys(mapId: int): int {
    const arrId = newTvArray("")
    const cur = tvList.getString(mapId + "")
    if (cur == "") { return arrId }
    const parts = cur.split(",")
    let i = 0
    while (i < parts.length()) {
        interpArrayPush(arrId, newTvString(parts[i]))
        i = i + 1
    }
    return arrId
}

function interpMapGetSize(mapId: int): int {
    return tvI3[mapId]
}

// ── interp* comptime buffer + value coercion (D092 Phase 2 sub-d) ─
// gen_exprs.ss 在 comptimeDepth > 0 时往 comptimeIR/SS 积累代码，
// @comptime 块结束由 interpGet*Comptime* 读出后清空。

let comptimeIR = ""
let comptimeSS = ""

function interpGetComptimeIR(): string {
    return comptimeIR
}

function interpGetComptimeSS(): string {
    return comptimeSS
}

function interpClearComptimeIR() {
    comptimeIR = ""
}

function interpClearComptimeSS() {
    comptimeSS = ""
}

// Phase 3 建立 scope stack 根帧；sub-d 阶段 interpVars 作为 flat scope 够用
function interpEnsureComptimeRoot() {
}

function interpTruthy(id: int): int {
    const k = tvKindOf(id)
    if (k == "null") { return 0 }
    if (k == "bool") { return tvIntOf(id) }
    if (k == "int") { return tvIntOf(id) != 0 ? 1 : 0 }
    if (k == "string") { return tvStringOf(id) != "" ? 1 : 0 }
    if (k == "array") { return tvI2[id] > 0 ? 1 : 0 }
    if (k == "map") { return tvI3[id] > 0 ? 1 : 0 }
    return 1
}

function interpNewDouble(d: double): int {
    const id = allocTv("double")
    tvD1.set(id + "", `${d}`)
    return id
}

// interpVars 是 comptime 变量的全局 scope store；scope stack 留给 Phase 3
let interpVars = new Map()
let interpThisVal = 0
let interpLastFoundMethodClass = ""
let comptimeReleaseMode = 0

function interpFindScopeKey(name: string): string {
    if (interpVars.has(name) == 1) { return name }
    return ""
}

function interpNewVal(kind: string, payload: string): int {
    if (kind == "object") {
        const id = allocTv("object")
        tvS1.set(id + "", payload)
        tvList.set(id + "", "")
        return id
    }
    if (kind == "fn") {
        const id = allocTv("fn")
        tvI1[id] = parseInt(payload)
        return id
    }
    return newTvNull()
}

function interpToStr(id: int): string {
    const k = tvKindOf(id)
    if (k == "int") { return `${tvIntOf(id)}` }
    if (k == "string") { return tvStringOf(id) }
    if (k == "bool") { return tvIntOf(id) == 1 ? "true" : "false" }
    if (k == "null") { return "null" }
    if (k == "double") { return tvD1.getString(id + "") }
    return ""
}

// interpIntOp / interpDoubleOp 接受 raw int/double（不是 tvId），
// 由调用方从 TypedValue 里提取后传入，这是常量折叠路径的专用 API
// —— 区别于 sub-b 的 interpCompoundOp (tvId → tvId)。

// op 名对齐 parse_exprs.ss 的 BINARY nSetS1 约定（Add/Sub/Mul/...），
// 不是 PLUS/MINUS 等 token 名，也不是 Plus/Minus 等随手发明名
function interpIntOp(op: string, a: int, b: int): int {
    if (op == "Add") { return newTvInt(a + b) }
    if (op == "Sub") { return newTvInt(a - b) }
    if (op == "Eq") { return newTvBool(a == b ? 1 : 0) }
    if (op == "Ne") { return newTvBool(a != b ? 1 : 0) }
    if (op == "Lt") { return newTvBool(a < b ? 1 : 0) }
    if (op == "Gt") { return newTvBool(a > b ? 1 : 0) }
    if (op == "Le") { return newTvBool(a <= b ? 1 : 0) }
    if (op == "Ge") { return newTvBool(a >= b ? 1 : 0) }
    if (op == "Mul") { return newTvInt(a * b) }
    if (op == "Div") { return newTvInt(a / b) }
    if (op == "Mod") { return newTvInt(a % b) }
    if (op == "BitAnd") { return newTvInt(a & b) }
    if (op == "BitOr") { return newTvInt(a | b) }
    if (op == "BitXor") { return newTvInt(a ^ b) }
    if (op == "Shl") { return newTvInt(a << b) }
    if (op == "Shr") { return newTvInt(a >> b) }
    // gen_exprs.ss genIntBinary 用 lshr (zero-fill)，与 SS 的 >>> 运算符对齐
    if (op == "UShr") { return newTvInt(a >>> b) }
    if (op == "Pow") {
        let pr = 1; let pi = 0
        while (pi < b) { pr = pr * a; pi = pi + 1 }
        return newTvInt(pr)
    }
    return newTvNull()
}

function interpDoubleOp(op: string, a: double, b: double): int {
    if (op == "Add") { return interpNewDouble(a + b) }
    if (op == "Sub") { return interpNewDouble(a - b) }
    if (op == "Mul") { return interpNewDouble(a * b) }
    if (op == "Div") { return interpNewDouble(a / b) }
    if (op == "Eq") { return newTvBool(a == b ? 1 : 0) }
    if (op == "Ne") { return newTvBool(a != b ? 1 : 0) }
    if (op == "Lt") { return newTvBool(a < b ? 1 : 0) }
    if (op == "Gt") { return newTvBool(a > b ? 1 : 0) }
    if (op == "Le") { return newTvBool(a <= b ? 1 : 0) }
    if (op == "Ge") { return newTvBool(a >= b ? 1 : 0) }
    if (op == "Pow") {
        let pr = 1.0; let pi = 0; const pe = parseInt(`${b}`)
        while (pi < pe) { pr = pr * a; pi = pi + 1 }
        return interpNewDouble(pr)
    }
    return newTvNull()
}

// TypeInfo 注册表由 Phase 3 建立；sub-d 阶段返回 null 占位
function interpBuildTypeInfo(typeName: string): int {
    return newTvNull()
}

function interpGetReturnFlag(): int {
    return interpReturnFlag
}

function interpGetReturnVal(): int {
    return interpReturnVal
}

function interpValEquals(lid: int, rid: int): int {
    const lk = tvKindOf(lid)
    const rk = tvKindOf(rid)
    if (lk != rk) { return 0 }
    if (lk == "int" || lk == "bool") { return tvIntOf(lid) == tvIntOf(rid) ? 1 : 0 }
    if (lk == "string") { return tvStringOf(lid) == tvStringOf(rid) ? 1 : 0 }
    if (lk == "null") { return 1 }
    if (lk == "double") { return tvD1.getString(lid + "") == tvD1.getString(rid + "") ? 1 : 0 }
    return lid == rid ? 1 : 0
}

// class 反射 stub：真正的注册表查询留给 Phase 3 (eval core)，
// sub-d 只保证符号 resolve，调用路径走 fallback (println 错误)。

function interpCollectFields(className: string): string {
    if (interpClasses.has(className) != 1) { return "" }
    let fields = ""
    let cur = className
    while (cur != "") {
        const cid = parseInt(interpClasses.getString(cur))
        const paramList = nGetList(cid)
        if (paramList != "") {
            if (fields == "") { fields = paramList }
            else { fields = `${paramList},${fields}` }
        }
        cur = interpClassParents.has(cur) == 1 ? interpClassParents.getString(cur) : ""
    }
    return fields
}

function interpCtFieldsArray(className: string): int {
    return newTvArray("")
}

function interpFindMethod(className: string, methodName: string): int {
    let cur = className
    while (cur != "") {
        if (interpClasses.has(cur) == 1) {
            const cid = parseInt(interpClasses.getString(cur))
            const mbId = nGetI2(cid)
            if (mbId > 0) {
                const mList = nGetList(mbId)
                if (mList != "") {
                    const mParts = mList.split(",")
                    for (mp in mParts) {
                        const mId = parseInt(mp)
                        if (mId > 0 && nGetKind(mId) == "FUNC_DECL" && nGetS1(mId) == methodName) {
                            interpLastFoundMethodClass = cur
                            return mId
                        }
                    }
                }
            }
        }
        cur = interpClassParents.has(cur) == 1 ? interpClassParents.getString(cur) : ""
    }
    return 0
}

// framework annotation handling 留给 Phase 3 eval core；sub-e 只承接符号
let annClassNodeIds: Array<string> = []
let annClassAnnNames: Array<string> = []

function registerAnnotation(annName: string, handlerFuncName: string) {
}

function collectClassAnnotations(classId: int) {
}

function emitAnnotationInits() {
}

// ── IR Builder Helpers ───────────────────────────────────────

function irLabel(name: string) {
    emitIR(`${name}:`)
}

function irAlloca(dst: string, ty: string, align: int) {
    emitIR(`  %${dst} = alloca ${ty}, align ${align}`)
}

function irLoad(dst: string, ty: string, ptr: string) {
    emitIR(`  %${dst} = load ${ty}, ptr ${ptr}`)
}

function irStore(ty: string, val: string, ptr: string) {
    emitIR(`  store ${ty} ${val}, ptr ${ptr}`)
}

function irGEP(dst: string, baseTy: string, base: string, idx: string) {
    emitIR(`  %${dst} = getelementptr ${baseTy}, ptr ${base}, i64 ${idx}`)
}

function irICmp(dst: string, op: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = icmp ${op} ${ty} ${a}, ${b}`)
}

function irBr(label: string) {
    emitIR(`  br label %${label}`)
}

function irBrCond(cond: string, thenL: string, elseL: string) {
    emitIR(`  br i1 %${cond}, label %${thenL}, label %${elseL}`)
}

function irRet(ty: string, val: string) {
    emitIR(`  ret ${ty} ${val}`)
}

function irRetVoid() {
    emitIR("  ret void")
}

function irAdd(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = add ${ty} ${a}, ${b}`)
}

function irSub(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = sub ${ty} ${a}, ${b}`)
}

function irMul(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = mul ${ty} ${a}, ${b}`)
}

function irCall(dst: string, retTy: string, func: string, args: string) {
    emitIR(`  %${dst} = call ${retTy} @${func}(${args})`)
}

function irCallVoid(func: string, args: string) {
    emitIR(`  call void @${func}(${args})`)
}

function irSext(dst: string, fromTy: string, val: string, toTy: string) {
    emitIR(`  %${dst} = sext ${fromTy} ${val} to ${toTy}`)
}

function irZext(dst: string, fromTy: string, val: string, toTy: string) {
    emitIR(`  %${dst} = zext ${fromTy} ${val} to ${toTy}`)
}

function irSelect(dst: string, cond: string, ty: string, thenVal: string, elseVal: string) {
    emitIR(`  %${dst} = select i1 %${cond}, ${ty} ${thenVal}, ${ty} ${elseVal}`)
}

function irSDiv(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = sdiv ${ty} ${a}, ${b}`)
}

function irOr(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = or ${ty} ${a}, ${b}`)
}

function irTrunc(dst: string, fromTy: string, val: string, toTy: string) {
    emitIR(`  %${dst} = trunc ${fromTy} ${val} to ${toTy}`)
}

function irPtrToInt(dst: string, val: string, toTy: string) {
    emitIR(`  %${dst} = ptrtoint ptr ${val} to ${toTy}`)
}

function irIntToPtr(dst: string, fromTy: string, val: string) {
    emitIR(`  %${dst} = inttoptr ${fromTy} ${val} to ptr`)
}

// Load array data buffer pointer from header slot 2
function irLoadArrayData(dst: string, arr: string) {
    irGEP(`${dst}p`, "i64", arr, "2")
    irLoad(`${dst}_i`, "i64", `%${dst}p`)
    irIntToPtr(dst, "i64", `%${dst}_i`)
}

function addStringConst(value: string): string {
    const name = `@.str.${strCount}`
    strCount = strCount + 1
    // Escape the string for LLVM IR c"..." format
    let escaped = ""
    let i = 0
    const sLen = value.length()
    while (i < sLen) {
        const ch = value.charAt(i)
        if (ch == "\n") { escaped = escaped + "\\0A"
        } else if (ch == "\r") { escaped = escaped + "\\0D"
        } else if (ch == "\t") { escaped = escaped + "\\09"
        } else if (ch == "\\") { escaped = escaped + "\\5C"
        } else if (ch == "\"") { escaped = escaped + "\\22"
        } else { escaped = escaped + ch }
        i = i + 1
    }
    const line = `${name} = constant [${sLen + 1} x i8] c"${escaped}\\00"\n`
    // strOutFile overrides irOutFile for string constant output (used by arrow functions)
    const strTarget = strOutFile ?? irOutFile
    if (strTarget != "") {
        appendFile(`${strTarget}.str`, line)
    } else {
        strConsts = strConsts + line
    }
    return name
}

// ── Runtime (generated by emitRuntimeDefs in gen_runtime.ss) ─

// ── Public API ────────────────────────────────────────────────

// Shared codegen passes
// Register a single FUNC_DECL node: retType, paramCount, overloads, generics, defaults.
// Used by registerAllDecls and comptime @comptimeEmit processing.
function registerFuncDeclNode(sid: int) {
    const fname = nGetS1(sid)
    ctFuncNodes.set(fname, `${sid}`)
    let fret = stripNullableCG(nGetS2(sid))
    if (fret == "") { fret = "void" }
    funcRetTypes.set(fname, fret)
    const fparams = nGetList(sid)
    const fSig = paramSig(fparams)
    if (fSig != "") {
        funcRetTypes.set(`${fname}_${fSig}`, fret)
        funcParamCount.set(`${fname}_${fSig}`, funcParamCount.getString(fname) ?? "0")
    }
    trackOverload(fname)
    if (nGetS3(sid) != "") {
        genericFuncNodes.set(fname, `${sid}`)
    }
    if (fparams != "") {
        const fps = fparams.split(",")
        let pCount = 0
        let defaults = ""
        for (fp in fps) {
            const fpId = parseInt(fp)
            if (fpId > 0 && nGetKind(fpId) == "PARAM") {
                let defId = nGetI1(fpId)
                if (defId <= 0 && nGetI2(fpId) > 0) {
                    const pType = nGetS2(fpId)
                    if (pType == "string") {
                        defId = newNode("STRING_LIT")
                        nSetS1(defId, "")
                    } else if (pType == "double") {
                        defId = newNode("DOUBLE_LIT")
                        nSetS1(defId, "0.0")
                    } else {
                        defId = newNode("INT_LIT")
                        nSetS1(defId, "0")
                    }
                    nSetI1(fpId, defId)
                }
                if (defId > 0) {
                    defaults = listAppendStr(defaults, `${pCount}:${defId}`)
                }
                funcParamTypes.set(`${fname}:${pCount}`, nGetS2(fpId))
                if (fSig != "") {
                    funcParamTypes.set(`${fname}_${fSig}:${pCount}`, nGetS2(fpId))
                }
                pCount = pCount + 1
            }
        }
        funcParamCount.set(fname, `${pCount}`)
        if (defaults != "") { funcDefaults.set(fname, defaults) }
    } else {
        funcParamCount.set(fname, "0")
    }
}

// Flush @comptimeEmit SS source: tokenize → parse → multi-pass codegen.
// Shared by COMPTIME_BLOCK (gen_stmts) and COMPTIME_EXPR (gen_types).
function flushComptimeSS() {
    const fss = interpGetComptimeSS()
    if (fss == "") { return }
    const fssTokens = tokenize(fss)
    const fssRoot = parse(fssTokens)
    const fssList = nGetList(fssRoot)
    if (fssList != "") {
        const fssParts = fssList.split(",")
        // Pass 0: VAR_DECL → global vars
        const fssSavedFunc = currentFunc
        currentFunc = ""
        emitGlobalVars(fssList)
        currentFunc = fssSavedFunc
        // Pass 1: CLASS_DECL/ENUM_DECL/INTERFACE_DECL → register before codegen
        for (fp in fssParts) {
            const fsSid = parseInt(fp)
            if (fsSid <= 0) { continue }
            const fsKind = nGetKind(fsSid)
            if (fsKind == "CLASS_DECL") {
                registerClass(fsSid)
                collectClassAnnotations(fsSid)
                resolveInheritanceForClass(nGetS1(fsSid))
                assignDtorTagForClass(nGetS1(fsSid))
            }
            if (fsKind == "ENUM_DECL") { registerEnum(fsSid) }
            if (fsKind == "INTERFACE_DECL") { registerInterface(fsSid) }
        }
        // Pass 2: FUNC_DECL → register
        for (fp in fssParts) {
            const fsSid = parseInt(fp)
            if (fsSid > 0 && nGetKind(fsSid) == "FUNC_DECL") { registerFuncDeclNode(fsSid) }
        }
        // Pass 3: codegen (skip VAR_DECL, already emitted)
        for (fp in fssParts) {
            const fsSid = parseInt(fp)
            if (fsSid > 0 && nGetKind(fsSid) != "VAR_DECL") { genStmt(fsSid) }
        }
        // Pass 4: generate interface dispatchers (idempotent — skips already emitted)
        generateInterfaceDispatchers()
    }
    interpClearComptimeSS()
}

// Flush comptime IR buffer emitted by emit() calls.
function flushComptimeIR() {
    const fir = interpGetComptimeIR()
    if (fir != "") { emitIR(fir); interpClearComptimeIR() }
}

function registerAllDecls(rootId: int) {
    const stmtList0 = nGetList(rootId)
    if (stmtList0 == "") { return }
    const parts0 = stmtList0.split(",")
    registrationPhase = 1
    for (p0 in parts0) {
        const sid = parseInt(p0)
        if (sid <= 0) { continue }
        const sk = nGetKind(sid)
        if (sk == "FUNC_DECL") {
            registerFuncDeclNode(sid)
        }
        if (sk == "INTERFACE_DECL") {
            registerInterface(sid)
        }
        if (sk == "EXPR_STMT") {
            // Process compile-time annotationMapping() directives
            const amExpr = nGetI1(sid)
            if (amExpr > 0 && nGetKind(amExpr) == "CALL" && nGetS1(amExpr) == "annotationMapping") {
                const amArgs = nGetList(amExpr)
                if (amArgs != "") {
                    const amParts = amArgs.split(",")
                    if (amParts.length() >= 2) {
                        const amNameId = parseInt(amParts[0])
                        const amHandlerId = parseInt(amParts[1])
                        if (amNameId > 0 && nGetKind(amNameId) == "STRING_LIT" && amHandlerId > 0 && nGetKind(amHandlerId) == "IDENT") {
                            registerAnnotation(nGetS1(amNameId), nGetS1(amHandlerId))
                        }
                    }
                }
            }
        }
        if (sk == "CLASS_DECL") {
            registerClass(sid)
            // Track generic classes for monomorphization
            if (classTypeParams(sid) != "") {
                genericClassNodes.set(nGetS1(sid), `${sid}`)
            }
            collectClassAnnotations(sid)
        }
        if (sk == "ENUM_DECL") {
            registerEnum(sid)
        }
    }
    // Resolve inheritance after all classes are registered
    resolveInheritance()
    // Build vtable for classes in inheritance hierarchies
    buildClassVtables()
    // Emit struct types for generic parents deferred during registration
    emitDeferredStructDefs()
    registrationPhase = 0
    // Assign dtor tags to classes with ptr fields
    assignClassDtorTags()
    // Detect cyclic ownership and mark non-owning container fields
    detectCyclicOwnership()
    // Generate interface dispatch functions (switch on class_id)
    generateInterfaceDispatchers()
}

function isTopLevelDecl(id: int): int {
    const k = nGetKind(id)
    if (k == "VAR_DECL") { return 1 }
    if (k == "FUNC_DECL") { return 1 }
    if (k == "CLASS_DECL") { return 1 }
    if (k == "ENUM_DECL") { return 1 }
    if (k == "INTERFACE_DECL") { return 1 }
    if (k == "ANNOTATION") { return 1 }
    return 0
}

function emitGlobalsAndCode(rootId: int) {
    const sl = nGetList(rootId)
    if (sl == "") { return }
    const parts = sl.split(",")
    emitGlobalVars(sl)
    emitIR("")

    let hasMain = 0
    let bareStmts = ""
    for (x in parts) {
        const s = parseInt(x)
        if (s <= 0) { continue }
        if (nGetKind(s) == "FUNC_DECL" && nGetS1(s) == "main") { hasMain = 1 }
        if (isTopLevelDecl(s) == 0) { bareStmts = listAppend(bareStmts, s) }
    }

    for (x2 in parts) {
        const s2 = parseInt(x2)
        if (s2 <= 0) { continue }
        if (nGetKind(s2) == "VAR_DECL") { continue }
        if (nGetKind(s2) == "FUNC_DECL" && nGetS3(s2) != "") { continue }
        if (nGetKind(s2) == "CLASS_DECL" && genericClassNodes.has(nGetS1(s2)) == 1) { continue }
        if (hasMain == 0 && isTopLevelDecl(s2) == 0) { continue }
        genStmt(s2)
    }

    if (hasMain == 0 && bareStmts != "") {
        currentFunc = "main"
        emitMainProlog()
        const bareParts = bareStmts.split(",")
        for (bs in bareParts) {
            const bsId = parseInt(bs)
            if (bsId > 0) { genStmt(bsId) }
        }
        emitReleaseFnLocals()
        emitReleaseLocals()
        emitIR("  ret i32 0")
        emitIR("}")
        emitIR("")
        flushArrowDefs()
        currentFunc = ""
    }
}

function resetCodegen() {
    // Reset guard flags so init functions re-create fresh Maps
    varTypesReady = 0
    varAliasReady = 0
    classStateReady = 0
    initCodegen()
    initClassState()
    initFuncRegistry()
    initVarAliases()
    // Comptime buffers
    interpClearComptimeIR()
    interpClearComptimeSS()
    comptimeConsts = new Map()
    // IR output
    irBuf = ""
    strConsts = ""
    strCount = 0
    strOutFile = ""
    // SSA counters
    regCount = 0
    regTable = []
    ctVars = new Map()
    ctFuncNodes = new Map()
    ctScopeStack = []
    ctCallCounter = 0
    comptimeDepth = 0
    labelCount = 0
    varCounter = 0
    // Function context
    currentFunc = ""
    terminated = 0
    breakLabel = ""
    continueLabel = ""
    // RC state (gen_rc.ss)
    initRcState()
    // PIR state (gen_pir.ss)
    initPir()
    // Enum / routes
    enumValues = ""
    enumTypes = ""
    enumDeclNodes = ""
    enumReady = 0
    annClassNodeIds = []
    annClassAnnNames = []
    // Arrow functions (gen_exprs.ss)
    arrowCount = 0
    arrowDefs = ""
    // Generic function monomorphization
    genericFuncNodes = Map()
    specializedFuncs = Map()
    genericTypeSubs = Map()
    genericSpecDefs = ""
    specFuncName = ""
    // Generic class monomorphization
    genericClassNodes = Map()
    specializedClasses = Map()
    specClassName = ""
    // Generic class inheritance deferred state
    registrationPhase = 0
    deferredStructDefs = ""
    specClassNodeId = Map()
    specClassTypeArgs = Map()
    specClassGenerated = Map()
    // Global var init tracking (gen_stmts.ss)
    globalInitIds = ""
}

function ctPopScope() {
    let ns: Array<string> = []
    let i = 0
    while (i < ctScopeStack.length() - 1) {
        ns = ns.push(ctScopeStack[i])
        i = i + 1
    }
    ctScopeStack = ns
}

function generate(rootId: int): string {
    resetCodegen()
    emitRuntimeDefs()
    registerAllDecls(rootId)
    emitGlobalsAndCode(rootId)
    generateDeferredSpecializations()
    return `; ModuleID = 'simplescript'\nsource_filename = "simplescript"\n\n${strConsts}\n${irBuf}`
}

let runtimeCacheObj = "/tmp/ss_rt_cache.o"
let runtimeCacheDecls = "/tmp/ss_rt_cache.decls"
let useRuntimeCache = 0

function buildRuntimeCache() {
    const rtLL = "/tmp/ss_rt_cache.ll"
    resetCodegen()
    irOutFile = rtLL
    writeFile(rtLL, "")
    writeFile(`${rtLL}.str`, "")
    emitRuntimeDefs()
    irOutFile = ""
    const rtBody = readFile(rtLL)
    writeFile(rtLL, `; ModuleID = 'ss_runtime'\nsource_filename = "ss_runtime"\n\n${rtBody}`)
    if (system(`llc-18 -filetype=obj ${rtLL} -o ${runtimeCacheObj}`) != 0) {
        system(`rm -f ${runtimeCacheObj} ${runtimeCacheDecls} ${rtLL}`)
        return
    }
    // Generate declarations from runtime IR
    // 1. Function declares
    system(`grep '^define ' ${rtLL} | grep -v '^define internal ' | sed 's/define /declare /;s/ {$//' > ${runtimeCacheDecls}`)
    // 2. Libc declares
    system(`grep '^declare ' ${rtLL} >> ${runtimeCacheDecls}`)
    // 3. Runtime string constants as external
    system(`grep '^@\.rt\.' ${rtLL} | sed 's/ = constant \(\[[^]]*\]\).*/= external constant \1/' >> ${runtimeCacheDecls}`)
    // 4. @stdin/@stdout and type definitions
    system(`grep '^@stdin\|^@stdout' ${rtLL} >> ${runtimeCacheDecls}`)
    system(`grep '^%TypeInfo\|^%ObjHeader' ${rtLL} >> ${runtimeCacheDecls}`)
    // 5. Runtime globals as external (auto-extracted from .ll)
    system(`grep '^@ss_' ${rtLL} | sed 's/ = global / = external global /;s/ zeroinitializer.*//;s/ null.*//;s/ 0, align [0-9]*//;s/ 0$//' >> ${runtimeCacheDecls}`)
    system(`rm -f ${rtLL} ${rtLL}.str`)
}

function generateToFile(rootId: int, outFile: string) {
    resetCodegen()
    irOutFile = outFile
    writeFile(outFile, "")
    writeFile(`${outFile}.str`, "")
    if (useRuntimeCache == 1 && fileExists(runtimeCacheDecls) == 1 && fileExists(runtimeCacheObj) == 1) {
        appendFile(outFile, readFile(runtimeCacheDecls))
    } else {
        emitRuntimeDefs()
        useRuntimeCache = 0
    }
    registerAllDecls(rootId)
    emitGlobalsAndCode(rootId)
    generateDeferredSpecializations()
    irOutFile = ""
    const body = readFile(outFile)
    writeFile(outFile, `; ModuleID = 'simplescript'\nsource_filename = "simplescript"\n\n${readFile(`${outFile}.str`)}\n${body}`)
}

// Builtin function name mapping moved to gen_registry.ss (builtinMap, runtimeName)

