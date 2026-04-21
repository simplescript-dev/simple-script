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
    let newCsv = ""
    for (p in tvList.getString(mapId + "").split(",")) {
        if (p != key) { newCsv = newCsv == "" ? p : newCsv + "," + p }
    }
    tvList.set(mapId + "", newCsv)
    tvMap.delete(fullKey)
    tvI3[mapId] = tvI3[mapId] - 1
}

function interpMapGetKeys(mapId: int): int {
    const arrId = newTvArray("")
    const cur = tvList.getString(mapId + "")
    if (cur == "") { return arrId }
    for (p in cur.split(",")) { interpArrayPush(arrId, newTvString(p)) }
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

// D121 R1-A:args 形态 Array<string> → Map<string, string>,value 通用化
// (STRING/INT/DOUBLE/TRUE/FALSE/MEMBER_ACCESS enum)。位置参数 Java 惯例:
// 单参 → key "value",多参 → key "0"/"1"/...;命名参数(NAMED_ARG COLON 或
// R2-B ASSIGN)→ key = S1, value = inline kind dispatch on nGetI1(argId)。
// 非 comptime-evaluable value kind silently skip(保兼容 d096 非 STRING 原行为)。
// annListId 非 ANNOTATION_LIST kind 或 <=0 返空数组(abstract FUNC_DECL.I4=1)。
// ANN InternPool key = `ANN|${annPoolPrefix}.${annName}`(D118 Execute 2 抽出)。
// D121 R1-A value kind 通用化:STRING/INT/DOUBLE/BOOL/enum MEMBER_ACCESS 字面化;
// sentinel "\0" 判非合法值(区别合法 "" 空串,D121 test 无空串用例)。enum 双 map 回退
// (comptimeDepth=0 注册 enumValues / >0 注册 interpEnumValues,见 member_access.ss:10-16)。
function buildAnnotationMetaArray(annListId: int, annPoolPrefix: string): int {
    const arr = interpNewArray("")
    if (annListId <= 0 || nGetKind(annListId) != "ANNOTATION_LIST") { return arr }
    for (ap in nGetList(annListId).split(",")) {
        const aId = parseInt(ap)
        if (aId <= 0) { continue }
        const amId = interpNewVal("object", "AnnotationMeta")
        tvMap.set(`${amId}|name`, `${interpNewString(nGetS1(aId))}`)
        const argsMap = interpNewMap()
        let posCount = 0
        for (arp in nGetList(aId).split(",")) {
            const acId = parseInt(arp)
            if (acId > 0 && nGetKind(acId) != "NAMED_ARG") { posCount = posCount + 1 }
        }
        let posIdx = 0
        for (arp2 in nGetList(aId).split(",")) {
            const argId = parseInt(arp2)
            if (argId <= 0) { continue }
            let key = ""
            let valId = 0
            if (nGetKind(argId) == "NAMED_ARG") {
                key = nGetS1(argId); valId = nGetI1(argId)
            } else {
                key = posCount == 1 ? "value" : `${posIdx}`; valId = argId; posIdx = posIdx + 1
            }
            const vKind = nGetKind(valId)
            let valStr = "\0"
            if (vKind == "STRING_LIT" || vKind == "INT_LIT" || vKind == "DOUBLE_LIT") { valStr = nGetS1(valId) }
            else if (vKind == "TRUE_LIT" || vKind == "FALSE_LIT") { valStr = vKind == "TRUE_LIT" ? "true" : "false" }
            else if (vKind == "MEMBER_ACCESS" && nGetKind(nGetI1(valId)) == "IDENT") {
                const eKey = `${nGetS1(nGetI1(valId))}.${nGetS1(valId)}`
                if (interpEnumValues.has(eKey) == 1) { valStr = interpEnumValues.getString(eKey) }
                else if (enumReady == 1 && enumValues.has(eKey) == 1) { valStr = enumValues.getString(eKey) }
            }
            if (valStr != "\0") { interpMapSet(argsMap, key, interpNewString(valStr)) }
        }
        tvMap.set(`${amId}|args`, `${argsMap}`)
        interpArrayPush(arr, internPoolGetOrInsert(`ANN|${annPoolPrefix}.${nGetS1(aId)}`, amId))
    }
    return arr
}

// ClassMeta 实例 + InternPool name-based dedup,FieldMeta/MethodMeta/AnnotationMeta inline 构造。
// Key schema:CLS|<cls> / FLD|<cls>.<fld> / MTH|<cls>.<mth>[.get|.set] / ANN|{CLS|FLD|MTH}|<...>。
// accessor get/set 共用 mName,MTH key 加 .get/.set 后缀分离(D118 §新张力 2)。
// hit-check pre-guard 避免 miss 路径浪费 tvIds。fields 父类链 prepend parent first;
// fromIC=0 走 classFields CSV(interpClasses 未注册场景,fp 直接是 fName string)。
function interpBuildTypeInfo(typeName: string): int {
    const poolKey = `CLS|${typeName}`
    if (internPool.has(poolKey) == 1) { return parseInt(internPool.getString(poolKey)) }
    const id = interpNewVal("object", typeName)
    tvMap.set(`${id}|name`, `${interpNewString(typeName)}`)
    const fArr = interpNewArray("")
    const fromIC = interpClasses.has(typeName) == 1
    const hasNode = classNodeIds.has(typeName) == 1
    const clsNodeId = hasNode ? parseInt(classNodeIds.getString(typeName)) : 0
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
        // AST 直读 annotations:fromIC fp 即 PARAM id;非 fromIC 在 classNodeIds[typeName] 按 fName 查 PARAM
        let fpAnn = ""
        if (fromIC) {
            fpAnn = nGetList(parseInt(fp))
        } else if (hasNode) {
            for (np in classFieldList(clsNodeId).split(",")) {
                const npId = parseInt(np)
                if (npId > 0 && paramName(npId) == fName) { fpAnn = nGetList(npId); break }
            }
        }
        const fAnnId = fpAnn == "" ? 0 : parseInt(fpAnn)
        const fAnnArr = buildAnnotationMetaArray(fAnnId, `FLD|${ftKey}`)
        tvMap.set(`${fmId}|annotations`, `${fAnnArr}`)
        interpArrayPush(fArr, internPoolGetOrInsert(`FLD|${ftKey}`, fmId))
    }
    tvMap.set(`${id}|fields`, `${fArr}`)
    // methods 段:AST 直读 methodsBlock → FUNC_DECL.I4 ANNOTATION_LIST + handler-generated 尾部补齐。
    // accessor get/set 共用 mName → MTH key 加 .get/.set 后缀分离(D118 §新张力 2);
    // abstract method I4=1 被 buildAnnotationMetaArray kind 校验自动返空。
    // classMethods CSV = [own FUNC_DECL 按声明序] + [@methodOf handler-appended 尾部],
    // AST 只含 own 部分(class_annotation.ss:107 handler 只往 CSV push);本段先 AST 遍历 own,
    // 再 skip 前 ownCount 取 CSV 尾部 handler-generated,空 annotations。
    // built-in 类(Map/Set 等)classNodeIds 缺失 → ownCount=0,CSV 全部按 handler-generated 建。
    const mArr = interpNewArray("")
    if (hasNode) {
        const mbId = classMethodsBlock(clsNodeId)
        if (mbId > 0) {
            for (mp in nGetList(mbId).split(",")) {
                const mId = parseInt(mp)
                if (mId <= 0 || nGetKind(mId) != "FUNC_DECL") { continue }
                const mName = funcName(mId)
                const mKind = nGetI2(mId)
                const keySuffix = mKind == 2 ? ".get" : (mKind == 3 ? ".set" : "")
                const mKey = `${typeName}.${mName}${keySuffix}`
                const mmId = interpNewVal("object", "MethodMeta")
                tvMap.set(`${mmId}|name`, `${interpNewString(mName)}`)
                const mAnnArr = buildAnnotationMetaArray(nGetI4(mId), `MTH|${mKey}`)
                tvMap.set(`${mmId}|annotations`, `${mAnnArr}`)
                interpArrayPush(mArr, internPoolGetOrInsert(`MTH|${mKey}`, mmId))
            }
        }
    }
    const ownCount = interpArrayLen(mArr)
    const mCsv = classMethods.getString(typeName)
    if (mCsv != "") {
        let mIdx = 0
        for (mp in mCsv.split(",")) {
            if (mIdx >= ownCount && mp != "") {
                const mmId = interpNewVal("object", "MethodMeta")
                tvMap.set(`${mmId}|name`, `${interpNewString(mp)}`)
                const emptyAnn = interpNewArray("")
                tvMap.set(`${mmId}|annotations`, `${emptyAnn}`)
                interpArrayPush(mArr, internPoolGetOrInsert(`MTH|${typeName}.${mp}`, mmId))
            }
            mIdx = mIdx + 1
        }
    }
    tvMap.set(`${id}|methods`, `${mArr}`)
    let aArr = interpNewArray("")
    if (hasNode) {
        aArr = buildAnnotationMetaArray(nGetI4(clsNodeId), `CLS|${typeName}`)
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
