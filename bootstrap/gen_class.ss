// Class codegen for bootstrap compiler

// ── Class state ──────────────────────────────────────────────

let classFields = ""     // "ClassName" -> "field1,field2,..."
let classFieldTypes = "" // "ClassName.field" -> "type"
let classMethods = ""    // "ClassName" -> "method1,method2,..."
let objClasses = ""      // "varName" -> "ClassName"
let classParents = ""    // "ClassName" -> "ParentClassName"
let classConstFields = "" // "ClassName.field" -> "1" (if field is const)
let classNeedsVtable = "" // "ClassName" -> "1" (if class has vtable)
let classVtableSlots = "" // "ClassName" -> "method1,method2,..." (ordered vtable slots)
let classVtableImpl = ""  // "ClassName.method" -> "ImplClassName_method" (actual func)
let classDtorTags = ""    // "ClassName" -> "tag" (tag >= 10 for classes with ptr fields)
let dtorNextTag = 10      // next available class dtor tag
let currentClassName = ""
let classStateReady = 0
// Interface metadata
let ifaceMethodsCG = ""   // "Shape" -> "area,name" (interface method list)
let ifaceMethodRets = ""  // "Shape.area" -> "int" (return type)
let ifaceMethodPars = ""  // "Shape.area" -> "p1:int,p2:string" (param name:type pairs)
let ifaceImplementors = "" // "Shape" -> "Circle,Rect"
let classIds = ""         // "Dog" -> "1" (unique class_id for TypeInfo)
let nextClassId = 1
// Generic class inheritance: deferred struct emission + codegen tracking
let registrationPhase = 0    // 1 during registerAllDecls, 0 during codegen
let deferredStructDefs = ""  // comma-separated mangled names needing struct emission
let specClassNodeId = ""     // Map: mangledName -> classNodeId (for deferred codegen)
let specClassTypeArgs = ""   // Map: mangledName -> "int,string" (for deferred codegen)
let specClassGenerated = ""  // Map: mangledName -> "1" (code already generated)

function initClassState() {
    if (classStateReady == 1) { return }
    classFields = Map()
    classFieldTypes = Map()
    classMethods = Map()
    objClasses = Map()
    classParents = Map()
    classConstFields = Map()
    classNeedsVtable = Map()
    classVtableSlots = Map()
    classVtableImpl = Map()
    classDtorTags = Map()
    dtorNextTag = 10
    currentClassName = ""
    ifaceMethodsCG = Map()
    ifaceMethodRets = Map()
    ifaceMethodPars = Map()
    ifaceImplementors = Map()
    classIds = Map()
    nextClassId = 1
    // Register Map as a built-in class (eliminates special cases)
    classFields.set("Map", "")
    classMethods.set("Map", "set,get,getString,has,delete,size,keys")
    // Register Set as built-in class (Map wrapper, D021)
    classFields.set("Set", "")
    classMethods.set("Set", "add,has,remove,size,values")
    // Register Math as built-in class with static methods (Java/JS style)
    classFields.set("Math", "")
    classStateReady = 1
}

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

// ── Layout helpers ────────────────────────────────────────────

// Returns the struct index where data fields start (after rc, TypeInfo, optional vtable)
function fieldStartIdx(hasVtable: int): int {
    return hasVtable == 1 ? 3 : 2
}

// Returns 1 if the type uses new RC system (ss_retain/ss_release).
// Includes interfaces: interface-typed vars hold class instance ptrs at runtime.
function isUserClass(typeName: string): int {
    if (typeName == "Map") { return 0 }
    if (classFields.has(typeName) == 1) { return 1 }
    if (ifaceMethodsCG.has(typeName) == 1) { return 1 }
    return 0
}

// Emit retain call for the appropriate RC system
function emitRetainForType(reg: string, ssType: string) {
    if (isUserClass(ssType) == 1) {
        emitIR(`  call void @ss_retain(ptr ${reg})`)
    } else {
        emitIR(`  call void @ss_rc_retain(ptr ${reg})`)
    }
}

