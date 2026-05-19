// gen/class_method.ss — 类方法 IR 生成 + 类型参约束检查 + 命名构造参排序

// ── Constraint validation ─────────────────────────────────────

function checkConstraint(concreteType: string, constraint: string, tp: string, ownerKind: string, ownerName: string) {
    const cParts = constraint.split("&")
    for (c in cParts) {
        let found = 0
        if (ifaceImplementors.has(c) == 1) {
            const implParts = ifaceImplementors.getString(c).split(",")
            for (impl in implParts) {
                if (impl == concreteType) { found = 1; break }
            }
        }
        if (found == 0) {
            println(`error: type '${concreteType}' does not satisfy constraint '${c}' for type parameter '${tp}' in ${ownerKind} '${ownerName}'`)
            exit(1)
        }
    }
}

function genClassMethod(className: string, id: int) {
    // D071: skip abstract methods (no body to generate)
    if (nGetI4(id) == 1) { return }
    const mName = funcName(id)
    let retType = resolveTypeParam(funcRetType(id))
    if (retType == "") { retType = "void" }
    const llRetType = ssTypeToLLVM(retType)
    const isStatic = nGetI2(id) == 1 ? 1 : 0

    // Build param list: static methods skip 'this'
    let paramStr = ""
    if (isStatic == 0) { paramStr = "ptr %this.ptr" }
    const paramList = funcParams(id)
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                const pName = nGetS1(pId)
                const pType = resolveTypeParam(nGetS2(pId))
                const llType = ssTypeToLLVM(pType)
                if (paramStr != "") { paramStr = `${paramStr}, ` }
                paramStr = `${paramStr}${llType} %${pName}.arg`
            }
        }
    }
    // I018 §路径 A — 形参数在 pre-register 阶段由 registerClassMethodRetType
    // (gen/gen_registry.ss) 写入 funcParamCount;此处 emit 时机过晚,不重复注册。

    // Mangled name: accessors get `get_`/`set_` prefix (D096); overloaded
    // regular methods get a param-signature suffix; otherwise plain `Class_method`.
    const mKind = nGetI2(id)
    let llMethodName = ""
    if (mKind == 2) {
        llMethodName = `${className}_get_${mName}`
    } else if (mKind == 3) {
        llMethodName = `${className}_set_${mName}`
    } else {
        llMethodName = `${className}_${mName}`
        if (isOverloaded(`${className}_${mName}`) == 1) {
            const mSig = paramSig(paramList)
            if (mSig != "") { llMethodName = `${className}_${mName}_${mSig}` }
        }
    }

    regCount = 0
    regTable = []
    terminated = 0
    currentFunc = llMethodName
    currentClassName = className
    varAliases = Map()
    localPtrVars = ""
    rcBlockDepth = 0

    // SS-LIM-4: enter function-emit window
    startFuncEmit()
    emitIR(`define ${llRetType} @${llMethodName}(${paramStr}) {`)
    emitIR("entry:")
    markEntryAllocaPoint()

    // Alloca this (skip for static methods)
    if (isStatic == 0) {
        emitEntryAlloca("%this", "ptr", 8)
        emitIR("  store ptr %this.ptr, ptr %this, align 8")
        setVarType("this", className)
    }

    emitParamAllocas(paramList, 0)

    // Generate body
    const bodyId = funcBody(id)
    genBlock(bodyId)

    // Default return
    if (terminated == 0) {
        emitReleaseFnLocals()
        emitReleaseLocals()
        if (llRetType == "void") {
            emitIR("  ret void")
        } else if (llRetType == "ptr") {
            const ns = addStringConst("")
            emitIR(`  ret ptr ${ns}`)
        } else {
            emitIR(`  ret ${llRetType} 0`)
        }
    }
    emitIR("}")
    emitIR("")
    const methodIR = endFuncEmit()
    if (irOutFile != "") {
        appendFile(irOutFile, methodIR)
    } else {
        irBuf = `${irBuf}${methodIR}`
    }
    currentClassName = ""
}

// D149: default value expr id (PARAM I1 slot); 0 if field has no default.
function lookupFieldDefaultId(className: string, fieldName: string): int {
    const owner = findFieldOwner(fieldName, className)
    if (owner == "") { return 0 }
    const key = `${owner}.${fieldName}`
    if (classFieldDefaultIds.has(key) == 0) { return 0 }
    return parseInt(classFieldDefaultIds.getString(key))
}

