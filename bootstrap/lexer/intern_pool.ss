// D098 §决策 2 §Phase B — InternPool 引入
// 相同 (tag, payload) 同 tvId,Value.eql 退化为 id == id O(1) 比较
// 范围:5 标量入口(int/string/bool/null/type),Array/Map/Double 留 Phase C
// key 格式:`<tag>|<payload>` —— int|42 / string|hello / bool|0 / null| / type|MyClass

let internPool = new Map()        // key → tvId
let internPoolKeyOf = new Map()   // str(tvId) → key(反查支持 valType)

function internPoolGetOrInsert(key: string, ifMissAlloc: int): int {
    if (internPool.has(key) == 1) {
        return parseInt(internPool.getString(key))
    }
    internPool.set(key, `${ifMissAlloc}`)
    internPoolKeyOf.set(`${ifMissAlloc}`, key)
    return ifMissAlloc
}

// D093 §差距 #3 候选 D1 prereq — InternPool key tag 双语义空间分离 (sibling 64 Execute)
// Meta 对象(反射元信息 CLS/FLD/MTH/PRM/ANN)独立池, 与 value kind(internPool 9 类)namespace 物理分离
// Zig InternPool.Key enum tag union namespace 物理分离同构, valType 反查 internPoolKeyOf 时
// Meta tvId 不命中 → fallback interpType 返 "object" 修复反射 Meta 对象路径
let metaPool = new Map()          // key → tvId (Meta 对象专用)
let metaPoolKeyOf = new Map()     // str(tvId) → key (Meta 对象反查通道, 与 internPoolKeyOf 隔离)

function metaPoolGetOrInsert(key: string, ifMissAlloc: int): int {
    if (metaPool.has(key) == 1) {
        return parseInt(metaPool.getString(key))
    }
    metaPool.set(key, `${ifMissAlloc}`)
    metaPoolKeyOf.set(`${ifMissAlloc}`, key)
    return ifMissAlloc
}

// D093 §差距 #3 候选 D1 真路径 sibling 65 — 双 namespace 查表 (Zig InternPool.indexToKey 同构)
// internPoolKeyOf 命中 → split "|" 取 tag 返 9 kind (int/string/bool/null/type/double/array/map)
// metaPoolKeyOf 命中 → 返 "object" (Meta 对象 CLS/FLD/MTH/PRM/ANN 统一 tvKind="object")
// 兜底 → tvKindOf storage 直读 (D098 §Phase C 远期 sub-phase 3 完结后清)
function tvKindByPool(tvId: int): string {
    const k = `${tvId}`
    if (internPoolKeyOf.has(k) == 1) {
        const key = internPoolKeyOf.getString(k)
        const barAt = key.indexOf("|")
        return key.substring(0, barAt)
    }
    if (metaPoolKeyOf.has(k) == 1) {
        return "object"
    }
    return tvKindOf(tvId)
}
