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
                    // Mangled name for overloading
                    const mSig = paramSig(nGetList(mId))
                    if (mSig != "") {
                        funcRetTypes.set(`${name}_${mName}_${mSig}`, mRet)
                    }
                    // Track overload count
                    if (overloadReady == 0) { overloadCount = new Map(); overloadReady = 1 }
                    const mFullName = `${name}_${mName}`
                    if (overloadCount.has(mFullName) == 1) {
                        const mc = parseInt(overloadCount.getString(mFullName))
                        overloadCount.set(mFullName, `${mc + 1}`)
                    } else {
                        overloadCount.set(mFullName, "1")
                    }
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

    // Auto-generate toJson() for all classes
    genAutoToJson(name, fieldStr)
}

function genAutoToJson(className: string, fieldStr: string) {
    if (fieldStr == "") { return }
    funcRetTypes.set(`${className}_toJson`, "string")

    regCount = 0
    emitIR(`define ptr @${className}_toJson(ptr %this.ptr) {`)
    emitIR("entry:")
    emitIR("  %this = alloca ptr, align 8")
    emitIR("  store ptr %this.ptr, ptr %this, align 8")

    // Build JSON string: {"field1":value1,"field2":value2}
    let resultReg = addStringConst("{")
    const fields = fieldStr.split(",")
    let fieldIdx = 0
    for (f in fields) {
        const fType = classFieldTypes.getString(`${className}.${f}`)
        const llFType = ssTypeToLLVM(fType)

        // Add comma separator
        if (fieldIdx > 0) {
            const commaStr = addStringConst(",")
            const cR = nextReg()
            emitIR(`  ${cR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${commaStr})`)
            resultReg = cR
        }

        // Add "fieldName":
        const keyStr = addStringConst(`"${f}":`)
        const kR = nextReg()
        emitIR(`  ${kR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${keyStr})`)
        resultReg = kR

        // Load field value
        const thisR = nextReg()
        emitIR(`  ${thisR} = load ptr, ptr %this, align 8`)
        const gepR = nextReg()
        emitIR(`  ${gepR} = getelementptr %${className}, ptr ${thisR}, i32 0, i32 ${fieldIdx}`)
        const valR = nextReg()
        emitIR(`  ${valR} = load ${llFType}, ptr ${gepR}, align 8`)

        // Convert to string and add
        if (fType == "string") {
            // Wrap in quotes: "value"
            const quoteStr = addStringConst("\"")
            const q1 = nextReg()
            emitIR(`  ${q1} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${quoteStr})`)
            const q2 = nextReg()
            emitIR(`  ${q2} = call ptr @ss_string_concat(ptr ${q1}, ptr ${valR})`)
            const q3 = nextReg()
            emitIR(`  ${q3} = call ptr @ss_string_concat(ptr ${q2}, ptr ${quoteStr})`)
            resultReg = q3
        } else if (fType == "int") {
            const numStr = nextReg()
            emitIR(`  ${numStr} = call ptr @ss_int_to_string(i32 ${valR})`)
            const nR = nextReg()
            emitIR(`  ${nR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${numStr})`)
            resultReg = nR
        } else if (fType == "double") {
            const dblStr = nextReg()
            emitIR(`  ${dblStr} = call ptr @ss_double_to_string(double ${valR})`)
            const dR = nextReg()
            emitIR(`  ${dR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${dblStr})`)
            resultReg = dR
        } else if (classFields.has(fType) == 1 && fType.contains("<") == 0) {
            // Nested POJO — call its toJson
            const nestedJson = nextReg()
            emitIR(`  ${nestedJson} = call ptr @${fType}_toJson(ptr ${valR})`)
            const njR = nextReg()
            emitIR(`  ${njR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${nestedJson})`)
            resultReg = njR
        } else {
            // Unknown type (Map, generic, etc.) — output as string representation
            const objStr = addStringConst("\"[object]\"")
            const oR = nextReg()
            emitIR(`  ${oR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${objStr})`)
            resultReg = oR
        }
        fieldIdx = fieldIdx + 1
    }

    // Close with }
    const closeStr = addStringConst("}")
    const finalR = nextReg()
    emitIR(`  ${finalR} = call ptr @ss_string_concat(ptr ${resultReg}, ptr ${closeStr})`)
    emitIR(`  ret ptr ${finalR}`)
    emitIR("}")
    emitIR("")
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

    // Use mangled name if method is overloaded
    let llMethodName = `${className}_${mName}`
    if (isOverloaded(`${className}_${mName}`) == 1) {
        const mSig = paramSig(paramList)
        if (mSig != "") { llMethodName = `${className}_${mName}_${mSig}` }
    }

    regCount = 0
    terminated = 0
    currentFunc = llMethodName
    currentClassName = className
    varAliases = Map()

    emitIR(`define ${llRetType} @${llMethodName}(${paramStr}) {`)
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
    // Map is a built-in class — constructor delegates to ss_mapNew
    if (className == "Map") {
        const r = nextReg()
        emitIR(`  ${r} = call ptr @ss_mapNew()`)
        return r
    }
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