// Emit release call for the appropriate RC system
function emitReleaseForType(reg: string, ssType: string) {
    if (isUserClass(ssType) == 1) {
        emitIR(`  call void @ss_release(ptr ${reg})`)
    } else {
        emitIR(`  call void @ss_rc_release(ptr ${reg})`)
    }
}

import { registerInterface, generateInterfaceDispatchers } from "./gen_iface"
import { splitParentType, emitDeferredStructDefs, preRegisterSpecializedClass, genGenericNewExpr, generateDeferredSpecializations } from "./gen_generic_class"

// ── Class support ─────────────────────────────────────────────

function registerClass(id: int) {
    // Generic classes: skip registration (unresolved type params).
    // Will be registered with concrete types at specialization time.
    if (classTypeParams(id) != "") { return }
    const name = classNodeName(id)
    const extendsName = classParentName(id)
    if (extendsName != "") {
        splitParentType(extendsName)
        const baseParent = parentBaseName
        const pTArgs = parentTypeArgs
        if (pTArgs != "" && genericClassNodes.has(baseParent) == 1) {
            // Case B: non-generic extends specialized generic (e.g., IntBox extends Box<int>)
            const parentNodeId = parseInt(genericClassNodes.getString(baseParent))
            const parentTP = classTypeParams(parentNodeId)
            const tpList = parentTP.split(",")
            const tArgList = pTArgs.split(",")
            const subs = Map()
            let tpIdx = 0
            for (tp in tpList) {
                let ai = 0
                for (ta in tArgList) {
                    if (ai == tpIdx) { subs.set(tp, ta) }
                    ai = ai + 1
                }
                tpIdx = tpIdx + 1
            }
            let mangledSig = ""
            for (tp in tpList) {
                if (subs.has(tp) == 1) {
                    if (mangledSig != "") { mangledSig = `${mangledSig}_` }
                    mangledSig = `${mangledSig}${typeSig(subs.getString(tp))}`
                }
            }
            const mangledParent = `${baseParent}_${mangledSig}`
            preRegisterSpecializedClass(parentNodeId, mangledParent, subs)
            classParents.set(name, mangledParent)
        } else {
            classParents.set(name, baseParent)
        }
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
                fieldNames = listAppendStr(fieldNames, fName)
                classFieldTypes.set(`${name}.${fName}`, fType)
                if (nGetS3(pId) == "const") {
                    classConstFields.set(`${name}.${fName}`, "1")
                }
            }
        }
    }
    // Store own fields only; inheritance resolved in resolveInheritance()
    classFields.set(name, fieldNames)
    // Register auto-generated clone method return types
    funcRetTypes.set(`${name}_deepClone`, name)
    funcRetTypes.set(`${name}_shallowClone`, name)
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
                    methodNames = listAppendStr(methodNames, mName)
                    let mRet = funcRetType(mId)
                    if (mRet == "") { mRet = "void" }
                    funcRetTypes.set(`${name}_${mName}`, mRet)
                    const mSig = paramSig(funcParams(mId))
                    if (mSig != "") {
                        funcRetTypes.set(`${name}_${mName}_${mSig}`, mRet)
                    }
                    trackOverload(`${name}_${mName}`)
                }
            }
        }
    }
    classMethods.set(name, methodNames)
    // Assign unique class_id for TypeInfo dispatch
    classIds.set(name, `${nextClassId}`)
    nextClassId = nextClassId + 1
    // Track interface implementations
    const implList = nGetS3(id)
    if (implList != "") {
        const implParts = implList.split(",")
        for (iface in implParts) {
            if (iface == "") { continue }
            const prev = ifaceImplementors.has(iface) == 1 ? ifaceImplementors.getString(iface) : ""
            ifaceImplementors.set(iface, listAppendStr(prev, name))
        }
    }
}

