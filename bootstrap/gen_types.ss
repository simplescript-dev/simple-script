// Type inference, type helpers, and method overloading for bootstrap codegen
// Extracted from gen_exprs.ss — pure query functions (no IR emission)

// ── Tuple type helpers ────────────────────────────────────────

function isTupleType(t: string): int {
    if (t.startsWith("Tuple<") == 1) { return 1 }
    return 0
}

// Extract the element type at a given index from a tuple type string
// e.g. tupleElemTypeAtIndex("Tuple<int,string>", 1) → "string"
function tupleElemTypeAtIndex(tupleType: string, idx: int): string {
    const inner = tupleType.substring(6, tupleType.length() - 7)
    let depth = 0
    let start = 0
    let pos = 0
    let i = 0
    while (i < inner.length()) {
        const ch = inner.substring(i, 1)
        if (ch == "<") { depth = depth + 1 }
        if (ch == ">") { depth = depth - 1 }
        if (ch == "," && depth == 0) {
            if (pos == idx) { return inner.substring(start, i - start) }
            pos = pos + 1
            start = i + 1
        }
        i = i + 1
    }
    if (pos == idx) { return inner.substring(start, inner.length() - start) }
    return ""
}

// ── Type inference ────────────────────────────────────────────

// Infer element type of an array expression (returns "string", "int", "double", or "")
function inferArrayElemType(arrId: int): string {
    if (arrId <= 0) { return "" }
    const aeKind = nGetKind(arrId)
    if (aeKind == "IDENT") {
        const aeType = getVarType(nGetS1(arrId))
        if (aeType.contains("<string>") == 1) { return "string" }
        if (aeType.contains("<int>") == 1) { return "int" }
        if (aeType.contains("<double>") == 1) { return "double" }
    }
    if (aeKind == "METHOD_CALL") {
        const aeMethod = nGetS1(arrId)
        if (aeMethod == "split") { return "string" }
        if (aeMethod == "filter" || aeMethod == "slice" || aeMethod == "reverse" || aeMethod == "sort") {
            return inferArrayElemType(nGetI1(arrId))
        }
    }
    return ""
}

// Resolve the CLASS name of an expression (returns class name or "")
function resolveObjClass(nodeId: int): string {
    if (nodeId <= 0) { return "" }
    const kind = nGetKind(nodeId)
    // Variable → check varType for class name
    if (kind == "IDENT") {
        const vt = getVarType(nGetS1(nodeId))
        if (vt != "" && classFields.has(vt) == 1) { return vt }
        if (vt != "" && ifaceMethodsCG.has(vt) == 1) { return vt }
        const oc = getObjClass(nGetS1(nodeId))
        if (oc != "") { return oc }
        // Class name used as static method target (e.g., JSON.create())
        if (classFields.has(nGetS1(nodeId)) == 1) { return nGetS1(nodeId) }
        return ""
    }
    // this → current class
    if (kind == "THIS" && currentClassName != "") { return currentClassName }
    // new ClassName() → class name directly (mangled for generic classes)
    if (kind == "NEW_EXPR") {
        const neCn = nGetS1(nodeId)
        if (genericClassNodes.has(neCn) == 1) { return inferGenericClassName(neCn, nGetList(nodeId), nGetS2(nodeId)) }
        return neCn
    }
    // Function call → check return type
    if (kind == "CALL") {
        const callee = nGetS1(nodeId)
        if (funcRetTypes.has(callee) == 1) {
            const rt = funcRetTypes.getString(callee)
            if (classFields.has(rt) == 1) { return rt }
            if (ifaceMethodsCG.has(rt) == 1) { return rt }
        }
        return ""
    }
    // Method call → recursively resolve object, then look up method return type
    if (kind == "METHOD_CALL") {
        const rt = inferType(nodeId)
        if (classFields.has(rt) == 1) { return rt }
        if (ifaceMethodsCG.has(rt) == 1) { return rt }
        return ""
    }
    // Member access → resolve object class, look up field type
    if (kind == "MEMBER_ACCESS") {
        const objClass = resolveObjClass(nGetI1(nodeId))
        if (objClass != "") {
            const fType = classFieldTypes.getString(`${objClass}.${nGetS1(nodeId)}`)
            if (fType != "" && classFields.has(fType) == 1) { return fType }
        }
        return ""
    }
    return ""
}

