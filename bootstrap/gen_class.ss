// Class codegen for bootstrap compiler
// ── Class support ─────────────────────────────────────────────

function registerClass(id: int) {
    const name = nGetS1(id)
    const extendsName = nGetS2(id)
    if (extendsName != "") {
        classParents.set(name, extendsName)
    }
    const paramList = nGetList(id)
    // Collect field names and types
    let fieldNames = ""
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                const fName = nGetS1(pId)
                const fType = nGetS2(pId)
                if (fieldNames == "") { fieldNames = fName } else { fieldNames = `${fieldNames},${fName}` }
                classFieldTypes.set(`${name}.${fName}`, fType)
            }
        }
    }
    // Prepend parent fields if extends
    if (extendsName != "" && classFields.has(extendsName) == 1) {
        const parentFields = classFields.getString(extendsName)
        if (parentFields != "") {
            if (fieldNames == "") {
                fieldNames = parentFields
            } else {
                fieldNames = `${parentFields},${fieldNames}`
            }
            // Copy parent field types
            const pfs = parentFields.split(",")
            for (pf in pfs) {
                if (classFieldTypes.has(`${extendsName}.${pf}`) == 1) {
                    classFieldTypes.set(`${name}.${pf}`, classFieldTypes.getString(`${extendsName}.${pf}`))
                }
            }
        }
    }
    classFields.set(name, fieldNames)
    // Collect method names
    const methodsBlockId = nGetI2(id)
    let methodNames = ""
    if (methodsBlockId > 0) {
        const mList = nGetList(methodsBlockId)
        if (mList != "") {
            const mParts = mList.split(",")
            for (mp in mParts) {
                const mId = parseInt(mp)
                if (mId > 0 && nGetKind(mId) == "FUNC_DECL") {
                    const mName = nGetS1(mId)
                    if (methodNames == "") { methodNames = mName } else { methodNames = `${methodNames},${mName}` }
                    // Register return type
                    let mRet = nGetS2(mId)
                    if (mRet == "") { mRet = "void" }
                    funcRetTypes.set(`${name}_${mName}`, mRet)
                }
            }
        }
    }
    classMethods.set(name, methodNames)
}

function genClassDecl(id: int) {
    const name = nGetS1(id)
    const fieldStr = classFields.getString(name)

    // Emit LLVM struct type
    let fieldTypes = ""
    if (fieldStr != "") {
        const parts = fieldStr.split(",")
        let first = 1
        for (p in parts) {
            const ft = classFieldTypes.getString(`${name}.${p}`)
            const llType = ssTypeToLLVM(ft)
            if (first == 1) { first = 0 } else { fieldTypes = fieldTypes + ", " }
            fieldTypes = fieldTypes + llType
        }
    }
    emitIR(`%${name} = type { ${fieldTypes} }`)
    emitIR("")

    // Emit constructor: @ClassName_new(fields...) -> ptr
    let ctorParams = ""
    let ctorIdx = 0
    if (fieldStr != "") {
        const parts = fieldStr.split(",")
        for (p in parts) {
            const ft = classFieldTypes.getString(`${name}.${p}`)
            const llType = ssTypeToLLVM(ft)
            if (ctorIdx > 0) { ctorParams = ctorParams + ", " }
            ctorParams = `${ctorParams}${llType} %${p}.arg`
            ctorIdx = ctorIdx + 1
        }
    }
    regCount = 0
    emitIR(`define ptr @${name}_new(${ctorParams}) {`)
    emitIR("entry:")
    // Calculate struct size (simplified: 8 bytes per field)
    const structSize = ctorIdx * 8
    const mallocReg = nextReg()
    emitIR(`  ${mallocReg} = call ptr @malloc(i64 ${structSize})`)
    // Store fields
    if (fieldStr != "") {
        let idx = 0
        const parts = fieldStr.split(",")
        for (p in parts) {
            const ft = classFieldTypes.getString(`${name}.${p}`)
            const llType = ssTypeToLLVM(ft)
            const gepReg = nextReg()
            emitIR(`  ${gepReg} = getelementptr %${name}, ptr ${mallocReg}, i32 0, i32 ${idx}`)
            emitIR(`  store ${llType} %${p}.arg, ptr ${gepReg}, align 8`)
            idx = idx + 1
        }
    }
    emitIR(`  ret ptr ${mallocReg}`)
    emitIR("}")
    emitIR("")

    // Emit methods: @ClassName_methodName(ptr %this, args...) -> retType
    const methodsBlockId = nGetI2(id)
    if (methodsBlockId > 0) {
        const mList = nGetList(methodsBlockId)
        if (mList != "") {
            const mParts = mList.split(",")
            for (mp in mParts) {
                const mId = parseInt(mp)
                if (mId > 0 && nGetKind(mId) == "FUNC_DECL") {
                    genClassMethod(name, mId)
                }
            }
        }
    }
}

