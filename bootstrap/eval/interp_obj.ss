// SimpleScript Bootstrap SEMA Interpreter — 对象 / 容器 / 类反射
// D092 Phase 2 sub-c field / collection delegate + sub-d class 反射 stub。
// 依赖:interp_value(读 tv*, 写 newTv*, allocTv, tvMap/tvList/tvArrElem state)、
// interp_core(interpClasses/interpClassParents registry, interpLastFoundMethodClass)。

// ── Field / Collection (D092 Phase 2 sub-c) ─────────────────
// object 和 map 共享 tvList[id] = CSV of keys、tvMap[id|key] = child tvId、
// tvI3[id] = entry count 的存储契约。array 用 tvList[id] = CSV of tvIds、
// tvI2[id] = length,由 sub-b 锁定。

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

// ── Class / TypeInfo 反射 (D092 Phase 2 sub-d) ──────────────

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

// D117 §决策 2 — ClassMeta 实例 + InternPool name-based dedup。
// tvS1 存 typeName 兼作 .name 语义载体;tvMap 直 set 绕 interpSetField 冗余层。
// .fields/.methods/.annotations 填充留 Execute 3(member_access.ss on Meta)。
function interpBuildTypeInfo(typeName: string): int {
    const id = interpNewVal("object", typeName)
    tvMap.set(`${id}|name`, `${interpNewString(typeName)}`)
    return internPoolGetOrInsert(`CLS|${typeName}`, id)
}

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
