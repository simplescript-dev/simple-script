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
        if (parts[i] != key) { newCsv = newCsv == "" ? parts[i] : newCsv + "," + parts[i] }
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

// ClassMeta 实例 + InternPool name-based dedup,FieldMeta/MethodMeta/AnnotationMeta inline 构造。
// Key schema:CLS|<cls> / FLD|<cls>.<fld> / MTH|<cls>.<mth> / ANN|{CLS|FLD|MTH}|<...>。
// hit-check pre-guard 避免 miss 路径浪费 tvIds。fields 父类链 prepend parent first;
// fromIC=0 走 classFields CSV(interpClasses 未注册场景,fp 直接是 fName string)。
function interpBuildTypeInfo(typeName: string): int {
    const poolKey = `CLS|${typeName}`
    if (internPool.has(poolKey) == 1) { return parseInt(internPool.getString(poolKey)) }
    const id = interpNewVal("object", typeName)
    tvMap.set(`${id}|name`, `${interpNewString(typeName)}`)
    const fArr = interpNewArray("")
    const fromIC = interpClasses.has(typeName) == 1
    let fStr = fromIC ? "" : classFields.getString(typeName)
    let cur = fromIC ? typeName : ""
    while (cur != "") {
        const paramList = nGetList(parseInt(interpClasses.getString(cur)))
        if (paramList != "") { fStr = fStr == "" ? paramList : `${paramList},${fStr}` }
        cur = interpClassParents.getString(cur)
    }
    for (fp in fStr.split(",")) {
        if (fp == "") { continue }
        const fName = fromIC ? nGetS1(parseInt(fp)) : fp
        const ftKey = `${typeName}.${fName}`
        const fmId = interpNewVal("object", "FieldMeta")
        tvMap.set(`${fmId}|name`, `${interpNewString(fName)}`)
        tvMap.set(`${fmId}|type`, `${interpNewString(classFieldTypes.getString(ftKey))}`)
        const fAnnArr = interpNewArray("")
        // AST 直读 annotations:fromIC fp 即 PARAM id;非 fromIC 在 classNodeIds[typeName] 按 fName 查 PARAM
        let fpAnn = ""
        if (fromIC) {
            fpAnn = nGetList(parseInt(fp))
        } else if (classNodeIds.has(typeName) == 1) {
            for (np in classFieldList(parseInt(classNodeIds.getString(typeName))).split(",")) {
                const npId = parseInt(np)
                if (npId > 0 && paramName(npId) == fName) { fpAnn = nGetList(npId); break }
            }
        }
        if (fpAnn != "") {
            for (fap in nGetList(parseInt(fpAnn)).split(",")) {
                const faId = parseInt(fap)
                if (faId > 0) {
                    const annName = nGetS1(faId)
                    const famId = interpNewVal("object", "AnnotationMeta")
                    tvMap.set(`${famId}|name`, `${interpNewString(annName)}`)
                    const argsArr = interpNewArray("")
                    for (arp in nGetList(faId).split(",")) {
                        const argId = parseInt(arp)
                        if (argId > 0 && nGetKind(argId) == "STRING_LIT") {
                            interpArrayPush(argsArr, interpNewString(nGetS1(argId)))
                        }
                    }
                    tvMap.set(`${famId}|args`, `${argsArr}`)
                    interpArrayPush(fAnnArr, internPoolGetOrInsert(`ANN|FLD|${ftKey}.${annName}`, famId))
                }
            }
        }
        tvMap.set(`${fmId}|annotations`, `${fAnnArr}`)
        interpArrayPush(fArr, internPoolGetOrInsert(`FLD|${ftKey}`, fmId))
    }
    tvMap.set(`${id}|fields`, `${fArr}`)
    // methods 段:MethodMeta(.name/.annotations)。params/returnType 未填,
    // method-level AnnotationMeta.args 无 sidecar(不 set → .args 访问返 null)。
    const mArr = interpNewArray("")
    for (mp in classMethods.getString(typeName).split(",")) {
        if (mp == "") { continue }
        const mmId = interpNewVal("object", "MethodMeta")
        tvMap.set(`${mmId}|name`, `${interpNewString(mp)}`)
        const mAnnArr = interpNewArray("")
        const mAnnKey = `${typeName}.${mp}`
        for (mann in classMethodAnnotations.getString(mAnnKey).split(",")) {
            if (mann == "") { continue }
            const mamId = interpNewVal("object", "AnnotationMeta")
            tvMap.set(`${mamId}|name`, `${interpNewString(mann)}`)
            interpArrayPush(mAnnArr, internPoolGetOrInsert(`ANN|MTH|${mAnnKey}.${mann}`, mamId))
        }
        tvMap.set(`${mmId}|annotations`, `${mAnnArr}`)
        interpArrayPush(mArr, internPoolGetOrInsert(`MTH|${typeName}.${mp}`, mmId))
    }
    tvMap.set(`${id}|methods`, `${mArr}`)
    const aArr = interpNewArray("")
    for (ap in nGetList(nGetI4(parseInt(classNodeIds.getString(typeName)))).split(",")) {
        const aId = parseInt(ap)
        if (aId > 0) {
            const annName = nGetS1(aId)
            const amId = interpNewVal("object", "AnnotationMeta")
            tvMap.set(`${amId}|name`, `${interpNewString(annName)}`)
            const argsArr = interpNewArray("")
            for (arp in nGetList(aId).split(",")) {
                const argId = parseInt(arp)
                if (argId > 0 && nGetKind(argId) == "STRING_LIT") {
                    interpArrayPush(argsArr, interpNewString(nGetS1(argId)))
                }
            }
            tvMap.set(`${amId}|args`, `${argsArr}`)
            interpArrayPush(aArr, internPoolGetOrInsert(`ANN|CLS|${typeName}.${annName}`, amId))
        }
    }
    tvMap.set(`${id}|annotations`, `${aArr}`)
    return internPoolGetOrInsert(poolKey, id)
}

function isKnownClass(name: string): int {
    return (classFields.has(name) == 1 || interpClasses.has(name) == 1) ? 1 : 0
}

function interpFindMethod(className: string, methodName: string): int {
    let cur = className
    while (cur != "") {
        if (interpClasses.has(cur) == 1) {
            const mList = nGetList(nGetI2(parseInt(interpClasses.getString(cur))))
            if (mList != "") {
                for (mp in mList.split(",")) {
                    const mId = parseInt(mp)
                    if (mId > 0 && nGetKind(mId) == "FUNC_DECL" && nGetS1(mId) == methodName) {
                        interpLastFoundMethodClass = cur
                        return mId
                    }
                }
            }
        }
        cur = interpClassParents.getString(cur)
    }
    return 0
}
