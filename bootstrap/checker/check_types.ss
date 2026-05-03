// SimpleScript Bootstrap Checker — Type queries
// Nullable helpers (D067) + type inference (checkerInferType) + subtyping/compatibility.
// Factored out of checker.ss by D114 Execute 1.

// ── Null safety helpers (D067) ────────────────────────────────

function isNullableType(t: string): int {
    if (t == "" || t == "null") { return 0 }
    if (t.charAt(t.length() - 1) == "?") { return 1 }
    return 0
}

// Primitive types cannot be nullable (stack values have no null representation)
function isPrimitiveNullable(t: string): int {
    if (t == "int?" || t == "double?" || t == "bool?") { return 1 }
    return 0
}

function stripNullable(t: string): string {
    if (isNullableType(t) == 1) {
        return t.substring(0, t.length() - 1)
    }
    return t
}

function makeNullable(t: string): string {
    if (t == "" || t == "null") { return t }
    if (isNullableType(t) == 1) { return t }
    return `${t}?`
}

// D067 Phase 2: Get narrowed type for a variable (from null guard narrowing)
function getNarrowedType(name: string): string {
    if (narrowedTypes.has(name) == 1) {
        return narrowedTypes.getString(name)
    }
    return ""
}

// ── Type inference + compatibility ────────────────────────────