function inferType(id: int): string {
    if (id <= 0) { return "int" }
    const kind = nGetKind(id)
    if (kind == "INT_LIT") { return "int" }
    if (kind == "DOUBLE_LIT") { return "double" }
    if (kind == "STRING_LIT") { return "string" }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT") { return "int" }
    if (kind == "NULL_LIT") { return "ptr" }
    if (kind == "TEMPLATE_LIT") { return "string" }
    if (kind == "THIS") {
        if (currentClassName != "") { return currentClassName }
        return "ptr"
    }
    if (kind == "IDENT") {
        const vType = getVarType(nGetS1(id))
        if (vType != "") { return vType }
        if (funcRetTypes.has(nGetS1(id)) == 1) { return "fn" }
        return "int"
    }
    if (kind == "BINARY") {
        const op = nGetS1(id)
        if (op == "Add") {
            const blt2 = inferType(nGetI1(id))
            if (blt2 == "string") { return "string" }
            const brt2 = inferType(nGetI2(id))
            if (brt2 == "string") { return "string" }
        }
        if (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge" || op == "And" || op == "Or") {
            return "int"
        }
        const binLt = inferType(nGetI1(id))
        const binRt = inferType(nGetI2(id))
        if (binLt == "double" || binRt == "double") { return "double" }
        if (binLt == "i64") { return "int" }
        return binLt
    }
    if (kind == "CALL") {
        const callee = nGetS1(id)
        if (callee == "Map") { return "Map" }
        if (getVarType(callee) == "fn" || getVarType(callee) == "i64") { return "i64" }
        // Generic function: infer return type from arguments
        if (genericFuncNodes.has(callee) == 1) {
            const grt = inferGenericRetType(callee, nGetList(id), nGetS2(id))
            if (grt != "") { return grt }
        }
        // Use funcRetTypes directly — preserves class names
        if (funcRetTypes.has(callee) == 1) {
            return funcRetTypes.getString(callee)
        }
        return callReturnType(callee)
    }
    if (kind == "NEW_EXPR") {
        const newCn = nGetS1(id)
        if (genericClassNodes.has(newCn) == 1) { return inferGenericClassName(newCn, nGetList(id), nGetS2(id)) }
        return newCn
    }
    if (kind == "METHOD_CALL") {
        const method = nGetS1(id)
        // Resolve object type FIRST via unified inferType (recursive)
        const objType = resolveObjClass(nGetI1(id))
        // If object is a known class, look up method return type in class chain
        if (objType != "" && objType != "string" && objType != "int" && objType != "double") {
            let lookupClass = objType
            while (lookupClass != "") {
                if (funcRetTypes.has(`${lookupClass}_${method}`) == 1) {
                    return funcRetTypes.getString(`${lookupClass}_${method}`)
                }
                if (classParents.has(lookupClass) == 1) {
                    lookupClass = classParents.getString(lookupClass)
                } else {
                    lookupClass = ""
                }
            }
        }
        // Interface method return type lookup
        if (ifaceMethodsCG.has(objType) == 1 && ifaceMethodRets.has(`${objType}.${method}`) == 1) {
            return ifaceMethodRets.getString(`${objType}.${method}`)
        }
        // find() returns the array element type
        if (method == "find") {
            const elemType = inferArrayElemType(nGetI1(id))
            if (elemType != "") { return elemType }
        }
        // Built-in method return types (fallback for string/array/map methods)
        if (methodRetTypes.has(method) == 1) {
            return methodRetTypes.getString(method)
        }
        return "int"
    }
    if (kind == "MEMBER_ACCESS") {
        const mField = nGetS1(id)
        const mObj = nGetI1(id)
        let maClassName = resolveObjClass(mObj)
        if (maClassName != "" && classFieldTypes.has(`${maClassName}.${mField}`) == 1) {
            return classFieldTypes.getString(`${maClassName}.${mField}`)
        }
        return "int"
    }
    if (kind == "GROUPING") { return inferType(nGetI1(id)) }
    if (kind == "UNARY") { return inferType(nGetI1(id)) }
    if (kind == "TERNARY") { return inferType(nGetI2(id)) }
    if (kind == "ARRAY_LIT") { return "ptr" }
    if (kind == "ARROW_FUNC") { return "fn" }
    if (kind == "INDEX_ACCESS") {
        // Tuple type: positional element type inference
        if (nGetKind(nGetI1(id)) == "IDENT") {
            const iaVarType = getVarType(nGetS1(nGetI1(id)))
            if (isTupleType(iaVarType) == 1 && nGetKind(nGetI2(id)) == "INT_LIT") {
                const tIdx = parseInt(nGetS1(nGetI2(id)))
                const tElem = tupleElemTypeAtIndex(iaVarType, tIdx)
                if (tElem != "") { return tElem }
            }
        }
        const iaElem = inferArrayElemType(nGetI1(id))
        if (iaElem != "") { return iaElem }
        return "i64"
    }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { return "int" }
    if (kind == "SPREAD_ELEM") { return inferType(nGetI1(id)) }
    if (kind == "NAMED_ARG") { return inferType(nGetI1(id)) }
    return "int"
}

