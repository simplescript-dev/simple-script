// D108 §步骤 1: MEMBER_ACCESS 迁出 eval_expr.ss 独立子目录文件
// 对称三段式:FieldMeta f.name/.type/.annotations → enum X.Y → ct obj field/length/name/fields/annotations → runtime

function evalMemberAccess(astId: int): int {
    const member = nGetS1(astId)
    const objNode = nGetI1(astId)
    if (nGetKind(objNode) == "IDENT") {
        const eName = nGetS1(objNode)
        const enumKey = `${eName}.${member}`
        if (interpEnumValues.has(enumKey) == 1) {
            const ieVal = interpEnumValues.getString(enumKey)
            return ctVal(interpEnumTypes.has(eName) == 1 ? interpNewString(ieVal) : interpNewInt(parseInt(ieVal)))
        }
        if (enumReady == 1 && enumValues.has(enumKey) == 1) {
            const eVal = enumValues.getString(enumKey)
            return ctVal(enumTypes.has(eName) == 1 ? interpNewString(eVal) : interpNewInt(parseInt(eVal)))
        }
        if (comptimeDepth == 0 && getVarType(eName) == "" && classFields.has(eName) == 1) {
            return 0 - constVal(genMemberAccess(astId)) - 1
        }
    }
    const obj = genVal(objNode)
    if (isCt(obj) == 1) {
        const objPayload = payload(obj)
        const mpKind = interpType(objPayload)
        if (mpKind == "object") { return ctVal(interpGetField(objPayload, member)) }
        if (member == "length" && (mpKind == "string" || mpKind == "array")) {
            const items = interpAsStr(objPayload)
            return ctVal(interpNewInt(mpKind == "string" ? items.length() : (items == "" ? 0 : items.split(",").length())))
        }
        // D117 §决策 4 — string/TypeValue 当作 class 句柄 .name/.fields/.methods/
        // .annotations 全部统一经 ClassMeta interpGetField read,消除 hardcoded 字符串
        // 数组 + AST 构造 AnnotationMeta 两条特例。未知 class 时 .name 回落 string tvId。
        if ((member == "name" || member == "fields" || member == "methods" || member == "annotations") && (mpKind == "string" || mpKind == "type")) {
            const clsName = interpAsStr(objPayload)
            if (isKnownClass(clsName) == 1) { return ctVal(interpGetField(interpBuildTypeInfo(clsName), member)) }
            if (member == "name") { return mpKind == "type" ? ctVal(interpNewString(clsName)) : obj }
        }
    }
    if (comptimeDepth > 0) {
        return comptimeError(`cannot access field '${member}' on ${isCt(obj) == 1 ? interpType(payload(obj)) : "runtime"} value`, astId)
    }
    if (nGetI3(astId) > 0) { return 0 - constVal(genOptionalMemberAccess(astId, reg(obj))) - 1 }
    return 0 - constVal(genMemberAccess(astId, reg(obj))) - 1
}