// D148 Phase 3: bidirectional 单一 entry — expectedType="" 时与原 inferType 行为等价;
// 非空时驱动 ARRAY_LIT / OBJ_LITERAL / ARROW_FUNC / TERNARY 4 case fallback 反推。
function checkerInferType(nodeId: int, expectedType: string): string {
    if (nodeId <= 0) { return "" }
    const kind = nGetKind(nodeId)
    if (kind == "INT_LIT") { return "int" }
    if (kind == "DOUBLE_LIT") { return "double" }
    if (kind == "STRING_LIT" || kind == "TEMPLATE_LIT") { return "string" }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT") { return "int" }
    if (kind == "NULL_LIT") { return "null" }
    if (kind == "ARRAY_LIT") {
        const arrLitS2 = nGetS2(nodeId)
        if (arrLitS2 != "") { return `Array<${arrLitS2}>` }
        const arrIsArrExp = (expectedType != "" && baseTypeName(expectedType) == "Array") ? 1 : 0
        const arrElemExpected = arrIsArrExp == 1 ? extractElemType(expectedType) : ""
        if (arrIsArrExp == 1 && arrElemExpected != "") {
            nSetS2(nodeId, arrElemExpected)
        }
        const arrElems = nGetList(nodeId)
        if (arrElems == "") {
            if (arrIsArrExp == 1) { return expectedType }
            return "Array"
        }
        const arrParts = arrElems.split(",")
        let arrInfer = ""
        let arrHomo = 1
        for (apId in arrParts) {
            if (arrHomo == 0) { break }
            const eId = parseInt(apId)
            if (eId <= 0) { continue }
            if (nGetKind(eId) == "SPREAD_ELEM") { arrHomo = 0; break }
            const eType = checkerInferType(eId, arrElemExpected)
            if (eType == "") { arrHomo = 0; break }
            if (arrInfer == "") { arrInfer = eType } else if (arrInfer != eType) { arrHomo = 0 }
        }
        if (arrHomo == 1 && arrInfer != "") {
            if (arrIsArrExp == 1 && arrInfer == arrElemExpected) { return expectedType }
            return `Array<${arrInfer}>`
        }
        if (arrIsArrExp == 1) { return expectedType }
        return "Array"
    }
    if (kind == "OBJ_LITERAL") {
        const objClsS2 = nGetS2(nodeId)
        if (objClsS2 != "") { return objClsS2 }
        if (expectedType != "" && expectedType != "auto") {
            // Map<K,V> 留 OBJ_LITERAL kind 走 codegen Map literal 路径(Phase 5);ClassName 触发 D084 rewrite
            // checker 接管避免 codegen helper short-circuit `if (nGetS2 != "") return` 漏 rewrite
            const objBase = baseTypeName(expectedType)
            if (objBase == "Map") {
                nSetS2(nodeId, expectedType)
            } else if (checkerClassFields.has(objBase) == 1) {
                nSetS2(nodeId, objBase)
                nKind.set(nodeId + "", "NEW_EXPR")
                nSetS1(nodeId, objBase)
            }
            return expectedType
        }
        return "auto"
    }
    if (kind == "ARROW_FUNC") {
        // D141 Phase 2.1: ARROW_FUNC inferType 返结构化签名 fn(P1,...):R(H11)
        // 全 PARAM s2="" 时降级为单一 "fn"(向后兼容 isTypeCompatible startsWith("fn") + typeSig "f" 路径)
        const arrowParamList = nGetList(nodeId)
        let arrowParamTypes = ""
        let hasAnyAnnotated = 0
        if (arrowParamList != "") {
            const arrParamParts = arrowParamList.split(",")
            for (apId in arrParamParts) {
                const aPid = parseInt(apId)
                if (aPid <= 0) { continue }
                if (nGetKind(aPid) != "PARAM") { continue }
                const aPtype = nGetS2(aPid)
                if (aPtype != "") { hasAnyAnnotated = 1 }
                if (arrowParamTypes == "") { arrowParamTypes = aPtype } else { arrowParamTypes = `${arrowParamTypes},${aPtype}` }
            }
        }
        if (hasAnyAnnotated == 0) {
            if (expectedType == "" || (expectedType != "fn" && expectedType.startsWith("fn(") == 0)) {
                return "fn"
            }
            // 结构化 fn(P,...):R 时反填 PARAM children s2 + ARROW_FUNC retT s2(D141 inferArrowFuncParams 同模式)
            if (expectedType.startsWith("fn(") == 1 && arrowParamList != "") {
                const arrParamPartsBack = arrowParamList.split(",")
                let backPi = 0
                for (apIdBack in arrParamPartsBack) {
                    const aPidBack = parseInt(apIdBack)
                    if (aPidBack > 0 && nGetKind(aPidBack) == "PARAM" && nGetS2(aPidBack) == "") {
                        const inferredParam = extractFnParamType(expectedType, backPi)
                        if (inferredParam != "") {
                            nSetS2(aPidBack, inferredParam)
                        }
                        backPi = backPi + 1
                    }
                }
                if (nGetS2(nodeId) == "") {
                    const inferredRet = extractFnRetType(expectedType)
                    if (inferredRet != "") {
                        nSetS2(nodeId, inferredRet)
                    }
                }
            }
            return expectedType
        }
        let arrowRetT = nGetS2(nodeId)
        if (arrowRetT == "") { arrowRetT = "void" }
        return `fn(${arrowParamTypes}):${arrowRetT}`
    }
    if (kind == "THIS") { return currentCheckerClass }
    if (kind == "SUPER") {
        if (currentCheckerClass != "" && checkerClassParents.has(currentCheckerClass) == 1) {
            return checkerClassParents.getString(currentCheckerClass)
        }
        return ""
    }
    if (kind == "IDENT") {
        const name = nGetS1(nodeId)
        const vType = lookupVar(name)
        if (vType != "") {
            if (vType != "auto") {
                // D067 Phase 2: check narrowed type from null guards
                const narrowed = getNarrowedType(name)
                if (narrowed != "") { return narrowed }
                return vType
            }
            return ""
        }
        if (lookupFunc(name) == 1) { return "fn" }
        return ""
    }
    if (kind == "NEW_EXPR") { return nGetS1(nodeId) }
    if (kind == "CALL") {
        const callee = nGetS1(nodeId)
        if (funcNames.has(callee) == 1) {
            const retType = funcNames.getString(callee)
            if (retType != "" && retType != "builtin") { return retType }
        }
        return ""
    }
    if (kind == "METHOD_CALL") {
        const mcRecv = inferCheckerClass(nGetI1(nodeId))
        if (mcRecv != "" && classConsMin.has(mcRecv) == 1) {
            const mRetType = lookupMethodRetType(mcRecv, nGetS1(nodeId))
            if (nGetI3(nodeId) > 0) { return makeNullable(mRetType) }
            return mRetType
        }
        return ""
    }
    if (kind == "MEMBER_ACCESS") {
        const ciObjNode = nGetI1(nodeId)
        // D078: ClassName.staticField → resolve via class name directly
        if (nGetKind(ciObjNode) == "IDENT" && lookupVar(nGetS1(ciObjNode)) == "class") {
            const sfFieldKey = `${nGetS1(ciObjNode)}.${nGetS1(nodeId)}`
            if (checkerFieldTypes.has(sfFieldKey) == 1) {
                return checkerFieldTypes.getString(sfFieldKey)
            }
        }
        const objClass = inferCheckerClass(ciObjNode)
        if (objClass != "") {
            const fieldKey = `${objClass}.${nGetS1(nodeId)}`
            if (checkerFieldTypes.has(fieldKey) == 1) {
                const fType = checkerFieldTypes.getString(fieldKey)
                if (nGetI3(nodeId) > 0) { return makeNullable(fType) }
                return fType
            }
        }
        return ""
    }
    if (kind == "INDEX_ACCESS") {
        const arrType = checkerInferType(nGetI1(nodeId), "")
        if (arrType != "") {
            const base = baseTypeName(arrType)
            if (base == "Array" || base == "List" || base == "Tuple") {
                const elemType = extractElemType(arrType)
                if (elemType != "") { return elemType }
            }
        }
        return ""
    }
    if (kind == "BINARY") {
        const op = nGetS1(nodeId)
        // ?? (null coalescing): result is non-nullable (D067)
        if (op == "NullCoalesce") {
            const ncLeft = checkerInferType(nGetI1(nodeId), "")
            if (isNullableType(ncLeft) == 1) { return stripNullable(ncLeft) }
            const ncRight = checkerInferType(nGetI2(nodeId), "")
            if (ncLeft != "" && ncLeft != "null") { return ncLeft }
            if (ncRight != "") { return ncRight }
            return ""
        }
        if (op == "As") {
            return nGetS1(nGetI2(nodeId))
        }
        if (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge" || op == "And" || op == "Or" || op == "Instanceof") {
            return "int"
        }
        const blt = checkerInferType(nGetI1(nodeId), "")
        const brt = checkerInferType(nGetI2(nodeId), "")
        if (op == "Add" && (blt == "string" || brt == "string")) { return "string" }
        if (blt == "double" || brt == "double") { return "double" }
        if (blt == "int") { return "int" }
        if (brt == "int") { return "int" }
        return ""
    }
    if (kind == "UNARY") { return checkerInferType(nGetI1(nodeId), expectedType) }
    if (kind == "GROUPING") { return checkerInferType(nGetI1(nodeId), expectedType) }
    if (kind == "TERNARY") {
        const ternStored = nGetS2(nodeId)
        if (ternStored != "") { return ternStored }
        if (expectedType != "" && expectedType != "auto") {
            propagateTernaryBranchType(nodeId, expectedType)
            return expectedType
        }
        return checkerInferType(nGetI2(nodeId), expectedType)
    }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { return "int" }
    if (kind == "NAMED_ARG") { return checkerInferType(nGetI1(nodeId), expectedType) }
    // SPREAD_ELEM inner expr 是数组(不是 elem),不透传 outer expectedType — elem vs array 维度差
    if (kind == "SPREAD_ELEM") { return checkerInferType(nGetI1(nodeId), "") }
    return ""
}