function genClassMethod(className: string, id: int) {
    const mName = nGetS1(id)
    let retType = nGetS2(id)
    if (retType == "") { retType = "void" }
    const llRetType = ssTypeToLLVM(retType)

    // Build param list (this + declared params)
    let paramStr = "ptr %this.ptr"
    const paramList = nGetList(id)
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                const pName = nGetS1(pId)
                const pType = nGetS2(pId)
                const llType = ssTypeToLLVM(pType)
                paramStr = `${paramStr}, ${llType} %${pName}.arg`
            }
        }
    }

    regCount = 0
    terminated = 0
    currentFunc = `${className}_${mName}`
    currentClassName = className
    varAliases = Map()

    emitIR(`define ${llRetType} @${className}_${mName}(${paramStr}) {`)
    emitIR("entry:")

    // Alloca this
    emitIR("  %this = alloca ptr, align 8")
    emitIR("  store ptr %this.ptr, ptr %this, align 8")
    setVarType("this", className)

    // Alloca params
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                const pName = nGetS1(pId)
                const pType = nGetS2(pId)
                const llType = ssTypeToLLVM(pType)
                emitIR(`  %${pName} = alloca ${llType}, align 8`)
                emitIR(`  store ${llType} %${pName}.arg, ptr %${pName}, align 8`)
                setVarType(pName, pType)
                if (classFields.has(pType) == 1) {
                    setObjClass(pName, pType)
                }
            }
        }
    }

    // Generate body
    const bodyId = nGetI1(id)
    genBlock(bodyId)

    // Default return
    if (terminated == 0) {
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

function genNewExpr(id: int): string {
    const className = nGetS1(id)
    const argList = nGetList(id)
    let args = ""
    if (argList != "") {
        const parts = argList.split(",")
        let first = 1
        for (p in parts) {
            const argId = parseInt(p)
            if (argId > 0) {
                const val = genExpr(argId)
                const vType = inferType(argId)
                const llType = ssTypeToLLVM(vType)
                if (first == 1) { first = 0 } else { args = args + ", " }
                args = `${args}${llType} ${val}`
            }
        }
    }
    const r = nextReg()
    emitIR(`  ${r} = call ptr @${className}_new(${args})`)
    return r
}

function emitFieldLoad(className: string, objReg: string, field: string): string {
    const idx = getFieldIndex(className, field)
    if (idx < 0) { return objReg }
    const fType = classFieldTypes.getString(`${className}.${field}`)
    const gepReg = nextReg()
    emitIR(`  ${gepReg} = getelementptr %${className}, ptr ${objReg}, i32 0, i32 ${idx}`)
    const loadReg = nextReg()
    emitIR(`  ${loadReg} = load ${ssTypeToLLVM(fType)}, ptr ${gepReg}, align 8`)
    return loadReg
}

function genMemberAccess(id: int): string {
    const member = nGetS1(id)
    const objId = nGetI1(id)
    const objKind = nGetKind(objId)
    // Enum value access: EnumName.Variant → integer constant
    if (objKind == "IDENT" && enumReady == 1) {
        const enumKey = `${nGetS1(objId)}.${member}`
        if (enumValues.has(enumKey) == 1) {
            return enumValues.getString(enumKey)
        }
    }
    if (objKind == "THIS") {
        const thisReg = nextReg()
        emitIR(`  ${thisReg} = load ptr, ptr %this, align 8`)
        return emitFieldLoad(currentClassName, thisReg, member)
    }
    const objVal = genExpr(objId)
    if (objKind == "IDENT") {
        const cn = getObjClass(nGetS1(objId))
        if (cn != "") { return emitFieldLoad(cn, objVal, member) }
    }
    return objVal
}

function setObjClass(varName: string, className: string) {
    objClasses.set(`${currentFunc}.${varName}`, className)
}

function getObjClass(varName: string): string {
    const localKey = `${currentFunc}.${varName}`
    if (objClasses.has(localKey) == 1) {
        return objClasses.getString(localKey)
    }
    const globalKey = `.${varName}`
    if (objClasses.has(globalKey) == 1) {
        return objClasses.getString(globalKey)
    }
    return ""
}

function getFieldIndex(className: string, fieldName: string): int {
    const fieldStr = classFields.getString(className)
    if (fieldStr == "") { return -1 }
    const parts = fieldStr.split(",")
    let idx = 0
    for (p in parts) {
        if (p == fieldName) { return idx }
        idx = idx + 1
    }
    return -1
}
