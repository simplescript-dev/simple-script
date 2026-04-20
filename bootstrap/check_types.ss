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

function checkerInferType(nodeId: int): string {
    if (nodeId <= 0) { return "" }
    const kind = nGetKind(nodeId)
    if (kind == "INT_LIT") { return "int" }
    if (kind == "DOUBLE_LIT") { return "double" }
    if (kind == "STRING_LIT" || kind == "TEMPLATE_LIT") { return "string" }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT") { return "int" }
    if (kind == "NULL_LIT") { return "null" }
    if (kind == "ARRAY_LIT") { return "Array" }
    if (kind == "ARROW_FUNC") { return "fn" }
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
        const arrType = checkerInferType(nGetI1(nodeId))
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
            const ncLeft = checkerInferType(nGetI1(nodeId))
            if (isNullableType(ncLeft) == 1) { return stripNullable(ncLeft) }
            const ncRight = checkerInferType(nGetI2(nodeId))
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
        const blt = checkerInferType(nGetI1(nodeId))
        const brt = checkerInferType(nGetI2(nodeId))
        if (op == "Add" && (blt == "string" || brt == "string")) { return "string" }
        if (blt == "double" || brt == "double") { return "double" }
        if (blt == "int") { return "int" }
        if (brt == "int") { return "int" }
        return ""
    }
    if (kind == "UNARY") { return checkerInferType(nGetI1(nodeId)) }
    if (kind == "GROUPING") { return checkerInferType(nGetI1(nodeId)) }
    if (kind == "TERNARY") { return checkerInferType(nGetI2(nodeId)) }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { return "int" }
    if (kind == "NAMED_ARG") { return checkerInferType(nGetI1(nodeId)) }
    if (kind == "SPREAD_ELEM") { return checkerInferType(nGetI1(nodeId)) }
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