// D149: field's SS type, walking parent chain.
function lookupFieldType(className: string, fieldName: string): string {
    const owner = findFieldOwner(fieldName, className)
    return owner == "" ? "" : classFieldTypes.getString(`${owner}.${fieldName}`)
}

// D149: C3 helper — unified ctor args builder.
// Walks class fields in declaration order; for each field, prefers named arg value,
// then falls back to field default value expr, then to zero (LLVM type-correct).
// Used by both partial named arg path (genNamedConstructorArgs) and 全 default 空 ctor path.
function genCtorArgsWithDefaults(className: string, namedVals: Map, namedLLTypes: Map): string {
    const fieldStr = classFields.getString(className)
    let result = ""
    if (fieldStr == "") { return result }
    const fields = fieldStr.split(",")
    let first = 1
    for (f in fields) {
        if (first == 1) { first = 0 } else { result = result + ", " }
        if (namedVals.has(f) == 1) {
            const val = namedVals.getString(f)
            const llType = namedLLTypes.getString(f)
            result = `${result}${llType} ${val}`
        } else {
            const defId = lookupFieldDefaultId(className, f)
            if (defId > 0) {
                const defVal = genExpr(defId)
                const defType = inferType(defId)
                const defLLType = ssTypeToLLVM(defType)
                result = `${result}${defLLType} ${defVal}`
            } else {
                const fType = lookupFieldType(className, f)
                const llType = ssTypeToLLVM(fType)
                if (llType == "ptr") { result = result + "ptr null" }
                else if (llType == "double") { result = result + "double 0.0" }
                else { result = `${result}${llType} 0` }
            }
        }
    }
    return result
}

// Generate constructor args in field order from NAMED_ARG nodes.
// D149: missing fields fall through to default value expr via genCtorArgsWithDefaults.
function genNamedConstructorArgs(className: string, argList: string): string {
    let namedVals = Map()
    let namedLLTypes = Map()
    const parts = argList.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0 && nGetKind(argId) == "NAMED_ARG") {
            const argName = nGetS1(argId)
            const valId = nGetI1(argId)
            // D148 Phase 5: NAMED_ARG OBJ_LITERAL 反推删 — checker 已通过
            // check_named_args.ss:70 checkerInferType(nGetI1, naExpType) 写 nSetS2,
            // 与 eval/new_expr.ss line 24-49 删的 NAMED_ARG 反推循环对偶。
            const val = genExpr(valId)
            const vType = inferType(valId)
            namedVals.set(argName, val)
            namedLLTypes.set(argName, ssTypeToLLVM(vType))
        }
    }
    return genCtorArgsWithDefaults(className, namedVals, namedLLTypes)
}

// I030: single arity-safe builder for a constructor call's argument string,
// shared by genNewExpr and genGenericNewExpr. Named args delegate to
// genNamedConstructorArgs; positional args map index→field and (like empty
// construction) route through genCtorArgsWithDefaults, which pads every
// un-provided field to a type-correct zero/default. Emitting only the provided
// args would yield `call @X_new` short of the constructor's declared field
// arity, leaving un-provided fields reading uninitialized ABI registers.
function genCtorCallArgs(className: string, argList: string): string {
    let hasNamed = 0
    if (argList != "") {
        const ci = argList.indexOf(",")
        const firstArgId = parseInt(ci >= 0 ? argList.substring(0, ci) : argList)
        if (firstArgId > 0 && nGetKind(firstArgId) == "NAMED_ARG") { hasNamed = 1 }
    }
    if (hasNamed == 1) {
        return genNamedConstructorArgs(className, argList)
    }
    let posVals = Map()
    let posLLTypes = Map()
    if (argList != "") {
        const parts = argList.split(",")
        const posFields = classFields.getString(className).split(",")
        let posIdx = 0
        for (p in parts) {
            const argId = parseInt(p)
            if (argId > 0) {
                const val = genExpr(argId)
                const vType = inferType(argId)
                const fname = posFields[posIdx]
                posVals.set(fname, val)
                posLLTypes.set(fname, ssTypeToLLVM(vType))
                posIdx = posIdx + 1
            }
        }
    }
    return genCtorArgsWithDefaults(className, posVals, posLLTypes)
}
