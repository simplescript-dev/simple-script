// interp_reflect.ss — Compile-time reflection for the AST interpreter
//
// Handles @typeInfo(T) and getTypeInfo(className): builds interpreter objects
// representing class structure (fields, methods, annotations, params).
// Forward-references value/field/array helpers from interp.ss
// and compiler registries (classFields, classMethods, etc.) from codegen/gen_class.

// ── @typeInfo Reflection (D087 Phase 3a) ─────────────────────

function interpBuildMethodParams(mdParts: Array<string>, mName: string): int {
    const paramsArr = interpNewArray("")
    let mdi = 0
    while (mdi < mdParts.length()) {
        const mdId = parseInt(mdParts[mdi])
        if (nGetKind(mdId) == "FUNC_DECL" && nGetS1(mdId) == mName) {
            const pList = nGetList(mdId)
            if (pList != "") {
                const pParts = pList.split(",")
                let pi = 0
                while (pi < pParts.length()) {
                    const pId = parseInt(pParts[pi])
                    if (nGetKind(pId) == "PARAM") {
                        const pObj = interpNewVal("object", "ParamInfo")
                        interpSetField(pObj, "name", interpNewString(nGetS1(pId)))
                        interpSetField(pObj, "type", interpNewString(nGetS2(pId)))
                        // Param annotation (e.g., @PathVariable) — PARAM I4
                        const pAnnId = nGetI4(pId)
                        let pAnnName = ""
                        if (pAnnId > 0 && nGetKind(pAnnId) == "ANNOTATION") {
                            pAnnName = nGetS1(pAnnId)
                        }
                        interpSetField(pObj, "annotation", interpNewString(pAnnName))
                        interpArrayPush(paramsArr, pObj)
                    }
                    pi = pi + 1
                }
            }
            return paramsArr
        }
        mdi = mdi + 1
    }
    return paramsArr
}

// Build interpreter array of AnnotationInfo {name, args} from ANNOTATION_LIST node
function interpBuildAnnotationArray(annListId: int): int {
    const annArr = interpNewArray("")
    if (annListId <= 0 || nGetKind(annListId) != "ANNOTATION_LIST") { return annArr }
    const annListStr = nGetList(annListId)
    if (annListStr == "") { return annArr }
    const annParts = annListStr.split(",")
    let ai = 0
    while (ai < annParts.length()) {
        const aId = parseInt(annParts[ai])
        if (aId > 0 && nGetKind(aId) == "ANNOTATION") {
            const aObj = interpNewVal("object", "AnnotationInfo")
            interpSetField(aObj, "name", interpNewString(nGetS1(aId)))
            interpSetField(aObj, "args", interpNewString(nGetS2(aId)))
            interpArrayPush(annArr, aObj)
        }
        ai = ai + 1
    }
    return annArr
}

function interpBuildTypeInfo(className: string): int {
    if (classFields.has(className) == 0) {
        println(`[interp] @typeInfo: unknown class '${className}'`)
        return interpNewNull()
    }
    const infoId = interpNewVal("object", "ClassInfo")
    interpSetField(infoId, "name", interpNewString(className))

    // Fields
    const fieldsArr = interpNewArray("")
    const fieldStr = classFields.getString(className)
    if (fieldStr != "") {
        const fParts = fieldStr.split(",")
        let fi = 0
        while (fi < fParts.length()) {
            const fName = fParts[fi]
            let fType = "unknown"
            if (classFieldTypes.has(`${className}.${fName}`) == 1) {
                fType = classFieldTypes.getString(`${className}.${fName}`)
            }
            const fieldObj = interpNewVal("object", "FieldInfo")
            interpSetField(fieldObj, "name", interpNewString(fName))
            interpSetField(fieldObj, "type", interpNewString(fType))
            interpArrayPush(fieldsArr, fieldObj)
            fi = fi + 1
        }
    }
    interpSetField(infoId, "fields", fieldsArr)

    // Methods — cache AST method list outside loop
    const methodsArr = interpNewArray("")
    let mdParts: Array<string> = []
    if (classNodeIds.has(className) == 1) {
        const cNodeId = parseInt(classNodeIds.getString(className))
        const mBlock = nGetI2(cNodeId)
        if (mBlock > 0) {
            const mList = nGetList(mBlock)
            if (mList != "") { mdParts = mList.split(",") }
        }
    }
    const methodStr = classMethods.getString(className)
    if (methodStr != "") {
        const mParts = methodStr.split(",")
        let mi = 0
        while (mi < mParts.length()) {
            const mName = mParts[mi]
            let mRetType = "void"
            if (funcRetTypes.has(`${className}_${mName}`) == 1) {
                mRetType = funcRetTypes.getString(`${className}_${mName}`)
            }
            const methodObj = interpNewVal("object", "MethodInfo")
            interpSetField(methodObj, "name", interpNewString(mName))
            interpSetField(methodObj, "returnType", interpNewString(mRetType))
            interpSetField(methodObj, "params", interpBuildMethodParams(mdParts, mName))
            // Method annotations — find FUNC_DECL for this method, extract I4
            let mAnnListId = 0
            let mdx = 0
            while (mdx < mdParts.length()) {
                const mdxId = parseInt(mdParts[mdx])
                if (nGetKind(mdxId) == "FUNC_DECL" && nGetS1(mdxId) == mName) {
                    mAnnListId = nGetI4(mdxId)
                    mdx = mdParts.length()
                } else {
                    mdx = mdx + 1
                }
            }
            interpSetField(methodObj, "annotations", interpBuildAnnotationArray(mAnnListId))
            interpArrayPush(methodsArr, methodObj)
            mi = mi + 1
        }
    }
    interpSetField(infoId, "methods", methodsArr)

    // Class annotations
    let caAnnListId = 0
    if (classNodeIds.has(className) == 1) {
        caAnnListId = nGetI4(parseInt(classNodeIds.getString(className)))
    }
    interpSetField(infoId, "annotations", interpBuildAnnotationArray(caAnnListId))
    return infoId
}
