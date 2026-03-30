// Class codegen for bootstrap compiler
// ── Class support ─────────────────────────────────────────────

function registerClass(id: int) {
    const name = classNodeName(id)
    const extendsName = classParentName(id)
    if (extendsName != "") {
        classParents.set(name, extendsName)
    }
    const paramList = classFieldList(id)
    // Collect field names and types
    let fieldNames = ""
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                const fName = paramName(pId)
                const fType = paramType(pId)
                if (fieldNames == "") { fieldNames = fName } else { fieldNames = `${fieldNames},${fName}` }
                classFieldTypes.set(`${name}.${fName}`, fType)
            }
        }
    }
    // Store own fields only; inheritance resolved in resolveInheritance()
    classFields.set(name, fieldNames)
    // Collect method names
    const methodsBlockId = classMethodsBlock(id)
    let methodNames = ""
    if (methodsBlockId > 0) {
        const mList = nGetList(methodsBlockId)
        if (mList != "") {
            const mParts = mList.split(",")
            for (mp in mParts) {
                const mId = parseInt(mp)
                if (mId > 0 && nGetKind(mId) == "FUNC_DECL") {
                    const mName = funcName(mId)
                    if (methodNames == "") { methodNames = mName } else { methodNames = `${methodNames},${mName}` }
                    let mRet = funcRetType(mId)
                    if (mRet == "") { mRet = "void" }
                    funcRetTypes.set(`${name}_${mName}`, mRet)
                    const mSig = paramSig(funcParams(mId))
                    if (mSig != "") {
                        funcRetTypes.set(`${name}_${mName}_${mSig}`, mRet)
                    }
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

// Resolve inheritance after ALL classes are registered.
// Walks parent chain to prepend parent fields and copy field types.
function resolveInheritance() {
    const allClasses = classFields.keys()
    if (allClasses == "") { return }
    // Map.keys() returns newline-separated string
    const classList = allClasses.split("\n")
    for (cls in classList) {
        if (cls == "") { continue }
        const parent = classParents.has(cls) == 1 ? classParents.getString(cls) : ""
        if (parent == "") { continue }
        if (classFields.has(parent) == 0) {
            println(`codegen error: class '${cls}' extends unknown class '${parent}'`)
            exit(1)
        }
        // Walk parent chain to get full parent fields (handles grandparent etc.)
        let fullParentFields = resolveFullFields(parent)
        const ownFields = classFields.getString(cls)
        if (fullParentFields != "") {
            if (ownFields == "") {
                classFields.set(cls, fullParentFields)
            } else {
                classFields.set(cls, `${fullParentFields},${ownFields}`)
            }
            // Copy parent field types to child
            const pfs = fullParentFields.split(",")
            for (pf in pfs) {
                const parentCls = findFieldOwner(pf, parent)
                if (parentCls != "" && classFieldTypes.has(`${parentCls}.${pf}`) == 1) {
                    classFieldTypes.set(`${cls}.${pf}`, classFieldTypes.getString(`${parentCls}.${pf}`))
                }
            }
        }
    }
}

// Get the complete field list for a class (own + all ancestors)
function resolveFullFields(cls: string): string {
    const parent = classParents.has(cls) == 1 ? classParents.getString(cls) : ""
    const ownFields = classFields.getString(cls)
    if (parent == "" || classFields.has(parent) == 0) { return ownFields }
    const parentFields = resolveFullFields(parent)
    if (parentFields == "") { return ownFields }
    if (ownFields == "") { return parentFields }
    return `${parentFields},${ownFields}`
}

// ── Class dtor tags ──────────────────────────────────────────
// Assign unique tags (>= 10) to classes with ptr fields for destructor dispatch.
// Called after resolveInheritance() so inherited fields are known.

function assignClassDtorTags() {
    const allClasses = classFields.keys()
    if (allClasses == "") { return }
    const cList = allClasses.split("\n")
    for (c in cList) {
        if (c == "" || c == "Map") { continue }
        const fieldStr = classFields.getString(c)
        if (fieldStr == "") { continue }
        // Check if any field (own or inherited) has ptr type
        let hasPtrField = 0
        const fields = fieldStr.split(",")
        for (f in fields) {
            if (f == "") { continue }
            const owner = findFieldOwner(f, c)
            if (owner == "") { continue }
            const fType = classFieldTypes.getString(`${owner}.${f}`)
            if (fType == "") { continue }
            const llType = ssTypeToLLVM(fType)
            if (llType == "ptr") { hasPtrField = 1 }
        }
        if (hasPtrField == 1) {
            classDtorTags.set(c, `${dtorNextTag}`)
            dtorNextTag = dtorNextTag + 1
        }
    }
}

// ── Vtable ────────────────────────────────────────────────────
// Build vtable metadata for classes in inheritance hierarchies.
// Called after resolveInheritance() so parent chains are complete.

function buildClassVtables() {
    const allClasses = classFields.keys()
    if (allClasses == "") { return }
    const classList = allClasses.split("\n")
    // Mark all classes that are part of an inheritance hierarchy
    for (cls in classList) {
        if (cls == "") { continue }
        if (classParents.has(cls) == 1) {
            classNeedsVtable.set(cls, "1")
            classNeedsVtable.set(classParents.getString(cls), "1")
        }
    }
    // Build vtable for each marked class (recursion ensures parents built first)
    for (cls in classList) {
        if (cls == "") { continue }
        if (classNeedsVtable.has(cls) == 0) { continue }
        buildVtableForClass(cls)
    }
}

function buildVtableForClass(cls: string) {
    // Already built?
    if (classVtableSlots.has(cls) == 1) { return }
    const parent = classParents.has(cls) == 1 ? classParents.getString(cls) : ""
    // Build parent first (recursion)
    if (parent != "" && classNeedsVtable.has(parent) == 1) {
        buildVtableForClass(parent)
    }
    let slots = ""
    // Inherit parent slot ordering + implementations
    if (parent != "" && classVtableSlots.has(parent) == 1) {
        slots = classVtableSlots.getString(parent)
        const parentSlots = slots.split(",")
        for (ps in parentSlots) {
            if (ps == "") { continue }
            const parentImpl = classVtableImpl.getString(`${parent}.${ps}`)
            classVtableImpl.set(`${cls}.${ps}`, parentImpl)
        }
    }
    // Collect own methods + toJson
    let allMethods = classMethods.getString(cls)
    const fieldStr = classFields.getString(cls)
    if (fieldStr != "") {
        if (allMethods == "") { allMethods = "toJson" }
        else if (allMethods.contains("toJson") == 0) { allMethods = `${allMethods},toJson` }
    }
    if (allMethods != "") {
        const methods = allMethods.split(",")
        for (m in methods) {
            if (m == "") { continue }
            // Check if already in slots
            let found = 0
            if (slots != "") {
                const existing = slots.split(",")
                for (es in existing) {
                    if (es == m) { found = 1 }
                }
            }
            if (found == 0) {
                if (slots == "") { slots = m } else { slots = `${slots},${m}` }
            }
            // Set implementation for this class
            classVtableImpl.set(`${cls}.${m}`, `${cls}_${m}`)
        }
    }
    classVtableSlots.set(cls, slots)
}

// ── Class codegen helpers ────────────────────────────────────

function emitClassStruct(name: string, fieldStr: string, hasVtable: int) {
    let fieldTypes = ""
    if (hasVtable == 1) { fieldTypes = "ptr" }
    if (fieldStr != "") {
        const parts = fieldStr.split(",")
        for (p in parts) {
            const ft = classFieldTypes.getString(`${name}.${p}`)
            const llType = ssTypeToLLVM(ft)
            if (fieldTypes != "") { fieldTypes = fieldTypes + ", " }
            fieldTypes = fieldTypes + llType
        }
    }
    emitIR(`%${name} = type { ${fieldTypes} }`)
    emitIR("")
}

function emitClassVtableConst(name: string, hasVtable: int) {
    if (hasVtable == 0 || classVtableSlots.has(name) == 0) { return }
    const vtSlots = classVtableSlots.getString(name)
    if (vtSlots == "") { return }
    const slotParts = vtSlots.split(",")
    let vtEntries = ""
    let vtCount = 0
    for (sp in slotParts) {
        if (sp == "") { continue }
        const impl = classVtableImpl.getString(`${name}.${sp}`)
        if (vtCount > 0) { vtEntries = vtEntries + ", " }
        vtEntries = `${vtEntries}ptr @${impl}`
        vtCount = vtCount + 1
    }
    emitIR(`@${name}_vtable = constant [${vtCount} x ptr] [${vtEntries}]`)
    emitIR("")
}

function emitClassConstructor(name: string, fieldStr: string, hasVtable: int) {
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
    const sizeGep = nextReg()
    emitIR(`  ${sizeGep} = getelementptr %${name}, ptr null, i32 1`)
    const sizeReg = nextReg()
    emitIR(`  ${sizeReg} = ptrtoint ptr ${sizeGep} to i64`)
    let classTag = 3
    if (classDtorTags.has(name) == 1) {
        classTag = parseInt(classDtorTags.getString(name))
    }
    const mallocReg = nextReg()
    emitIR(`  ${mallocReg} = call ptr @ss_rc_alloc(i64 ${sizeReg}, i32 ${classTag})`)
    if (classTag >= 10) {
        emitIR(`  call void @${name}_dtor_register()`)
    }
    if (hasVtable == 1) {
        const vtGep = nextReg()
        emitIR(`  ${vtGep} = getelementptr %${name}, ptr ${mallocReg}, i32 0, i32 0`)
        emitIR(`  store ptr @${name}_vtable, ptr ${vtGep}, align 8`)
    }
    if (fieldStr != "") {
        let idx = hasVtable == 1 ? 1 : 0
        const parts = fieldStr.split(",")
        for (p in parts) {
            const ft = classFieldTypes.getString(`${name}.${p}`)
            const llType = ssTypeToLLVM(ft)
            const gepReg = nextReg()
            emitIR(`  ${gepReg} = getelementptr %${name}, ptr ${mallocReg}, i32 0, i32 ${idx}`)
            if (llType == "ptr") {
                emitIR(`  call void @ss_rc_retain(ptr %${p}.arg)`)
            }
            emitIR(`  store ${llType} %${p}.arg, ptr ${gepReg}, align 8`)
            idx = idx + 1
        }
    }
    emitIR(`  ret ptr ${mallocReg}`)
    emitIR("}")
    emitIR("")
}

function emitClassDtorRegister(name: string, fieldStr: string, hasVtable: int) {
    if (classDtorTags.has(name) == 0) { return }
    const dtorTag = parseInt(classDtorTags.getString(name))
    emitClassDestroy(name, fieldStr, hasVtable)
    const dtorIdx = dtorTag - 10
    emitIR(`@${name}_dtor_init = internal global i1 false`)
    emitIR(`define internal void @${name}_dtor_register() {`)
    emitIR("entry:")
    emitIR(`  %done = load i1, ptr @${name}_dtor_init`)
    emitIR(`  br i1 %done, label %ret, label %init`)
    emitIR("init:")
    emitIR(`  store i1 true, ptr @${name}_dtor_init`)
    emitIR(`  %gep = getelementptr [100 x ptr], ptr @ss_class_dtor, i64 0, i64 ${dtorIdx}`)
    emitIR(`  store ptr @${name}_destroy, ptr %gep`)
    emitIR("  br label %ret")
    emitIR("ret:")
    emitIR("  ret void")
    emitIR("}")
    emitIR("")
}

function genClassDecl(id: int) {
    const name = classNodeName(id)
    const fieldStr = classFields.getString(name)
    const hasVtable = classNeedsVtable.has(name) == 1 ? 1 : 0

    emitClassStruct(name, fieldStr, hasVtable)
    emitClassVtableConst(name, hasVtable)
    emitClassConstructor(name, fieldStr, hasVtable)

    const methodsBlockId = classMethodsBlock(id)
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
    genAutoToJson(name, fieldStr)
    emitClassDtorRegister(name, fieldStr, hasVtable)
}

// Emit @ClassName_destroy(ptr %self) — release all ptr-type fields
function emitClassDestroy(className: string, fieldStr: string, hasVtable: int) {
    regCount = 0
    emitIR(`define void @${className}_destroy(ptr %self) {`)
    emitIR("entry:")
    if (fieldStr != "") {
        let idx = hasVtable == 1 ? 1 : 0
        const parts = fieldStr.split(",")
        for (p in parts) {
            const owner = findFieldOwner(p, className)
            let ft = ""
            if (owner != "") { ft = classFieldTypes.getString(`${owner}.${p}`) }
            if (ft == "") { ft = classFieldTypes.getString(`${className}.${p}`) }
            const llType = ssTypeToLLVM(ft)
            if (llType == "ptr") {
                const gepR = nextReg()
                emitIR(`  ${gepR} = getelementptr %${className}, ptr %self, i32 0, i32 ${idx}`)
                const loadR = nextReg()
                emitIR(`  ${loadR} = load ptr, ptr ${gepR}, align 8`)
                if (nonOwningFields.has(`${className}.${p}`) == 1) {
                    emitIR(`  call void @ss_rc_release_no_children(ptr ${loadR})`)
                } else {
                    emitIR(`  call void @ss_rc_release(ptr ${loadR})`)
                }
            }
            idx = idx + 1
        }
    }
    emitIR("  ret void")
    emitIR("}")
    emitIR("")
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
    // Vtable classes have vtable ptr at index 0, data fields start at 1
    let fieldIdx = classNeedsVtable.has(className) == 1 ? 1 : 0
    let fieldOrd = 0
    for (f in fields) {
        const fType = classFieldTypes.getString(`${className}.${f}`)
        const llFType = ssTypeToLLVM(fType)

        // Add comma separator
        if (fieldOrd > 0) {
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
        fieldOrd = fieldOrd + 1
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
    const mName = funcName(id)
    let retType = funcRetType(id)
    if (retType == "") { retType = "void" }
    const llRetType = ssTypeToLLVM(retType)

    // Build param list (this + declared params)
    let paramStr = "ptr %this.ptr"
    const paramList = funcParams(id)
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
    localPtrVars = ""
    rcBlockDepth = 0

    emitIR(`define ${llRetType} @${llMethodName}(${paramStr}) {`)
    emitIR("entry:")

    // Alloca this
    emitIR("  %this = alloca ptr, align 8")
    emitIR("  store ptr %this.ptr, ptr %this, align 8")
    setVarType("this", className)

    emitParamAllocas(paramList, 0)

    // Generate body
    const bodyId = funcBody(id)
    genBlock(bodyId)

    // Default return
    if (terminated == 0) {
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
    if (idx < 0) {
        println(`codegen error: class '${className}' has no field '${field}'`)
        exit(1)
    }
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
    // Vtable classes have vtable ptr at index 0, data fields start at 1
    let idx = classNeedsVtable.has(className) == 1 ? 1 : 0
    for (p in parts) {
        if (p == fieldName) { return idx }
        idx = idx + 1
    }
    return -1
}