function baseTypeName(t: string): string {
    const raw = stripNullable(t)
    const ltIdx = raw.indexOf("<")
    if (ltIdx > 0) { return raw.substring(0, ltIdx) }
    return raw
}

function extractElemType(t: string): string {
    const raw = stripNullable(t)
    const ltIdx = raw.indexOf("<")
    if (ltIdx < 0) { return "" }
    return raw.substring(ltIdx + 1, raw.length() - ltIdx - 2)
}

function isTypeCompatible(declared: string, actual: string): int {
    if (declared == "" || actual == "") { return 1 }
    if (declared == "auto" || actual == "auto") { return 1 }
    if (declared == actual) { return 1 }
    // Null safety (D067)
    const declNullable = isNullableType(declared)
    const actualNullable = isNullableType(actual)
    if (actual == "null") {
        if (declNullable == 1) { return 1 }
        return 0
    }
    if (actualNullable == 1 && declNullable == 0) { return 0 }
    if (declNullable == 1) {
        return isTypeCompatible(stripNullable(declared), stripNullable(actual))
    }
    if (declared == "double" && actual == "int") { return 1 }
    // bool is int in SS
    if ((declared == "bool" && actual == "int") || (declared == "int" && actual == "bool")) { return 1 }
    // D141 Phase 3 — fn 类型双向兼容:codegen 阶段反推回填 PARAM s2 + 失败硬错(H4/H13);
    // checker 阶段对 untyped ARROW_FUNC actual="fn" + structured expected="fn(...):R" 放行,
    // 反向(typed actual + 老 setter: fn expected)亦兼容 H12 既有 callee。
    const declFn = declared == "fn" || declared.startsWith("fn(") == 1
    const actualFn = actual == "fn" || actual.startsWith("fn(") == 1
    if (declFn == 1 && actualFn == 1) { return 1 }
    if (ifaceMethods.has(declared) == 1) { return 1 }
    // Generic type parameters: T is compatible with any concrete type
    if (currentTypeParams != "") {
        const tpParts = currentTypeParams.split(",")
        for (tp in tpParts) {
            if (declared == tp || actual == tp) { return 1 }
        }
    }
    // Class inheritance: actual is subclass of declared
    let parent = ""
    if (checkerClassParents.has(actual) == 1) {
        parent = checkerClassParents.getString(actual)
    }
    while (parent != "") {
        if (parent == declared) { return 1 }
        if (checkerClassParents.has(parent) == 1) {
            parent = checkerClassParents.getString(parent)
        } else {
            parent = ""
        }
    }
    // Generic types: compare base type (Array<int> compat with Array — imprecise but safe)
    const declBase = baseTypeName(declared)
    const actualBase = baseTypeName(actual)
    if (declBase != declared || actualBase != actual) {
        if (declBase == actualBase) { return 1 }
    }
    // List/Tuple are aliases for Array
    if ((declBase == "Array" || declBase == "List" || declBase == "Tuple") && (actualBase == "Array" || actualBase == "List" || actualBase == "Tuple")) { return 1 }
    return 0
}

