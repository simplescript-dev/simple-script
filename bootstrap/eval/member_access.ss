// D108 §步骤 1: MEMBER_ACCESS 迁出 eval_expr.ss 独立子目录文件
// 对称三段式:FieldMeta f.name/.type/.annotations → enum X.Y → ct obj field/length/name/fields/annotations → runtime

function evalMemberAccess(astId: int): int {
    const member = nGetS1(astId)
    const objNode = nGetI1(astId)
    // D095 FieldMeta: f.name / f.type when f is a for-in-unroll bound comptime const
    if (nGetKind(objNode) == "IDENT" && comptimeConsts.has(nGetS1(objNode)) == 1) {
        const fmName = nGetS1(objNode)
        if (member == "name") {
            const nmStr = comptimeConsts.getString(fmName)
            if (comptimeDepth > 0) { return ctVal(interpNewString(nmStr)) }
            return constVal(addStringConst(nmStr))
        }
        if (member == "type") {
            const fmClsKey = `${fmName}.__class`
            if (comptimeConsts.has(fmClsKey) == 1) {
                const fmCls = comptimeConsts.getString(fmClsKey)
                const fmFld = comptimeConsts.getString(fmName)
                if (classFieldTypes.has(`${fmCls}.${fmFld}`) == 1) {
                    const tStr = classFieldTypes.getString(`${fmCls}.${fmFld}`)
                    if (comptimeDepth > 0) { return ctVal(interpNewString(tStr)) }
                    return constVal(addStringConst(tStr))
                }
            }
        }
        // D095 Stage C: f.annotations → comptime string array of annotation
        // names. Empty array when no annotations attached. Only valid in
        // comptimeDepth>0 since handlers consume it via for-in unroll.
        if (member == "annotations" && comptimeDepth > 0) {
            const fmClsKey = `${fmName}.__class`
            if (comptimeConsts.has(fmClsKey) == 1) {
                const fmCls = comptimeConsts.getString(fmClsKey)
                const fmFld = comptimeConsts.getString(fmName)
                const fmAnnArr = interpNewArray("")
                const fmAnnKey = `${fmCls}.${fmFld}`
                if (classFieldAnnotations.has(fmAnnKey) == 1) {
                    const fmAnnCsv = classFieldAnnotations.getString(fmAnnKey)
                    if (fmAnnCsv != "") {
                        const fmAnnParts = fmAnnCsv.split(",")
                        for (fap in fmAnnParts) {
                            interpArrayPush(fmAnnArr, interpNewString(fap))
                        }
                    }
                }
                return ctVal(fmAnnArr)
            }
        }
    }
    if (nGetKind(objNode) == "IDENT") {
        const eName = nGetS1(objNode)
        const enumKey = `${eName}.${member}`
        if (interpEnumValues.has(enumKey) == 1) {
            if (interpEnumTypes.has(eName) == 1) {
                return ctVal(interpNewString(interpEnumValues.getString(enumKey)))
            }
            return ctVal(interpNewInt(parseInt(interpEnumValues.getString(enumKey))))
        }
        if (enumReady == 1 && enumValues.has(enumKey) == 1) {
            if (enumTypes.has(eName) == 1) {
                return ctVal(interpNewString(enumValues.getString(enumKey)))
            }
            return ctVal(interpNewInt(parseInt(enumValues.getString(enumKey))))
        }
        if (comptimeDepth == 0 && getVarType(eName) == "" && classFields.has(eName) == 1) {
            return 0 - constVal(genMemberAccess(astId)) - 1
        }
    }
    const obj = genVal(objNode)
    if (isCt(obj) == 1) {
        const objPayload = payload(obj)
        if (interpType(objPayload) == "object") {
            return ctVal(interpGetField(objPayload, member))
        }
        if (member == "length" && interpType(objPayload) == "string") {
            return ctVal(interpNewInt(interpAsStr(objPayload).length()))
        }
        if (member == "length" && interpType(objPayload) == "array") {
            const items = interpAsStr(objPayload)
            if (items == "") { return ctVal(interpNewInt(0)) }
            return ctVal(interpNewInt(items.split(",").length()))
        }
        // string / TypeValue 都当作 class 句柄,支持 .name / .fields 属性式访问
        const mpKind = interpType(objPayload)
        if (member == "name" && (mpKind == "string" || mpKind == "type")) {
            if (mpKind == "type") { return ctVal(interpNewString(interpAsStr(objPayload))) }
            return obj
        }
        if (member == "fields" && (mpKind == "string" || mpKind == "type")) {
            const clsName = interpAsStr(objPayload)
            if (isKnownClass(clsName) == 1) {
                return ctVal(interpCtFieldsArray(clsName))
            }
        }
        // D097: cls.annotations → comptime Array<AnnotationMeta>, AST-sourced.
        if (member == "annotations" && (mpKind == "string" || mpKind == "type")) {
            const arr = interpNewArray("")
            const clsAnnName = interpAsStr(objPayload)
            if (classNodeIds.has(clsAnnName) == 1) {
                const annListId = nGetI4(parseInt(classNodeIds.getString(clsAnnName)))
                if (annListId > 0) {
                    for (ap in nGetList(annListId).split(",")) {
                        const aId = parseInt(ap)
                        const metaTv = interpNewVal("object", "AnnotationMeta")
                        interpSetField(metaTv, "name", interpNewString(nGetS1(aId)))
                        const argsArr = interpNewArray("")
                        for (arp in nGetList(aId).split(",")) {
                            const argId = parseInt(arp)
                            if (argId > 0 && nGetKind(argId) == "STRING_LIT") {
                                interpArrayPush(argsArr, interpNewString(nGetS1(argId)))
                            }
                        }
                        interpSetField(metaTv, "args", argsArr)
                        interpArrayPush(arr, metaTv)
                    }
                }
            }
            return ctVal(arr)
        }
    }
    if (comptimeDepth > 0) {
        return comptimeError(`cannot access field '${member}' on ${isCt(obj) == 1 ? interpType(payload(obj)) : "runtime"} value`, astId)
    }
    if (nGetI3(astId) > 0) { return 0 - constVal(genOptionalMemberAccess(astId, reg(obj))) - 1 }
    return 0 - constVal(genMemberAccess(astId, reg(obj))) - 1
}