// Resolve inheritance after ALL classes are registered.
// Uses resolve-parent-first recursion to handle 3+ level chains correctly.
let resolvedInheritance = ""
function resolveInheritance() {
    resolvedInheritance = Map()
    const allClasses = classFields.keys()
    if (allClasses == "") { return }
    const classList = allClasses.split("\n")
    for (cls in classList) {
        if (cls == "") { continue }
        resolveInheritanceForClass(cls)
    }
}

function resolveInheritanceForClass(cls: string) {
    if (resolvedInheritance.has(cls) == 1) { return }
    resolvedInheritance.set(cls, "1")
    const parent = classParents.has(cls) == 1 ? classParents.getString(cls) : ""
    if (parent == "" || classFields.has(parent) == 0) { return }
    // Resolve parent first (recursive) — ensures classFields[parent] is fully resolved
    resolveInheritanceForClass(parent)
    // Now classFields[parent] already includes all ancestor fields
    const parentFields = classFields.getString(parent)
    const ownFields = classFields.getString(cls)
    if (parentFields != "") {
        if (ownFields == "") {
            classFields.set(cls, parentFields)
        } else {
            classFields.set(cls, `${parentFields},${ownFields}`)
        }
        // Copy parent field types to child
        const pfs = parentFields.split(",")
        for (pf in pfs) {
            const parentCls = findFieldOwner(pf, parent)
            if (parentCls != "" && classFieldTypes.has(`${parentCls}.${pf}`) == 1) {
                classFieldTypes.set(`${cls}.${pf}`, classFieldTypes.getString(`${parentCls}.${pf}`))
                if (classConstFields.has(`${parentCls}.${pf}`) == 1) {
                    classConstFields.set(`${cls}.${pf}`, "1")
                }
            }
        }
    }
}

// ── Class codegen helpers ────────────────────────────────────

function emitClassStruct(name: string, fieldStr: string, hasVtable: int) {
    // New layout: rc:i32 at offset 0, TypeInfo*:ptr at offset 1, then optional vtable, then fields
    let fieldTypes = "i32, ptr"
    if (hasVtable == 1) { fieldTypes = fieldTypes + ", ptr" }
    if (fieldStr != "") {
        const parts = fieldStr.split(",")
        for (p in parts) {
            const ft = classFieldTypes.getString(`${name}.${p}`)
            const llType = ssTypeToLLVM(ft)
            fieldTypes = fieldTypes + ", " + llType
        }
    }
    emitIR(`%${name} = type { ${fieldTypes} }`)
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
    const mallocReg = nextReg()
    emitIR(`  ${mallocReg} = call ptr @ss_alloc(i64 ${sizeReg})`)
    emitClassCtorBody(name, fieldStr, hasVtable, mallocReg)
    emitIR(`  ret ptr ${mallocReg}`)
    emitIR("}")
    emitIR("")
}

import { assignClassDtorTags, buildClassVtables, emitClassVtableConst, emitClassDtorRegister, emitClassTypeInfo, emitClassDropFieldsFn, emitClassCtorBody, emitClassConstructorReuse, genAutoToJson } from "./gen_type_ops"

function genClassDecl(id: int) {
    const name = specClassName != "" ? specClassName : classNodeName(id)
    const fieldStr = classFields.getString(name)
    const hasVtable = classNeedsVtable.has(name) == 1 ? 1 : 0

    // Skip struct emission for specialized generic classes (already emitted into strConsts)
    if (specClassName == "") { emitClassStruct(name, fieldStr, hasVtable) }
    emitClassVtableConst(name, hasVtable)
    emitClassConstructor(name, fieldStr, hasVtable)
    emitClassDropFieldsFn(name, fieldStr, hasVtable)
    emitClassConstructorReuse(name, fieldStr, hasVtable)

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
    emitClassTypeInfo(name, fieldStr, hasVtable)
}