// ── Method overload signature (D138 Phase 1.5) ──────────────
// Mirror gen_types.ss:979 typeSig + paramSig 公约 — interface method overload by arity 时
// checker 注册 mangled methodNames(`${mName}_${paramSig}`)与 codegen ifaceMethodsCG entry 同公约,
// check_class.ss checkInterfaceImpl contains 比对自动跟着;否则 plain mName backward compat。
function typeSigChecker(ssType: string): string {
    const st = stripNullable(ssType)
    if (st == "int" || st == "bool" || st == "auto" || st == "") { return "i" }
    if (st == "double") { return "d" }
    if (st == "string") { return "s" }
    if (st == "fn" || st.startsWith("fn(") == 1) { return "f" }
    if (st == "void") { return "v" }
    if (st.contains("<") == 1) { return "p" }
    return st
}

function paramSigChecker(paramList: string): string {
    if (paramList == "") { return "" }
    let sig = ""
    const parts = paramList.split(",")
    for (p in parts) {
        const pId = parseInt(p)
        if (pId > 0 && nGetKind(pId) == "PARAM") {
            if (sig != "") { sig = `${sig}_` }
            sig = `${sig}${typeSigChecker(nGetS2(pId))}`
        }
    }
    return sig
}

// D138 Phase 1.5: 收敛三处双 pass — INTERFACE_DECL methods(fdOnly=0)+ CLASS_DECL FUNC_DECL
// methods(fdOnly=1)。Pass 1 计数 mName 出现次数,Pass 2 对 overload(>=2)加 paramSig suffix
// 落 mangled csv;单 arity plain backward compat。返回 csv(无前后 `,`),调用方按需包装。
function mangleMethodList(ml: string, fdOnly: int): string {
    if (ml == "") { return "" }
    const ms = ml.split(",")
    let cnt = new Map()
    for (m in ms) {
        const mId = parseInt(m)
        if (mId > 0 && (fdOnly == 0 || nGetKind(mId) == "FUNC_DECL")) {
            const mName = nGetS1(mId)
            const cur = cnt.has(mName) == 1 ? parseInt(cnt.getString(mName)) : 0
            cnt.set(mName, `${cur + 1}`)
        }
    }
    let out = ""
    for (m in ms) {
        const mId = parseInt(m)
        if (mId > 0 && (fdOnly == 0 || nGetKind(mId) == "FUNC_DECL")) {
            const mName = nGetS1(mId)
            const isOverload = parseInt(cnt.getString(mName)) >= 2 ? 1 : 0
            const pSig = isOverload == 1 ? paramSigChecker(nGetList(mId)) : ""
            const mangledKey = pSig != "" ? `${mName}_${pSig}` : mName
            out = listAppendStr(out, mangledKey)
        }
    }
    return out
}
