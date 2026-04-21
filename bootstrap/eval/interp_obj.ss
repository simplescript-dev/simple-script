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

// D117 §决策 2-4 — ClassMeta 实例 + InternPool name-based dedup +
// .fields/.annotations 填充(走 ClassMeta object → MEMBER_ACCESS interpGetField 统一 read)。
// hit-check pre-guard 避免 dedup miss 路径浪费 tvIds + 节点数(填充 array 远大于 .name).
// .methods 字段留 Execute 5 补(当前无 evalExpr 上下文用例,for-in 走 stmts_loop_forin 反射分支)。
// FieldMeta/AnnotationMeta inline 构造 + InternPool dedup,key schema 走 §决策 3
// FLD|<className>.<fName> / ANN|CLS|<className>.<annName>。inline 不抽 helper(M7b strict 0)。
function interpBuildTypeInfo(typeName: string): int {
    const poolKey = `CLS|${typeName}`
    if (internPool.has(poolKey) == 1) { return parseInt(internPool.getString(poolKey)) }
    const id = interpNewVal("object", typeName)
    tvMap.set(`${id}|name`, `${interpNewString(typeName)}`)
    tvMap.set(`${id}|fields`, `${interpCtFieldsArray(typeName)}`)
    // D117 Execute 4 — .methods 填充:MethodMeta(.name/.annotations);params/returnType
    // 占位 Execute 5。method-level AnnotationMeta.args 无 sidecar,未 set(.args 访问返 null)。
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

function interpCollectFields(className: string): string {
    if (interpClasses.has(className) != 1) { return "" }
    let fields = ""
    let cur = className
    while (cur != "") {
        const paramList = nGetList(parseInt(interpClasses.getString(cur)))
        if (paramList != "") {
            fields = fields == "" ? paramList : `${paramList},${fields}`
        }
        cur = interpClassParents.getString(cur)
    }
    return fields
}

function isKnownClass(name: string): int {
    return (classFields.has(name) == 1 || interpClasses.has(name) == 1) ? 1 : 0
}

// D117 §决策 3-4 — fp 从 fName string 升级为 FieldMeta object(InternPool dedup
// FLD|<className>.<fName>),f.name/.type 经 MEMBER_ACCESS object-kind interpGetField
// 统一 read。依赖 internPoolGetOrInsert hit-check 直接接管,不做外层 if/else 双重
// dedup(M4/M2 根因:重复 IF chain + AST 双分支)。
function interpCtFieldsArray(className: string): int {
    const fArr = interpNewArray("")
    const fromIC = interpClasses.has(className) == 1
    const fStr = fromIC ? interpCollectFields(className) : classFields.getString(className)
    if (fStr == "") { return fArr }
    for (fp in fStr.split(",")) {
        const fName = fromIC ? nGetS1(parseInt(fp)) : fp
        const ftKey = `${className}.${fName}`
        const fmId = interpNewVal("object", "FieldMeta")
        tvMap.set(`${fmId}|name`, `${interpNewString(fName)}`)
        const fType = classFieldTypes.getString(ftKey)
        tvMap.set(`${fmId}|type`, `${interpNewString(fType)}`)
        // D117 Execute 4 — FieldMeta.annotations 填充,AnnotationMeta.args 走
        // classFieldAnnotationArgs(key=<cls>.<field>.<ann>)。空 annotation 时
        // 写入空 array tv。
        const fAnnArr = interpNewArray("")
        for (fann in classFieldAnnotations.getString(ftKey).split(",")) {
            if (fann == "") { continue }
            const famId = interpNewVal("object", "AnnotationMeta")
            tvMap.set(`${famId}|name`, `${interpNewString(fann)}`)
            const faArgsArr = interpNewArray("")
            const faArgKey = `${ftKey}.${fann}`
            for (faarg in classFieldAnnotationArgs.getString(faArgKey).split(",")) {
                if (faarg != "") { interpArrayPush(faArgsArr, interpNewString(faarg)) }
            }
            tvMap.set(`${famId}|args`, `${faArgsArr}`)
            interpArrayPush(fAnnArr, internPoolGetOrInsert(`ANN|FLD|${faArgKey}`, famId))
        }
        tvMap.set(`${fmId}|annotations`, `${fAnnArr}`)
        interpArrayPush(fArr, internPoolGetOrInsert(`FLD|${ftKey}`, fmId))
    }
    return fArr
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