function genClassMethod(className: string, id: int) {
    const mName = funcName(id)
    let retType = resolveTypeParam(funcRetType(id))
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
                const pType = resolveTypeParam(nGetS2(pId))
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

function genNewExpr(id: int): string {
    const className = nGetS1(id)
    // Generic class: monomorphize at instantiation site
    if (genericClassNodes.has(className) == 1) {
        return genGenericNewExpr(id, className)
    }
    // Map and Set are built-in — constructor delegates to ss_mapNew
    if (className == "Map" || className == "Set") {
        pirPendingReuseReg = ""
        pirPendingReuseClass = ""
        const r = nextReg()
        emitIR(`  ${r} = call ptr @ss_mapNew()`)
        return r
    }
    // Capture and clear REUSE state before arg evaluation (prevents nested consumption)
    let reuseReg = ""
    if (pirPendingReuseReg != "" && pirPendingReuseClass == className) {
        reuseReg = pirPendingReuseReg
    }
    pirPendingReuseReg = ""
    pirPendingReuseClass = ""

    const argList = nGetList(id)
    let args = ""
    // Check if first arg is NAMED_ARG
    let hasNamed = 0
    if (argList != "") {
        const ci = argList.indexOf(",")
        const firstArgId = parseInt(ci >= 0 ? argList.substring(0, ci) : argList)
        if (firstArgId > 0 && nGetKind(firstArgId) == "NAMED_ARG") { hasNamed = 1 }
    }
    if (hasNamed == 1) {
        args = genNamedConstructorArgs(className, argList)
    } else if (argList != "") {
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
    // PIR REUSE: use reuse constructor if memory is available from a previous drop
    if (reuseReg != "") {
        const r = nextReg()
        emitIR(`  ${r} = call ptr @${className}_new_reuse(ptr ${reuseReg}, ${args})`)
        return r
    }
    const r = nextReg()
    emitIR(`  ${r} = call ptr @${className}_new(${args})`)
    return r
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

// obj?.field — if obj is null, return default; otherwise access normally
function genOptionalMemberAccess(id: int): string {
    const objId = nGetI1(id)
    const member = nGetS1(id)
    const objVal = genExpr(objId)
    const retType = inferType(id)
    const llRetType = ssTypeToLLVM(retType)

    const resultAlloca = nextReg()
    emitIR(`  ${resultAlloca} = alloca ${llRetType}, align 8`)
    if (llRetType == "ptr") {
        const emptyStr = addStringConst("")
        emitIR(`  store ptr ${emptyStr}, ptr ${resultAlloca}, align 8`)
    } else {
        emitIR(`  store ${llRetType} 0, ptr ${resultAlloca}, align 8`)
    }

    const cmpR = nextReg()
    emitIR(`  ${cmpR} = icmp eq ptr ${objVal}, null`)
    const accessLabel = nextLabel("optf.access")
    const endLabel = nextLabel("optf.end")
    emitIR(`  br i1 ${cmpR}, label %${endLabel}, label %${accessLabel}`)

    emitIR(`${accessLabel}:`)
    // Resolve class and emit field load directly (avoid re-evaluating objId)
    let className = ""
    const objKind = nGetKind(objId)
    if (objKind == "IDENT") { className = getObjClass(nGetS1(objId)) }
    if (className == "") { className = resolveObjClass(objId) }
    let accessResult = objVal
    if (className != "") { accessResult = emitFieldLoad(className, objVal, member) }
    emitIR(`  store ${llRetType} ${accessResult}, ptr ${resultAlloca}, align 8`)
    emitIR(`  br label %${endLabel}`)

    emitIR(`${endLabel}:`)
    const finalR = nextReg()
    emitIR(`  ${finalR} = load ${llRetType}, ptr ${resultAlloca}, align 8`)
    return finalR
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
    // Generic fallback: resolve class via resolveObjClass for nested access, calls, etc.
    const resolvedClass = resolveObjClass(objId)
    if (resolvedClass != "") { return emitFieldLoad(resolvedClass, objVal, member) }
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
    // New layout: rc at 0, TypeInfo at 1, optional vtable at 2, fields start at 2 or 3
    let idx = classNeedsVtable.has(className) == 1 ? 3 : 2
    for (p in parts) {
        if (p == fieldName) { return idx }
        idx = idx + 1
    }
    return -1
}

