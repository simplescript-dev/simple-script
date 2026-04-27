// SimpleScript Bootstrap Checker — Class layer
// Class name resolution + method/inheritance/constructor param resolution + interface/abstract impl checks + class decl registration.
// Factored out of checker.ss by D114 Execute 4.

// ── Class name resolution ─────────────────────────────────────

// Normalize generic type to base class name for method dispatch (Array<int> → Array, Player? → Player)
function resolveCheckerClass(cls: string): string {
    if (cls == "" || cls == "null") { return "" }
    const stripped = stripNullable(cls)
    if (classConsMin.has(stripped) == 1) { return stripped }
    const base = baseTypeName(stripped)
    if (base != stripped && classConsMin.has(base) == 1) { return base }
    return stripped
}

// Infer class name from an expression node (for method dispatch / field checking)
function inferCheckerClass(nodeId: int): string {
    if (nodeId <= 0) { return "" }
    const kind = nGetKind(nodeId)
    if (kind == "IDENT") {
        return resolveCheckerClass(lookupVar(nGetS1(nodeId)))
    }
    if (kind == "THIS") { return currentCheckerClass }
    if (kind == "SUPER") {
        if (currentCheckerClass != "" && checkerClassParents.has(currentCheckerClass) == 1) {
            return checkerClassParents.getString(currentCheckerClass)
        }
        return ""
    }
    if (kind == "NEW_EXPR") { return nGetS1(nodeId) }
    if (kind == "STRING_LIT" || kind == "TEMPLATE_LIT") { return "string" }
    if (kind == "ARRAY_LIT") { return "Array" }
    if (kind == "MEMBER_ACCESS") {
        const objClass = inferCheckerClass(nGetI1(nodeId))
        if (objClass == "") { return "" }
        const fieldKey = `${objClass}.${nGetS1(nodeId)}`
        if (checkerFieldTypes.has(fieldKey) == 1) {
            return resolveCheckerClass(checkerFieldTypes.getString(fieldKey))
        }
        return ""
    }
    if (kind == "CALL") {
        const fname = nGetS1(nodeId)
        if (funcNames.has(fname) == 1) {
            return resolveCheckerClass(funcNames.getString(fname))
        }
        return ""
    }
    if (kind == "METHOD_CALL") {
        const objClass = inferCheckerClass(nGetI1(nodeId))
        if (objClass != "" && classConsMin.has(objClass) == 1) {
            return resolveCheckerClass(lookupMethodRetType(objClass, nGetS1(nodeId)))
        }
        return ""
    }
    return ""
}

// ── Interface / abstract impl checks ──────────────────────────

function checkInterfaceImpl(classNodeId: int, className: string, implList: string, classMethods: string) {
    // Scan comma-separated interface names without for-in (avoids i64/ptr issue)
    let remaining = implList
    while (remaining != "") {
        let iface = remaining
        const commaIdx = remaining.indexOf(",")
        if (commaIdx >= 0) {
            iface = remaining.substring(0, commaIdx)
            remaining = remaining.substring(commaIdx + 1, remaining.length() - commaIdx - 1)
        } else {
            remaining = ""
        }
        if (ifaceMethods.has(iface) == 1) {
            const required = ifaceMethods.getString(iface)
            if (required != "") {
                let remReq = required
                while (remReq != "") {
                    let req = remReq
                    const ci = remReq.indexOf(",")
                    if (ci >= 0) {
                        req = remReq.substring(0, ci)
                        remReq = remReq.substring(ci + 1, remReq.length() - ci - 1)
                    } else {
                        remReq = ""
                    }
                    if (classMethods.contains(`,${req},`) == 0) {
                        checkerError(`class '${className}' missing method '${req}' required by interface '${iface}'`, nGetLine(classNodeId), nGetCol(classNodeId))
                    }
                }
            }
        }
    }
}

