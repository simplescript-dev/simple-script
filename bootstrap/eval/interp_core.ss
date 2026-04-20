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
