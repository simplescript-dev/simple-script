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

    emitIR(`define ${llRetType} @${llMethodName}(${paramStr}) {`)
    emitIR("entry:")

    // Alloca this (skip for static methods)
    if (isStatic == 0) {
        emitIR("  %this = alloca ptr, align 8")
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
    currentClassName = ""
}

// Generate constructor args in field order from NAMED_ARG nodes
function genNamedConstructorArgs(className: string, argList: string): string {
    // Evaluate all named arg expressions and store values by name
    let namedVals = Map()
    let namedLLTypes = Map()
    const parts = argList.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0 && nGetKind(argId) == "NAMED_ARG") {
            const argName = nGetS1(argId)
            const valId = nGetI1(argId)
            const val = genExpr(valId)
            const vType = inferType(valId)
            namedVals.set(argName, val)
            namedLLTypes.set(argName, ssTypeToLLVM(vType))
        }
    }
    // Build args string in field declaration order
    const fieldStr = classFields.getString(className)
    let result = ""
    if (fieldStr != "") {
        const fields = fieldStr.split(",")
        let first = 1
        for (f in fields) {
            if (first == 1) { first = 0 } else { result = result + ", " }
            const val = namedVals.getString(f)
            const llType = namedLLTypes.getString(f)
            result = `${result}${llType} ${val}`
        }
    }
    return result
}
