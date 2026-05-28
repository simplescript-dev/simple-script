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

function allocTv(): int {
    initTypedValue()
    const id = nextTvId
    nextTvId = nextTvId + 1
    tvI1.push(0)
    tvI2.push(0)
    tvI3.push(0)
    return id
}

function newTvInt(n: int): int {
    const id = allocTv()
    tvI1[id] = n
    return id
}

function newTvString(s: string): int {
    const id = allocTv()
    tvS1.set(id + "", s)
    return id
}

// comptime TypeValue:kind="type",tvS1 存 class 名
function newTvType(className: string): int {
    const id = allocTv()
    tvS1.set(id + "", className)
    return id
}

function newTvBool(b: int): int {
    const id = allocTv()
    tvI1[id] = b
    return id
}

function newTvNull(): int {
    return allocTv()
}

function newTvArray(initCsv: string): int {
    const id = allocTv()
    if (initCsv != "") {
        const parts = initCsv.split(",")
        let i = 0
        while (i < parts.length()) {
            tvArrElem.set(`${id}:${i}`, parts[i])
            i = i + 1
        }
        tvI2[id] = i
    }
    internPoolKeyOf.set(`${id}`, `array|${id}`)
    return id
}

// ── TypedValue Accessor Primitive (D092 Phase 1 最小子集) ────

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

// D093 §差距 #3 — kind 单一源:Value 层不存 kind,interpType 全量走 internPoolKeyOf
// 反查(tvKindByPool)。tvKind 存储 + tvKindOf 已删除,双轨"读+存"消除。9 个 value 构造入口
// 注册 internPoolKeyOf(6 标量经 internPoolGetOrInsert + array/map/fn 显式 set);object kind
// (Meta + comptime obj)经 metaPool/fallback 返 "object",不入 value pool(namespace 物理分离)。
function interpType(id: int): string {
    return tvKindByPool(id)
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

function newTvDouble(d: double): int {
    const id = allocTv()
    tvD1.set(id + "", `${d}`)
    return id
}

// D098 §决策 2 §Phase C — double 入 InternPool dedup (sibling 58 起首 Execute)
// key = `double|<IEEE 754 bit-pattern hex>` (Zig InternPool.Key.float_* 对齐)
function interpNewDouble(d: double): int {
    return internPoolGetOrInsert(`double|${doubleBits(d)}`, newTvDouble(d))
}

// ── MaybeVal helper(D098 §决策 1 §Phase A 字面规约 — D169 Phase 1.5a 显式化) ──
// D099 commit 53066f0 已隐式落 mv 编码契约(eval_expr.ss:1-5 + valOf/valType 访问器),
// 本节是 D098 §决策 1 4 helper 函数的显式定义;callsite 渐进迁移由 D169 §子拆解
// Phase 1.5b/c/d 推进。class 视图(D098 行 102 + D169 §A §保留)不落 bootstrap。
//
// 编码契约(eval_expr.ss:1-5 头部权威):
//   mv >= 0   → known=true,  val = mv             (Value 句柄,通常已是 ctVal tagged int)
//   mv <= -2  → known=false, regId = -mv - 1      (regTable 1-based)
//   mv == -1  → error 哨兵,禁止 reg()

function mvRuntime(regId: int): int { return 0 - regId - 1 }   // regId 1-based → mv <= -2
function mvError(): int { return 0 - 1 }                        // -1 哨兵

function mvKnown(mv: int): int { return mv >= 0 ? 1 : 0 }

function mvVal(mv: int): int {
    if (mv >= 0) { return mv }              // known=true:Value 句柄(payload 等价 mv 本身,bit 30 含 ct tag)
    if (mv == 0 - 1) { return 0 - 1 }       // error:返回 -1 哨兵
    return 0 - mv - 1                        // runtime:decode regId
}
