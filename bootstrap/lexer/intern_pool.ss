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