// D071: Check that a non-abstract class implements all inherited abstract methods
function checkAbstractImpl(className: string, parentName: string, ownMethods: string, line: int, col: int) {
    // Collect all concrete method names from self + parent chain (non-abstract)
    let allImpl = ownMethods
    let p = parentName
    while (p != "") {
        if (classMethodNames.has(p) == 1) {
            const pMethods = classMethodNames.getString(p)
            if (pMethods != ",") {
                // Add each non-abstract parent method
                let rem = pMethods.substring(1, pMethods.length() - 1)
                while (rem != "") {
                    let m = rem
                    const ci = rem.indexOf(",")
                    if (ci >= 0) {
                        m = rem.substring(0, ci)
                        rem = rem.substring(ci + 1, rem.length() - ci - 1)
                    } else {
                        rem = ""
                    }
                    if (m != "" && abstractMethods.has(`${p}.${m}`) == 0) {
                        if (allImpl.contains(`,${m},`) == 0) {
                            allImpl = `${allImpl}${m},`
                        }
                    }
                }
            }
        }
        if (checkerClassParents.has(p) == 1) {
            p = checkerClassParents.getString(p)
        } else {
            p = ""
        }
    }
    // Check all abstract methods from parent chain are implemented
    p = parentName
    while (p != "") {
        if (classMethodNames.has(p) == 1) {
            const pMethods = classMethodNames.getString(p)
            if (pMethods != ",") {
                let rem = pMethods.substring(1, pMethods.length() - 1)
                while (rem != "") {
                    let m = rem
                    const ci = rem.indexOf(",")
                    if (ci >= 0) {
                        m = rem.substring(0, ci)
                        rem = rem.substring(ci + 1, rem.length() - ci - 1)
                    } else {
                        rem = ""
                    }
                    if (m != "" && abstractMethods.has(`${p}.${m}`) == 1) {
                        if (allImpl.contains(`,${m},`) == 0) {
                            checkerError(`class '${className}' must implement abstract method '${m}' from '${p}'`, line, col)
                        }
                    }
                }
            }
        }
        if (checkerClassParents.has(p) == 1) {
            p = checkerClassParents.getString(p)
        } else {
            p = ""
        }
    }
}

// ── Method registry + parent-chain lookup ─────────────────────

function registerMethodParams(className: string, methodName: string, minArgs: int, maxArgs: int) {
    const key = `${className}.${methodName}`
    if (methodParamMin.has(key) == 1) {
        const existMin = parseInt(methodParamMin.getString(key))
        const existMax = parseInt(methodParamMax.getString(key))
        if (minArgs < existMin) { methodParamMin.set(key, `${minArgs}`) }
        if (maxArgs > existMax) { methodParamMax.set(key, `${maxArgs}`) }
    } else {
        methodParamMin.set(key, `${minArgs}`)
        methodParamMax.set(key, `${maxArgs}`)
    }
}