function preludeName(cName: string): string {
    const pName = `_${cName}`
    if (funcRetTypes.has(pName) == 1) { return pName }
    return cName
}

function callReturnType(callee: string): string {
    if (funcRetTypes.has(callee) == 1) {
        return funcRetTypes.getString(callee)
    }
    return "int"
}

// Infer concrete return type for a generic function call
function inferGenericRetType(callee: string, argList: string, explicitTypes: string): string {
    if (genericFuncNodes.has(callee) == 0) { return "" }
    const funcNodeId = parseInt(genericFuncNodes.getString(callee))
    const declRet = nGetS2(funcNodeId)
    if (declRet == "") { return "void" }
    const typeParams = nGetS3(funcNodeId)
    // If return type is not a type param, return it directly
    let isRetTP = 0
    const tpParts = typeParams.split(",")
    for (tpp in tpParts) {
        if (tpp == declRet) { isRetTP = 1 }
    }
    if (isRetTP == 0) { return declRet }
    // Explicit type args: resolve directly
    if (explicitTypes != "") {
        let tpIdx = 0
        for (tpp in tpParts) {
            if (tpp == declRet) { return listGet(explicitTypes, tpIdx) }
            tpIdx = tpIdx + 1
        }
        return "int"
    }
    // Match declared params to actual args to resolve type params
    const declParams = nGetList(funcNodeId)
    if (declParams == "" || argList == "") { return "int" }
    const dParts = declParams.split(",")
    const aParts = argList.split(",")
    let argIdx = 0
    for (dp in dParts) {
        const pId = parseInt(dp)
        if (pId <= 0 || nGetKind(pId) != "PARAM") { continue }
        const pType = nGetS2(pId)
        if (pType == declRet) {
            let ai = 0
            for (ap in aParts) {
                if (ai == argIdx) { return inferType(parseInt(ap)) }
                ai = ai + 1
            }
        }
        argIdx = argIdx + 1
    }
    return "int"
}

// Infer mangled class name for a generic class instantiation (e.g., "Box" + [42] → "Box_i")
function inferGenericClassName(className: string, argList: string, explicitTypes: string): string {
    if (genericClassNodes.has(className) == 0) { return className }
    const classNodeId = parseInt(genericClassNodes.getString(className))
    const typeParamStr = classTypeParams(classNodeId)
    const typeParamList = typeParamStr.split(",")
    const declFields = classFieldList(classNodeId)
    const subs = Map()
    if (explicitTypes != "") {
        let tpIdx = 0
        for (tp in typeParamList) {
            subs.set(tp, listGet(explicitTypes, tpIdx))
            tpIdx = tpIdx + 1
        }
    } else if (declFields != "" && argList != "") {
        const fParts = declFields.split(",")
        const aParts = argList.split(",")
        let argIdx = 0
        for (fp in fParts) {
            const pId = parseInt(fp)
            if (pId <= 0 || nGetKind(pId) != "PARAM") { continue }
            const pType = nGetS2(pId)
            let isTP = 0
            for (tp in typeParamList) { if (tp == pType) { isTP = 1 } }
            if (isTP == 1 && subs.has(pType) == 0) {
                let ai = 0
                for (ap in aParts) {
                    if (ai == argIdx) { subs.set(pType, inferType(parseInt(ap))) }
                    ai = ai + 1
                }
            }
            argIdx = argIdx + 1
        }
    }
    let mangledSig = ""
    for (tp in typeParamList) {
        if (subs.has(tp) == 1) {
            if (mangledSig != "") { mangledSig = `${mangledSig}_` }
            mangledSig = `${mangledSig}${typeSig(subs.getString(tp))}`
        }
    }
    const mangledName = mangledSig != "" ? `${className}_${mangledSig}` : className
    // Ensure Maps are pre-registered so ssTypeToLLVM etc. recognize the mangled name
    if (classFields.has(mangledName) == 0) {
        preRegisterSpecializedClass(classNodeId, mangledName, subs)
    }
    return mangledName
}

