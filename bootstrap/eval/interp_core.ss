// SimpleScript Bootstrap SEMA Interpreter Core
// TypedValue 容器 + tagged value 基础原语(D089/D092 Phase 0-2 sub-a)。

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
    if (t == "bool") { return tvIntOf(interpValId) == 1 ? "1" : "0" }
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

// comptime TypeValue:kind="type",tvS1 存 class 名
function newTvType(className: string): int {
    const id = allocTv("type")
    tvS1.set(id + "", className)
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

// interp* value delegate — D092 Phase 2 sub-b / D111 §决策 4 InternPool dedup
// 5 标量入口(int/string/bool/null/type)key tag 与 interpType 同名,Array/Map/Double 留 Phase C

function interpNewInt(n: int): int {
    return internPoolGetOrInsert(`int|${n}`, newTvInt(n))
}

function interpNewString(s: string): int {
    return internPoolGetOrInsert(`string|${s}`, newTvString(s))
}

function interpNewBool(b: int): int {
    return internPoolGetOrInsert(`bool|${b}`, newTvBool(b))
}

function interpNewNull(): int {
    return internPoolGetOrInsert(`null|`, newTvNull())
}

// comptime TypeValue delegate(kind="type" 时读 tvS1 得 class 名)
function interpNewType(className: string): int {
    return internPoolGetOrInsert(`type|${className}`, newTvType(className))
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

function isKnownClass(name: string): int {
    if (classFields.has(name) == 1) { return 1 }
    if (interpClasses.has(name) == 1) { return 1 }
    return 0
}

function interpCtFieldsArray(className: string): int {
    const fArr = interpNewArray("")
    let fStr = ""
    if (interpClasses.has(className) == 1) {
        fStr = interpCollectFields(className)
    } else if (classFields.has(className) == 1) {
        fStr = classFields.getString(className)
    }
    if (fStr != "") {
        const fParts = fStr.split(",")
        for (fp in fParts) { interpArrayPush(fArr, interpNewString(fp)) }
    }
    return fArr
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
