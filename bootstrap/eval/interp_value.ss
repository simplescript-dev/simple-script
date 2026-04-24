// SimpleScript Bootstrap SEMA Interpreter — Value 构造 / TypedValue 容器
// D089 Tagged Value + D092 Phase 0-2 sub-b 标量 TypedValue 原语。
// 依赖方向:interp_op / interp_obj → interp_value(读 tv*, 写 newTv*),
// interp_value 仅依赖外部 internPoolGetOrInsert / addStringConst。

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
        tvI2[id] = i
    }
    return id
}

// ── TypedValue Accessor Primitive (D092 Phase 1 最小子集) ────

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
// interp* 前缀让现有 callsite 自动 resolve,底层改走 Phase 1 的 TypedValue accessor。

function interpType(id: int): string {
    return tvKindOf(id)
}

function interpAsInt(id: int): int {
    return tvIntOf(id)
}

function interpAsStr(id: int): string {
    return tvStringOf(id)
}

// interp* value delegate — D092 §Phase 2 sub-b / D098 §决策 2 Phase B InternPool dedup
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

function interpNewDouble(d: double): int {
    const id = allocTv("double")
    tvD1.set(id + "", `${d}`)
    return id
}