// ── Type helpers ──────────────────────────────────────────────

// Resolve generic type param via active substitution map (e.g., "T" → "int")
function resolveTypeParam(t: string): string {
    if (genericTypeSubs.has(t) == 1) { return genericTypeSubs.getString(t) }
    return t
}

function ssTypeToLLVM(t: string): string {
    // Generic type param substitution (active during specialization)
    if (genericTypeSubs.has(t) == 1) { return ssTypeToLLVM(genericTypeSubs.getString(t)) }
    if (t == "int" || t == "bool" || t == "auto" || t == "") { return "i32" }
    if (t == "double") { return "double" }
    if (t == "string") { return "ptr" }
    if (t == "void") { return "void" }
    if (t == "ptr") { return "ptr" }
    if (t == "fn") { return "i64" }
    if (t == "i64") { return "i64" }
    // Generic types (Array<string>, Map<string,int>, etc.) → ptr
    if (t.contains("<") == 1) { return "ptr" }
    // Interface type names → ptr
    if (ifaceMethodsCG.has(t) == 1) { return "ptr" }
    // Class type names → ptr (includes Map, registered as built-in class)
    if (classFields.has(t) == 1) { return "ptr" }
    // Generic type params (single uppercase letter like T, U, V) → ptr (erased)
    if (t.length() == 1 && charCodeAt(t, 0) >= 65 && charCodeAt(t, 0) <= 90) { return "ptr" }
    return "i32"
}

function setVarType(name: string, varType: string) {
    varTypes.set(`${currentFunc}:${name}`, varType)
}

function getVarType(name: string): string {
    const scopedKey = `${currentFunc}:${name}`
    if (varTypes.has(scopedKey) == 1) {
        return varTypes.getString(scopedKey)
    }
    const globalKey = `:${name}`
    if (varTypes.has(globalKey) == 1) {
        return varTypes.getString(globalKey)
    }
    return ""
}

// ── Method overloading: type signature ───────────────────────

function typeSig(ssType: string): string {
    if (genericTypeSubs.has(ssType) == 1) { return typeSig(genericTypeSubs.getString(ssType)) }
    if (ssType == "int" || ssType == "bool" || ssType == "auto" || ssType == "") { return "i" }
    if (ssType == "double") { return "d" }
    if (ssType == "string") { return "s" }
    if (ssType == "fn") { return "f" }
    if (ssType == "void") { return "v" }
    if (ssType.contains("<") == 1) { return "p" }
    // Class name → use full name
    return ssType
}

function paramSig(paramList: string): string {
    if (paramList == "") { return "" }
    let sig = ""
    const parts = paramList.split(",")
    for (p in parts) {
        const pId = parseInt(p)
        if (pId > 0 && nGetKind(pId) == "PARAM") {
            if (sig != "") { sig = `${sig}_` }
            sig = `${sig}${typeSig(nGetS2(pId))}`
        }
    }
    return sig
}

function argsSig(argList: string): string {
    if (argList == "") { return "" }
    let sig = ""
    const parts = argList.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0) {
            const aType = inferType(argId)
            if (sig != "") { sig = `${sig}_` }
            // For IDENT with class type, use class name
            if (nGetKind(argId) == "IDENT") {
                const objClass = getObjClass(nGetS1(argId))
                if (objClass != "") {
                    sig = `${sig}${objClass}`
                    continue
                }
            }
            if (nGetKind(argId) == "NEW_EXPR") {
                sig = `${sig}${nGetS1(argId)}`
                continue
            }
            sig = `${sig}${typeSig(aType)}`
        }
    }
    return sig
}

function resolveOverload(baseName: string, argList: string): string {
    // Only resolve overloads for functions with multiple signatures
    if (overloadReady == 0) { return baseName }
    if (overloadCount.has(baseName) == 0) { return baseName }
    if (parseInt(overloadCount.getString(baseName)) <= 1) { return baseName }
    // This function IS overloaded — find the right signature
    const sig = argsSig(argList)
    if (sig != "") {
        const mangled = `${baseName}_${sig}`
        if (funcRetTypes.has(mangled) == 1) { return mangled }
    }
    return baseName
}
