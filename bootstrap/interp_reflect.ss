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
    // Enum reflection
    if (enumReady == 1 && enumDeclNodes.has(className) == 1) {
        return interpBuildEnumInfo(className)
    }
    // Interface reflection
    if (ifaceMethodsCG.has(className) == 1 && classFields.has(className) == 0) {
        return interpBuildInterfaceInfo(className)
    }
    if (classFields.has(className) == 0) {
        println(`[interp] @typeInfo: unknown type '${className}'`)
        return interpNewNull()
    }
    const infoId = interpNewVal("object", "ClassInfo")
    interpSetField(infoId, "name", interpNewString(className))
    interpSetField(infoId, "kind", interpNewString("class"))

    // Resolve CLASS_DECL node once for fields, methods, and class annotations
    let classNodeId = 0
    if (classNodeIds.has(className) == 1) {
        classNodeId = parseInt(classNodeIds.getString(className))
    }

    // Fields
    const fieldsArr = interpNewArray("")
    let fieldParamParts: Array<string> = []
    if (classNodeId > 0) {
        const fNodeList = nGetList(classNodeId)
        if (fNodeList != "") { fieldParamParts = fNodeList.split(",") }
    }
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
            // Field annotations — PARAM nList stores ANNOTATION_LIST node ID
            // (can't use I4 like methods because PARAM I4 is isStatic for class fields)
            let fAnnListId = 0
            let fpi = 0
            while (fpi < fieldParamParts.length()) {
                const fpId = parseInt(fieldParamParts[fpi])
                if (fpId > 0 && nGetKind(fpId) == "PARAM" && nGetS1(fpId) == fName) {
                    const fpList = nGetList(fpId)
                    if (fpList != "") { fAnnListId = parseInt(fpList) }
                    fpi = fieldParamParts.length()
                } else {
                    fpi = fpi + 1
                }
            }
            interpSetField(fieldObj, "annotations", interpBuildAnnotationArray(fAnnListId))
            interpArrayPush(fieldsArr, fieldObj)
            fi = fi + 1
        }
    }
    interpSetField(infoId, "fields", fieldsArr)

    // Methods
    const methodsArr = interpNewArray("")
    let mdParts: Array<string> = []
    if (classNodeId > 0) {
        const mBlock = nGetI2(classNodeId)
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
    if (classNodeId > 0) {
        caAnnListId = nGetI4(classNodeId)
    }
    interpSetField(infoId, "annotations", interpBuildAnnotationArray(caAnnListId))
    return infoId
}

// ── Enum Reflection ─────────────────────────────────────────

function interpBuildEnumInfo(enumName: string): int {
    const infoId = interpNewVal("object", "EnumInfo")
    interpSetField(infoId, "name", interpNewString(enumName))
    interpSetField(infoId, "kind", interpNewString("enum"))
    const isString = enumTypes.has(enumName) == 1 ? 1 : 0
    interpSetField(infoId, "isString", interpNewInt(isString))

    // Build variants array from ENUM_DECL AST node
    const variantsArr = interpNewArray("")
    const nodeId = parseInt(enumDeclNodes.getString(enumName))
    if (nodeId > 0) {
        const vList = nGetList(nodeId)
        if (vList != "") {
            const vParts = vList.split(",")
            let vi = 0
            while (vi < vParts.length()) {
                const vid = parseInt(vParts[vi])
                if (vid > 0 && nGetKind(vid) == "ENUM_VARIANT") {
                    const vObj = interpNewVal("object", "VariantInfo")
                    interpSetField(vObj, "name", interpNewString(nGetS1(vid)))
                    if (isString == 1) {
                        interpSetField(vObj, "value", interpNewString(nGetS2(vid)))
                    } else {
                        interpSetField(vObj, "value", interpNewInt(nGetI1(vid)))
                    }
                    interpArrayPush(variantsArr, vObj)
                }
                vi = vi + 1
            }
        }
    }
    interpSetField(infoId, "variants", variantsArr)
    return infoId
}

// ── Interface Reflection ────────────────────────────────────

function interpBuildInterfaceInfo(ifaceName: string): int {
    const infoId = interpNewVal("object", "InterfaceInfo")
    interpSetField(infoId, "name", interpNewString(ifaceName))
    interpSetField(infoId, "kind", interpNewString("interface"))

    const methodsArr = interpNewArray("")
    const methodStr = ifaceMethodsCG.getString(ifaceName)
    if (methodStr != "") {
        const mParts = methodStr.split(",")
        let mi = 0
        while (mi < mParts.length()) {
            const mName = mParts[mi]
            if (mName != "") {
                const methodObj = interpNewVal("object", "MethodInfo")
                interpSetField(methodObj, "name", interpNewString(mName))
                const methodKey = `${ifaceName}.${mName}`
                let mRetType = "void"
                if (ifaceMethodRets.has(methodKey) == 1) {
                    mRetType = ifaceMethodRets.getString(methodKey)
                }
                interpSetField(methodObj, "returnType", interpNewString(mRetType))
                const paramsArr = interpNewArray("")
                if (ifaceMethodPars.has(methodKey) == 1) {
                    const parStr = ifaceMethodPars.getString(methodKey)
                    if (parStr != "") {
                        const pParts = parStr.split(",")
                        let pi = 0
                        while (pi < pParts.length()) {
                            const pp = pParts[pi]
                            if (pp != "") {
                                const colonIdx = pp.indexOf(":")
                                if (colonIdx >= 0) {
                                    const pObj = interpNewVal("object", "ParamInfo")
                                    interpSetField(pObj, "name", interpNewString(pp.substring(0, colonIdx)))
                                    interpSetField(pObj, "type", interpNewString(pp.substring(colonIdx + 1, pp.length() - colonIdx - 1)))
                                    interpSetField(pObj, "annotation", interpNewString(""))
                                    interpArrayPush(paramsArr, pObj)
                                }
                            }
                            pi = pi + 1
                        }
                    }
                }
                interpSetField(methodObj, "params", paramsArr)
                interpSetField(methodObj, "annotations", interpNewArray(""))
                interpArrayPush(methodsArr, methodObj)
            }
            mi = mi + 1
        }
    }
    interpSetField(infoId, "methods", methodsArr)
    return infoId
}