// Walk parent chain to find method param counts. Returns "min,max" or "".
function lookupMethodParams(className: string, methodName: string): string {
    let cls = className
    while (cls != "") {
        const key = `${cls}.${methodName}`
        if (methodParamMin.has(key) == 1) {
            return `${methodParamMin.getString(key)},${methodParamMax.getString(key)}`
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    return ""
}

function lookupMethodParamType(className: string, methodName: string, paramIndex: int): string {
    let cls = className
    while (cls != "") {
        const key = `${cls}.${methodName}:${paramIndex}`
        if (methodParamTypes.has(key) == 1) {
            return methodParamTypes.getString(key)
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    return ""
}

function lookupMethodRetType(className: string, methodName: string): string {
    let cls = className
    while (cls != "") {
        const key = `${cls}.${methodName}`
        if (methodRetTypes.has(key) == 1) {
            return methodRetTypes.getString(key)
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    return ""
}

// ── Access control + inheritance chain (D068) ─────────────────

// D068: Walk parent chain to find which class owns a private field/method
function lookupPrivateOwner(className: string, memberName: string, isMethod: int): string {
    let cls = className
    while (cls != "") {
        const key = `${cls}.${memberName}`
        if (isMethod == 1) {
            if (privateMethods.has(key) == 1) { return cls }
        } else {
            if (privateFields.has(key) == 1) { return cls }
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    return ""
}

// D068 Phase 2: Walk parent chain to find which class owns a protected field/method
function lookupProtectedOwner(className: string, memberName: string, isMethod: int): string {
    let cls = className
    while (cls != "") {
        const key = `${cls}.${memberName}`
        if (isMethod == 1) {
            if (protectedMethods.has(key) == 1) { return cls }
        } else {
            if (protectedFields.has(key) == 1) { return cls }
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    return ""
}

// D068 Phase 2: Check if child class is a subclass of ancestor (walks parent chain)
function isSubclassOf(child: string, ancestor: string): int {
    if (child == "" || ancestor == "") { return 0 }
    let cls = child
    while (checkerClassParents.has(cls) == 1) {
        cls = checkerClassParents.getString(cls)
        if (cls == ancestor) { return 1 }
    }
    return 0
}

// ── Constructor param resolution ──────────────────────────────

// Walk parent chain and sum constructor params (own + inherited). Returns "min,max".
function totalConstructorParams(className: string): string {
    let totalMin = 0
    let totalMax = 0
    let cls = className
    while (cls != "") {
        if (classConsMin.has(cls) == 1) {
            totalMin = totalMin + parseInt(classConsMin.getString(cls))
            totalMax = totalMax + parseInt(classConsMax.getString(cls))
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    return `${totalMin},${totalMax}`
}

// Look up constructor param type by walking parent chain (parent fields first).
// Returns "" if type unknown (generic class field, out of range, etc).
function lookupConsParamType(className: string, paramIndex: int): string {
    // Build parent chain from root to leaf
    let chain = ""
    let cls = className
    while (cls != "") {
        if (chain == "") { chain = cls }
        else { chain = `${cls},${chain}` }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    // Walk chain from root to leaf, counting fields
    let idx = 0
    const chainParts = chain.split(",")
    for (cp in chainParts) {
        if (checkerClassFields.has(cp) == 0) { continue }
        const fields = checkerClassFields.getString(cp)
        if (fields == "") { continue }
        const isGeneric = checkerGenericClasses.has(cp)
        const fParts = fields.split(",")
        for (fp in fParts) {
            if (idx == paramIndex) {
                if (isGeneric == 1) { return "" }
                const key = `${cp}.${fp}`
                if (checkerFieldTypes.has(key) == 1) {
                    return checkerFieldTypes.getString(key)
                }
                return ""
            }
            idx = idx + 1
        }
    }
    return ""
}

// ── Class decl registration ───────────────────────────────────

// overrideName == "" 按 nGetS1(s) 注册;否则以别名注册,让 `const W=comptime{...return Wrap}` 的 W 与 Wrap 共享字段/方法签名
function registerCheckerClassDecl(s: int, overrideName: string) {
    const className = overrideName != "" ? overrideName : nGetS1(s)
    defineVar(className, "class", 0)
    if (nGetI1(s) == 1) {
        abstractClasses.set(className, "1")
    }
    let parentName = nGetS2(s)
    if (parentName != "") {
        parentName = baseTypeName(parentName)
        checkerClassParents.set(className, parentName)
    }
    const fieldList = nGetList(s)
    let fieldNameList = ""
    let instanceParamList = ""
    if (fieldList != "") {
        const flds = fieldList.split(",")
        for (f in flds) {
            const fId = parseInt(f)
            if (fId > 0 && nGetKind(fId) == "PARAM") {
                const fName = nGetS1(fId)
                const fType = nGetS2(fId)
                const fKey = `${className}.${fName}`
                checkerFieldTypes.set(fKey, fType)
                if (nGetI4(fId) == 1) {
                    staticFields.set(fKey, "1")
                } else {
                    fieldNameList = listAppendStr(fieldNameList, fName)
                    instanceParamList = listAppend(instanceParamList, fId)
                }
                if (nGetS3(fId) == "const") {
                    constFields.set(fKey, "1")
                }
                if (nGetI3(fId) == 1) {
                    privateFields.set(fKey, "1")
                }
                if (nGetI3(fId) == 2) {
                    protectedFields.set(fKey, "1")
                }
            }
        }
    }
    checkerClassFields.set(className, fieldNameList)
    if (classTypeParams(s) != "") {
        classConsMin.set(className, "0")
        classConsMax.set(className, "99")
        checkerGenericClasses.set(className, "1")
    } else {
        const consRange = countParamRange(instanceParamList)
        const consComma = consRange.indexOf(",")
        classConsMin.set(className, consRange.substring(0, consComma))
        classConsMax.set(className, consRange.substring(consComma + 1, consRange.length() - consComma - 1))
    }
    let clsMethodNameList = ","
    const clsMethodsBlock = nGetI2(s)
    if (clsMethodsBlock > 0) {
        const clsML = nGetList(clsMethodsBlock)
        if (clsML != "") {
            const clsMS = clsML.split(",")
            for (cm in clsMS) {
                const cmId = parseInt(cm)
                if (cmId > 0 && nGetKind(cmId) == "FUNC_DECL") {
                    const mName = nGetS1(cmId)
                    clsMethodNameList = `${clsMethodNameList}${mName},`
                    if (nGetI3(cmId) == 1) {
                        privateMethods.set(`${className}.${mName}`, "1")
                    }
                    if (nGetI3(cmId) == 2) {
                        protectedMethods.set(`${className}.${mName}`, "1")
                    }
                    if (nGetI2(cmId) == 1) {
                        staticMethods.set(`${className}.${mName}`, "1")
                    }
                    if (nGetI4(cmId) == 1) {
                        abstractMethods.set(`${className}.${mName}`, "1")
                        if (abstractClasses.has(className) == 0) {
                            checkerError(`abstract method '${mName}' can only be declared in an abstract class`, nGetLine(cmId), nGetCol(cmId))
                        }
                        if (nGetI3(cmId) == 1) {
                            checkerError(`'private' modifier cannot be used with 'abstract' modifier`, nGetLine(cmId), nGetCol(cmId))
                        }
                        if (nGetI2(cmId) == 1) {
                            checkerError(`'static' modifier cannot be used with 'abstract' modifier`, nGetLine(cmId), nGetCol(cmId))
                        }
                    }
                    const mRange = countParamRange(nGetList(cmId))
                    const mComma = mRange.indexOf(",")
                    const mKey = `${className}.${mName}`
                    if (methodParamMin.has(mKey) == 1) {
                        methodOverloaded.set(mKey, "1")
                    }
                    registerMethodParams(className, mName, parseInt(mRange.substring(0, mComma)), parseInt(mRange.substring(mComma + 1, mRange.length() - mComma - 1)))
                    if (classTypeParams(s) == "") {
                        const mRetType = nGetS2(cmId)
                        if (mRetType != "" && methodOverloaded.has(mKey) == 0) {
                            methodRetTypes.set(mKey, mRetType)
                        }
                        const mPList = nGetList(cmId)
                        if (mPList != "" && methodOverloaded.has(mKey) == 0) {
                            const mParts = mPList.split(",")
                            let mPIdx = 0
                            for (mp in mParts) {
                                const mpId = parseInt(mp)
                                if (mpId > 0 && nGetKind(mpId) == "PARAM") {
                                    const mpType = nGetS2(mpId)
                                    if (mpType != "") {
                                        methodParamTypes.set(`${mKey}:${mPIdx}`, mpType)
                                    }
                                    mPIdx = mPIdx + 1
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    classMethodNames.set(className, clsMethodNameList)
    if (abstractClasses.has(className) == 0 && parentName != "") {
        checkAbstractImpl(className, parentName, clsMethodNameList, nGetLine(s), nGetCol(s))
    }
}

// 扫 stmtList 里所有 VAR_DECL,若 init 是 COMPTIME_EXPR:
//   - 把 body 里的 CLASS_DECL 按原名注册到 checker
//   - 若 body 末尾 return IDENT 指向某 CLASS_DECL 名,把 VAR_DECL 名注册为该 class 的 alias(字段/方法签名共享)
//   - 若 return IDENT 指向 enclosing function 的 type param(如 `function f<T>() { const R = comptime { return T } }`),
//     把 VAR_DECL 名登记到 checkerDeferredAliases:具体 class 由 specialization 决定,checker 跳过字段严校验。
// 递归进 FUNC_DECL body,传下该函数的 type params。
function preScanComptimeClasses(stmtList: string, enclosingTypeParams: string) {
    if (stmtList == "") { return }
    const parts = stmtList.split(",")
    for (p in parts) {
        const s = parseInt(p)
        if (s <= 0) { continue }
        const sk = nGetKind(s)
        if (sk == "FUNC_DECL") {
            const fbId = nGetI1(s)
            if (fbId > 0) { preScanComptimeClasses(nGetList(fbId), nGetS3(s)) }
            continue
        }
        if (sk != "VAR_DECL") { continue }
        const initId = nGetI1(s)
        if (initId <= 0 || nGetKind(initId) != "COMPTIME_EXPR") { continue }
        const bodyId = nGetI1(initId)
        if (bodyId <= 0) { continue }
        const bList = nGetList(bodyId)
        if (bList == "") { continue }
        const bParts = bList.split(",")
        let returnName = ""
        for (bp in bParts) {
            const bs = parseInt(bp)
            if (bs <= 0) { continue }
            if (nGetKind(bs) == "CLASS_DECL") {
                registerCheckerClassDecl(bs, "")
            }
            if (nGetKind(bs) == "RETURN") {
                const retExpr = nGetI1(bs)
                if (retExpr > 0 && nGetKind(retExpr) == "IDENT") {
                    returnName = nGetS1(retExpr)
                }
            }
        }
        if (returnName != "") {
            const varName = nGetS1(s)
            let resolvedAsClassDecl = 0
            for (bp2 in bParts) {
                const bs2 = parseInt(bp2)
                if (bs2 > 0 && nGetKind(bs2) == "CLASS_DECL" && nGetS1(bs2) == returnName) {
                    registerCheckerClassDecl(bs2, varName)
                    resolvedAsClassDecl = 1
                }
            }
            if (resolvedAsClassDecl == 0 && enclosingTypeParams != "") {
                const tpParts = enclosingTypeParams.split(",")
                for (tp in tpParts) {
                    if (tp == returnName) {
                        checkerDeferredAliases.set(varName, "1")
                    }
                }
            }
        }
    }
}
