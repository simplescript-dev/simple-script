// Class codegen for bootstrap compiler

// ── Class state ──────────────────────────────────────────────

let classFields = ""     // "ClassName" -> "field1,field2,..."
let classFieldTypes = "" // "ClassName.field" -> "type"
let classFieldAnnotations = "" // "ClassName.field" -> "Ann1,Ann2" CSV of annotation names (D095 Stage C — FieldMeta reflection)
let classFieldAnnotationArgs = "" // "ClassName.field.AnnName" -> "arg0,arg1" CSV of string-lit arg values (D095 Stage C — a.args reflection, L2η)
let classAnnotations = ""     // "ClassName" -> "Ann1,Ann2" CSV of class-level annotation names (D096 L2θ — cls.annotations reflection)
let classAnnotationArgs = ""  // "ClassName.AnnName" -> "arg0,arg1" CSV of string-lit arg values (D096 L2θ — a.args for class-level annotations)
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
// D096: accessor tables — key "ClassName.field" -> mangled symbol name.
// MEMBER_ACCESS/ASSIGN codegen consults these to rewrite obj.field into a call.
let classAccessorGetters = ""
let classAccessorSetters = ""
// D096: setter's declared first-param SS type; call sites use it to pick the
// LLVM arg type and trunc i64→i32 when the value expr disagrees.
let classAccessorSetterParamTypes = ""
// Interface metadata
let ifaceMethodsCG = ""   // "Shape" -> "area,name" (interface method list)
let ifaceMethodRets = ""  // "Shape.area" -> "int" (return type)
let ifaceMethodPars = ""  // "Shape.area" -> "p1:int,p2:string" (param name:type pairs)
let ifaceImplementors = "" // "Shape" -> "Circle,Rect"
let classNodeIds = ""     // "ClassName" -> AST node ID (for @typeInfo reflection)
let classIds = ""         // "Dog" -> "1" (unique class_id for TypeInfo)
let nextClassId = 1
// Generic class inheritance: deferred struct emission + codegen tracking
let registrationPhase = 0    // 1 during registerAllDecls, 0 during codegen
let deferredStructDefs = ""  // comma-separated mangled names needing struct emission
let specClassNodeId = ""     // Map: mangledName -> classNodeId (for deferred codegen)
let specClassTypeArgs = ""   // Map: mangledName -> "int,string" (for deferred codegen)
let specClassGenerated = ""  // Map: mangledName -> "1" (code already generated)
let abstractMethodsCG = ""   // "ClassName.methodName" -> "1" (D071: abstract methods in codegen)
// D078: Static fields
let staticFieldGlobals = ""  // "ClassName.fieldName" -> "@ClassName_fieldName"
let staticFieldTypes = ""    // "ClassName.fieldName" -> SS type
let sfPendingInits = ""      // comma-separated "ClassName.fieldName" entries needing runtime init
let sfInitExprs = ""         // "ClassName.fieldName" -> initNodeId (int)

function initClassState() {
    if (classStateReady == 1) { return }
    classFields = Map()
    classFieldTypes = Map()
    classFieldAnnotations = Map()
    classFieldAnnotationArgs = Map()
    classAnnotations = Map()
    classAnnotationArgs = Map()
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
    emittedDispatchers = Map()
    classNodeIds = Map()
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
    // Register Thread as built-in class (D082 Phase 2)
    classFields.set("Thread", "")
    abstractMethodsCG = Map()
    classAccessorGetters = Map()
    classAccessorSetters = Map()
    classAccessorSetterParamTypes = Map()
    staticFieldGlobals = Map()
    staticFieldTypes = Map()
    sfPendingInits = ""
    sfInitExprs = Map()
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

// ── D078: Static field support ────────────────────────────────

function registerStaticField(className: string, fieldName: string, fieldType: string, initId: int) {
    const key = `${className}.${fieldName}`
    const globalName = `@${className}_${fieldName}`
    staticFieldGlobals.set(key, globalName)
    staticFieldTypes.set(key, fieldType)
    const llType = ssTypeToLLVM(fieldType)
    if (initId > 0) {
        const litType = emitLiteralGlobalInit(globalName, initId)
        if (litType == "") {
            let zeroVal = "0"
            if (llType == "double") { zeroVal = "0.0" }
            if (llType == "ptr") { zeroVal = "null" }
            emitIR(`${globalName} = global ${llType} ${zeroVal}, align 8`)
            sfPendingInits = listAppendStr(sfPendingInits, key)
            sfInitExprs.set(key, initId)
        }
    } else {
        if (llType == "i32") {
            emitIR(`${globalName} = global i32 0, align 4`)
        } else if (llType == "double") {
            emitIR(`${globalName} = global double 0.0, align 8`)
        } else {
            emitIR(`${globalName} = global ptr null, align 8`)
        }
    }
}

function emitStaticFieldInits() {
    if (sfPendingInits == "") { return }
    const parts = sfPendingInits.split(",")
    for (p in parts) {
        const globalName = staticFieldGlobals.getString(p)
        const initId = sfInitExprs.get(p)
        const fType = staticFieldTypes.getString(p)
        const llType = ssTypeToLLVM(fType)
        const val = genExpr(initId)
        emitIR(`  store ${llType} ${val}, ptr ${globalName}, align 8`)
    }
}

// ── Class support ─────────────────────────────────────────────

// L2ζ/L2η/L2θ: fill namesMap[keyPrefix] with annotation name CSV and
// argsMap["${keyPrefix}.${annName}"] with STRING_LIT arg CSV for each annotation.
// Non-STRING_LIT args are silently dropped. Shared by field-level and class-level
// reflection paths.
function extractAnnotationsReflection(annListId: int, namesMap: Map, argsMap: Map, keyPrefix: string) {
    if (annListId <= 0 || nGetKind(annListId) != "ANNOTATION_LIST") { return }
    const anns = nGetList(annListId)
    if (anns == "") { return }
    let names = ""
    const aParts = anns.split(",")
    for (ap in aParts) {
        const aId = parseInt(ap)
        if (aId <= 0 || nGetKind(aId) != "ANNOTATION") { continue }
        const annName = nGetS1(aId)
        names = listAppendStr(names, annName)
        const argsCsv = nGetList(aId)
        if (argsCsv != "") {
            let argVals = ""
            const argParts = argsCsv.split(",")
            for (arp in argParts) {
                const argId = parseInt(arp)
                if (argId > 0 && nGetKind(argId) == "STRING_LIT") {
                    argVals = listAppendStr(argVals, nGetS1(argId))
                }
            }
            if (argVals != "") {
                argsMap.set(`${keyPrefix}.${annName}`, argVals)
            }
        }
    }
    if (names != "") { namesMap.set(keyPrefix, names) }
}

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
    // Collect field names and types — D078: separate static fields from instance fields
    let fieldNames = ""
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                const fName = paramName(pId)
                const fType = paramType(pId)
                const strippedType = stripNullableCG(fType)
                if (nGetS3(pId) == "const") {
                    classConstFields.set(`${name}.${fName}`, "1")
                }
                // D078: static field → emit global variable, skip from instance fields
                if (nGetI4(pId) == 1) {
                    registerStaticField(name, fName, strippedType, nGetI1(pId))
                } else {
                    fieldNames = listAppendStr(fieldNames, fName)
                    classFieldTypes.set(`${name}.${fName}`, strippedType)
                    // D095 Stage C: PARAM.list holds ANNOTATION_LIST id as string (parser.ss:437).
                    const fAnnListRaw = nGetList(pId)
                    if (fAnnListRaw != "") {
                        extractAnnotationsReflection(parseInt(fAnnListRaw), classFieldAnnotations, classFieldAnnotationArgs, `${name}.${fName}`)
                    }
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
                    // D071: track abstract methods
                    if (nGetI4(mId) == 1) {
                        abstractMethodsCG.set(`${name}.${mName}`, "1")
                    }
                    let mRet = stripNullableCG(funcRetType(mId))
                    if (mRet == "") { mRet = "void" }
                    // D096: accessor mangling — I2=2 getter / I2=3 setter.
                    // Prefix disambiguates from same-name regular methods and from
                    // paired getter+setter (both have mName=field).
                    const mKind = nGetI2(mId)
                    if (mKind == 2 || mKind == 3) {
                        // D096: accessor cannot share a name with a declared field.
                        if (classFieldTypes.has(`${name}.${mName}`) == 1) {
                            const accKindName = mKind == 2 ? "getter" : "setter"
                            println(`error: class '${name}' ${accKindName} '${mName}' conflicts with field of the same name`)
                            exit(1)
                        }
                    }
                    if (mKind == 2) {
                        const getMangled = `${name}_get_${mName}`
                        classAccessorGetters.set(`${name}.${mName}`, getMangled)
                        funcRetTypes.set(getMangled, mRet)
                    } else if (mKind == 3) {
                        const setMangled = `${name}_set_${mName}`
                        classAccessorSetters.set(`${name}.${mName}`, setMangled)
                        funcRetTypes.set(setMangled, mRet)
                        const setParams = funcParams(mId)
                        if (setParams != "") {
                            const setParts = setParams.split(",")
                            const setFirstPid = parseInt(setParts[0])
                            if (setFirstPid > 0) {
                                classAccessorSetterParamTypes.set(`${name}.${mName}`, nGetS2(setFirstPid))
                            }
                        }
                    } else {
                        registerClassMethodRetType(name, mId, mRet)
                    }
                }
            }
        }
    }
    classMethods.set(name, methodNames)
    // Assign unique class_id for TypeInfo dispatch
    classNodeIds.set(name, `${id}`)
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
    const classList = classFields.keys()
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
    regTable = []
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

// @methodOf(cls) state: handler-internal FUNC_DECLs queued for class injection.
let pendingMethodInjections = new Map()  // className → comma-separated FUNC_DECL ids

function pendingMethodAdd(className: string, funcId: int) {
    let cur = ""
    if (pendingMethodInjections.has(className) == 1) { cur = pendingMethodInjections.getString(className) }
    pendingMethodInjections.set(className, listAppend(cur, funcId))
}

function pendingMethodTake(className: string): string {
    if (pendingMethodInjections.has(className) == 0) { return "" }
    const v = pendingMethodInjections.getString(className)
    pendingMethodInjections.delete(className)
    return v
}

// Look up an IDENT name in the outer comptime scope (ctScopeStack → ctVars
// → interpVars), mirroring genVal's IDENT path but without IR side effects.
// Returns tagged ctVal if bound to a comptime value, -1 otherwise.
function lookupComptimeBinding(name: string): int {
    if (comptimeDepth > 0 && ctScopeStack.length() > 0) {
        let si = ctScopeStack.length() - 1
        while (si >= 0) {
            const k = `${ctScopeStack[si]}:${name}`
            if (ctVars.has(k) == 1) { return parseInt(ctVars.getString(k)) }
            si = si - 1
        }
    }
    const fk = `${currentFunc}:${name}`
    if (ctVars.has(fk) == 1 && ctInvalidated.has(fk) == 0) {
        const v = parseInt(ctVars.getString(fk))
        if (isCt(v) == 1) { return v }
    }
    if (comptimeDepth > 0) {
        const ik = interpFindScopeKey(name)
        if (ik != "") { return ctVal(parseInt(interpVars.getString(ik))) }
    }
    return -1
}

// Replace an IDENT node in-place with the corresponding LIT for its comptime
// value. Returns 1 if replaced, 0 otherwise.
function rewriteIdentToLit(nodeId: int, tagged: int): int {
    if (isCt(tagged) == 0) { return 0 }
    const pl = payload(tagged)
    const tk = tvKindOf(pl)
    if (tk == "string") {
        nKind.set(nodeId + "", "STRING_LIT")
        nSetS1(nodeId, tvStringOf(pl))
        return 1
    }
    if (tk == "int") {
        nKind.set(nodeId + "", "INT_LIT")
        nSetS1(nodeId, `${tvIntOf(pl)}`)
        return 1
    }
    if (tk == "double") {
        nKind.set(nodeId + "", "DOUBLE_LIT")
        nSetS1(nodeId, tvD1.getString(pl + ""))
        return 1
    }
    if (tk == "bool") {
        nKind.set(nodeId + "", tvIntOf(pl) == 1 ? "TRUE_LIT" : "FALSE_LIT")
        return 1
    }
    return 0
}

// Deep-clone an AST subtree. Required because foldComptimeIdentsInTree rewrites
// nodes in place; when the same FUNC_DECL is visited across multiple iterations
// of a handler-level for-in loop (D095 @Getter / @Setter pattern), each iteration
// must operate on its own AST copy so prior folds don't poison later ones.
//
// Slot semantics follow foldComptimeIdentsInTree: I1..I4 may be child node IDs
// (detected via `nGetKind(val) != ""`) OR raw ints; list is CSV of child IDs.
// Strings and line/col metadata are copied verbatim.
function cloneAstNode(id: int): int {
    if (id <= 0) { return 0 }
    const k = nGetKind(id)
    if (k == "") { return 0 }
    const nid = newNode(k)
    nSetS1(nid, nGetS1(id))
    nSetS2(nid, nGetS2(id))
    nSetS3(nid, nGetS3(id))
    nSetLine(nid, nGetLine(id))
    nSetCol(nid, nGetCol(id))
    const i1 = nGetI1(id)
    nSetI1(nid, i1 > 0 && nGetKind(i1) != "" ? cloneAstNode(i1) : i1)
    const i2 = nGetI2(id)
    nSetI2(nid, i2 > 0 && nGetKind(i2) != "" ? cloneAstNode(i2) : i2)
    const i3 = nGetI3(id)
    nSetI3(nid, i3 > 0 && nGetKind(i3) != "" ? cloneAstNode(i3) : i3)
    const i4 = nGetI4(id)
    nSetI4(nid, i4 > 0 && nGetKind(i4) != "" ? cloneAstNode(i4) : i4)
    const list = nGetList(id)
    if (list != "") {
        const parts = list.split(",")
        let newList = ""
        for (p in parts) {
            const childId = parseInt(p)
            const cloned = childId > 0 && nGetKind(childId) != "" ? cloneAstNode(childId) : childId
            newList = newList == "" ? `${cloned}` : `${newList},${cloned}`
        }
        nSetList(nid, newList)
    }
    return nid
}

// Resolve an AST node (after fold) to its compile-time string literal.
// STRING_LIT → its text; TEMPLATE_LIT → concat of fragments where TMPL_FRAG_EXPR
// inner node is recursively resolved (folded IDENTs now appear as STRING_LIT).
function resolveComptimeString(id: int): string {
    if (id <= 0) { return "" }
    const k = nGetKind(id)
    if (k == "STRING_LIT") { return nGetS1(id) }
    // D095 FieldMeta: `f.name` where f has been folded to STRING_LIT — .name
    // on a string literal is self (the field name itself).
    if (k == "MEMBER_ACCESS" && nGetS1(id) == "name") {
        const mObj = nGetI1(id)
        if (nGetKind(mObj) == "STRING_LIT") { return nGetS1(mObj) }
    }
    if (k == "TEMPLATE_LIT") {
        const list = nGetList(id)
        if (list == "") { return "" }
        let s = ""
        const parts = list.split(",")
        for (p in parts) {
            const fragId = parseInt(p)
            const fk = nGetKind(fragId)
            if (fk == "TMPL_FRAG_LIT") {
                s = s + nGetS1(fragId)
            } else if (fk == "TMPL_FRAG_EXPR") {
                s = s + resolveComptimeString(nGetI1(fragId))
            }
        }
        return s
    }
    return ""
}

// In-place AST rewrite: walk tree, fold every IDENT whose name resolves to
// a comptime value in the outer handler's scope. Recurses through I1..I4 and
// the list slot. Non-node ints are filtered by nGetKind == "" check.
function foldComptimeIdentsInTree(rootId: int) {
    if (rootId <= 0) { return }
    const k = nGetKind(rootId)
    if (k == "") { return }
    if (k == "IDENT") {
        const name = nGetS1(rootId)
        const tagged = lookupComptimeBinding(name)
        if (tagged > 0) { rewriteIdentToLit(rootId, tagged) }
        return
    }
    foldComptimeIdentsInTree(nGetI1(rootId))
    foldComptimeIdentsInTree(nGetI2(rootId))
    foldComptimeIdentsInTree(nGetI3(rootId))
    foldComptimeIdentsInTree(nGetI4(rootId))
    const list = nGetList(rootId)
    if (list != "") {
        const parts = list.split(",")
        for (p in parts) { foldComptimeIdentsInTree(parseInt(p)) }
    }
}

// Cheap check: does this FUNC_DECL carry a @methodOf annotation?
function hasMethodOfAnnotation(funcId: int): int {
    const annListId = nGetI4(funcId)
    if (annListId <= 0 || nGetKind(annListId) != "ANNOTATION_LIST") { return 0 }
    const anns = nGetList(annListId)
    if (anns == "") { return 0 }
    const aParts = anns.split(",")
    for (ap in aParts) {
        const aId = parseInt(ap)
        if (aId > 0 && nGetKind(aId) == "ANNOTATION" && nGetS1(aId) == "methodOf") { return 1 }
    }
    return 0
}

// Evaluate a `ct:<exprId>` encoded type to its string. Errors point at the
// expr's source node so users see line:col, not just the slot description.
function resolveCtType(encoded: string, slotDesc: string): string {
    const exprId = parseInt(encoded.substring(3, encoded.length() - 3))
    const tagged = genVal(exprId)
    if (isCt(tagged) == 0) {
        comptimeError(`type interpolation must resolve at comptime (${slotDesc})`, exprId)
    }
    const typeName = interpAsStr(payload(tagged))
    if (typeName == "") {
        comptimeError(`type interpolation yielded empty string (${slotDesc})`, exprId)
    }
    return typeName
}

// Resolve `ct:<exprId>` encoded types (from type-position `${expr}` syntax) on
// each PARAM's S2 and the FUNC_DECL's own retType (S2). Runs after the body
// fold so exprs can reference folded comptime consts (e.g. `v: ${f.type}`).
function foldCtTypesInFuncDecl(funcId: int) {
    const paramList = funcParams(funcId)
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId <= 0 || nGetKind(pId) != "PARAM") { continue }
            const t = paramType(pId)
            if (t.startsWith("ct:") == 1) {
                nSetS2(pId, resolveCtType(t, `param '${paramName(pId)}'`))
            }
        }
    }
    const retT = funcRetType(funcId)
    if (retT.startsWith("ct:") == 1) {
        nSetS2(funcId, resolveCtType(retT, `func '${funcName(funcId)}' return type`))
    }
}

// Detect @methodOf(cls) on a comptime FUNC_DECL: fold every captured outer
// IDENT in body (including cls) to its comptime literal, queue the func for
// injection into that class. Returns 1 if handled.
function handleMethodOfFuncDecl(funcId: int): int {
    const annListId = nGetI4(funcId)
    if (annListId <= 0 || nGetKind(annListId) != "ANNOTATION_LIST") { return 0 }
    const anns = nGetList(annListId)
    if (anns == "") { return 0 }
    const aParts = anns.split(",")
    for (ap in aParts) {
        const aId = parseInt(ap)
        if (aId <= 0 || nGetKind(aId) != "ANNOTATION" || nGetS1(aId) != "methodOf") { continue }
        const argList = nGetList(aId)
        if (argList == "") { continue }
        const aArg = parseInt(argList.split(",")[0])
        if (aArg <= 0 || nGetKind(aArg) != "IDENT") { continue }
        const tagged = genVal(aArg)
        if (isCt(tagged) == 0) { continue }
        const clsName = interpAsStr(payload(tagged))
        if (clsName == "") { continue }
        // D095 Stage E: clone before fold so each handler-level for-in iteration
        // gets its own AST copy. Resolves computed method names (I2 template)
        // against the post-fold literal fragments.
        const clonedId = cloneAstNode(funcId)
        foldComptimeIdentsInTree(clonedId)
        foldCtTypesInFuncDecl(clonedId)
        if (nGetS1(clonedId) == "" && nGetI2(clonedId) > 0) {
            const resolvedName = resolveComptimeString(nGetI2(clonedId))
            if (resolvedName != "") {
                nSetS1(clonedId, resolvedName)
                nSetI2(clonedId, 0)
            }
        }
        pendingMethodAdd(clsName, clonedId)
        return 1
    }
    return 0
}

// Callers: class-level comptime blocks and @derive annotations.
function emitClassComptimeMethods(className: string) {
    const ccSS = interpGetComptimeSS()
    let ccParts = ""
    if (ccSS != "") {
        const ccTokens = tokenize(ccSS)
        const ccRoot = parse(ccTokens)
        const ccList = nGetList(ccRoot)
        if (ccList != "") { ccParts = ccList }
    }
    const pending = pendingMethodTake(className)
    if (pending != "") { ccParts = ccParts == "" ? pending : `${ccParts},${pending}` }
    if (ccParts == "") { interpClearComptimeSS(); return }
    const partList = ccParts.split(",")
    // Pass 1: register each comptime-generated method's signature so sibling
    // methods in pass 2 can resolve `this.other()` during IR gen.
    let ccMethods = classMethods.getString(className)
    for (ccp in partList) {
        const ccSid = parseInt(ccp)
        if (ccSid > 0 && nGetKind(ccSid) == "FUNC_DECL") {
            let ccRet = stripNullableCG(funcRetType(ccSid))
            if (ccRet == "") {
                // No explicit return annotation → infer from first RETURN.
                // inferType's "i64" sentinel means unknown bracket access; treat as void.
                const ccSavedName = currentClassName
                currentClassName = className
                const inferred = firstReturnInferredType(funcBody(ccSid))
                currentClassName = ccSavedName
                ccRet = (inferred != "" && inferred != "i64") ? inferred : "void"
                nSetS2(ccSid, ccRet)
            }
            registerClassMethodRetType(className, ccSid, ccRet)
            ccMethods = listAppendStr(ccMethods, funcName(ccSid))
        }
    }
    classMethods.set(className, ccMethods)
    // Pass 2: emit IR for methods; run any non-FUNC_DECL stmts in place.
    for (ccp in partList) {
        const ccSid = parseInt(ccp)
        if (ccSid <= 0) { continue }
        if (nGetKind(ccSid) == "FUNC_DECL") { genClassMethod(className, ccSid) }
        else { genStmt(ccSid) }
    }
    interpClearComptimeSS()
}

// Render an annotation arg AST node to its source-text form for handler call
// synthesis. Handles string/int/double/bool literals.
function annArgToSrc(argId: int): string {
    if (argId <= 0) { return "" }
    const k = nGetKind(argId)
    if (k == "STRING_LIT") {
        return "\"" + nGetS1(argId) + "\""
    }
    if (k == "INT_LIT" || k == "DOUBLE_LIT") { return nGetS1(argId) }
    if (k == "TRUE_LIT") { return "true" }
    if (k == "FALSE_LIT") { return "false" }
    if (k == "UNARY" && nGetS1(argId) == "Neg") {
        return "-" + annArgToSrc(nGetI1(argId))
    }
    return ""
}

function runComptimeAnnotationCall(handlerName: string, className: string, extraArgList: string) {
    let argsStr = "\"" + className + "\""
    if (extraArgList != "") {
        const eParts = extraArgList.split(",")
        for (ep in eParts) {
            const eId = parseInt(ep)
            const eSrc = annArgToSrc(eId)
            if (eSrc != "") { argsStr = argsStr + ", " + eSrc }
        }
    }
    const callSrc = `${handlerName}(${argsStr})\n`
    const tks = tokenize(callSrc)
    const root = parse(tks)
    const blk = newNode("BLOCK")
    nSetList(blk, nGetList(root))
    runComptimeBlockBody(blk)
    flushComptimeIR()
    emitClassComptimeMethods(className)
}

function genClassDecl(id: int) {
    if (comptimeDepth > 0) {
        const ctClassName = nGetS1(id)
        interpClasses.set(ctClassName, `${id}`)
        const ctParent = nGetS2(id)
        if (ctParent != "") { interpClassParents.set(ctClassName, ctParent) }
        // 预扫描可能已注册元数据;若已注册则跳过二次 push,避免 flushPendingCtClasses 重复 emit IR
        if (classFields.has(ctClassName) == 1) { return }
        pendingCtClassIds = pendingCtClassIds.push(`${id}`)
        return
    }
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
    // Execute class-level comptime blocks
    if (methodsBlockId > 0) {
        const ctmList = nGetList(methodsBlockId)
        if (ctmList != "") {
            const ctmParts = ctmList.split(",")
            for (ctmp in ctmParts) {
                const ctmId = parseInt(ctmp)
                if (ctmId <= 0 || nGetKind(ctmId) != "COMPTIME_BLOCK") { continue }
                runComptimeBlockBody(nGetI1(ctmId))
                flushComptimeIR()
                emitClassComptimeMethods(name)
            }
        }
    }
    // Annotation handler dispatch:
    //   @derive("X")    → ctDeriveX(className)        (legacy shim)
    //   @AnnName(...)   → AnnName(className)          (handler = function with same name)
    const annListId = nGetI4(id)
    if (annListId > 0 && nGetKind(annListId) == "ANNOTATION_LIST") {
        const anns = nGetList(annListId)
        if (anns != "") {
            const aParts = anns.split(",")
            // L2θ: class-level annotation reflection capture (names + args).
            extractAnnotationsReflection(annListId, classAnnotations, classAnnotationArgs, name)
            for (ap in aParts) {
                const aId = parseInt(ap)
                if (aId <= 0 || nGetKind(aId) != "ANNOTATION") { continue }
                const annName = nGetS1(aId)
                if (annName == "derive") {
                    const argList = nGetList(aId)
                    if (argList == "") { continue }
                    const argParts = argList.split(",")
                    for (dap in argParts) {
                        const argId = parseInt(dap)
                        if (argId <= 0 || nGetKind(argId) != "STRING_LIT") { continue }
                        runComptimeAnnotationCall(`ctDerive${nGetS1(argId)}`, name, "")
                    }
                } else if (ctFuncNodes.has(annName) == 1) {
                    runComptimeAnnotationCall(annName, name, nGetList(aId))
                }
            }
        }
    }
    genAutoToJson(name, fieldStr)
    emitClassDtorRegister(name, fieldStr, hasVtable)
    emitClassTypeInfo(name, fieldStr, hasVtable)
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

function genNewExpr(id: int): string {
    let className = resolveCtTypeAlias(nGetS1(id))
    // Generic class: monomorphize at instantiation site
    if (genericClassNodes.has(className) == 1) {
        return genGenericNewExpr(id, className)
    }
    // D082 Phase 4: Channel<T> is built-in — constructor delegates to ss_channelNew
    // Optional capacity arg: new Channel<int>() = unbounded, new Channel<int>(10) = bounded
    if (className == "Channel") {
        pirPendingReuseReg = ""
        pirPendingReuseClass = ""
        let capVal = "0"
        const chanArgList = nGetList(id)
        if (chanArgList != "") {
            const chanParts = chanArgList.split(",")
            const capArgId = parseInt(chanParts[0])
            if (capArgId > 0) {
                capVal = genExpr(capArgId)
            }
        }
        const r = nextReg()
        emitIR(`  ${r} = call ptr @ss_channelNew(i32 ${capVal})`)
        return r
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
    } else if (argList == "" && classFields.has(className) == 1) {
        // No args: fill in zero values for all fields
        const zfStr = classFields.getString(className)
        if (zfStr != "") {
            const zfParts = zfStr.split(",")
            let zfFirst = 1
            for (zf in zfParts) {
                const zfType = classFieldTypes.getString(`${className}.${zf}`)
                const zfLL = ssTypeToLLVM(zfType)
                if (zfFirst == 1) { zfFirst = 0 } else { args = args + ", " }
                if (zfLL == "ptr") { args = args + "ptr null" }
                else if (zfLL == "double") { args = args + "double 0.0" }
                else { args = `${args}${zfLL} 0` }
            }
        }
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

// D096: accessor getter retType lookup. Returns "" if no accessor or funcRetTypes
// missing; distinguishes "no accessor" from "accessor exists" via paired
// classAccessorGetters.has() check when the caller needs both signals.
function getAccessorRetType(className: string, member: string): string {
    const accKey = `${className}.${member}`
    if (classAccessorGetters.has(accKey) == 0) { return "" }
    const mangled = classAccessorGetters.getString(accKey)
    if (funcRetTypes.has(mangled) == 1) { return funcRetTypes.getString(mangled) }
    return ""
}

// D096: accessor getter dispatch. Returns reg from @ClassName_get_FIELD(ptr) call,
// "" when no accessor is registered (caller falls through to emitFieldLoad),
// or exits with a write-only-accessor error when only the setter exists.
function tryEmitAccessorGet(className: string, objReg: string, member: string): string {
    const accKey = `${className}.${member}`
    if (classAccessorGetters.has(accKey) == 1) {
        const getMangled = classAccessorGetters.getString(accKey)
        const retType = funcRetTypes.has(getMangled) == 1 ? funcRetTypes.getString(getMangled) : "int"
        const llRet = ssTypeToLLVM(retType)
        const resR = nextReg()
        emitIR(`  ${resR} = call ${llRet} @${getMangled}(ptr ${objReg})`)
        return resR
    }
    if (classAccessorSetters.has(accKey) == 1) {
        println(`error: cannot read from write-only accessor '${className}.${member}'`)
        exit(1)
    }
    return ""
}

// D096: MEMBER_ACCESS dispatch — accessor getter wins, else plain field load.
function emitFieldOrAccessorGet(className: string, objReg: string, member: string): string {
    const acc = tryEmitAccessorGet(className, objReg, member)
    if (acc != "") { return acc }
    return emitFieldLoad(className, objReg, member)
}

// obj?.field — if obj is null, return default; otherwise access normally
function genOptionalMemberAccess(id: int, preObj: string = ""): string {
    const objId = nGetI1(id)
    const member = nGetS1(id)
    const objVal = preObj != "" ? preObj : genExpr(objId)
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

function genMemberAccess(id: int, preObj: string = ""): string {
    const member = nGetS1(id)
    const objId = nGetI1(id)
    const objKind = nGetKind(objId)
    // D095: STRING_LIT.name → string itself. Fires when cls was folded from
    // comptime IDENT to string literal in @methodOf body.
    if (objKind == "STRING_LIT" && member == "name") {
        return addStringConst(nGetS1(objId))
    }
    // Enum value access: EnumName.Variant
    if (objKind == "IDENT" && enumReady == 1) {
        const eName = nGetS1(objId)
        const enumKey = `${eName}.${member}`
        if (enumValues.has(enumKey) == 1) {
            if (enumTypes.has(eName) == 1) {
                return addStringConst(enumValues.getString(enumKey))
            }
            return enumValues.getString(enumKey)
        }
    }
    // D078: Static field access: ClassName.field
    if (objKind == "IDENT") {
        const sfKey = `${nGetS1(objId)}.${member}`
        if (staticFieldGlobals.has(sfKey) == 1) {
            const sfGlobal = staticFieldGlobals.getString(sfKey)
            const sfType = staticFieldTypes.getString(sfKey)
            const sfLLType = ssTypeToLLVM(sfType)
            const sfReg = nextReg()
            emitIR(`  ${sfReg} = load ${sfLLType}, ptr ${sfGlobal}, align 8`)
            return sfReg
        }
    }
    if (objKind == "THIS") {
        const thisReg = nextReg()
        emitIR(`  ${thisReg} = load ptr, ptr %this, align 8`)
        return emitFieldOrAccessorGet(currentClassName, thisReg, member)
    }
    // D082: Ref<T>.value read
    if (member == "value" && objKind == "IDENT") {
        const rvt = getVarType(nGetS1(objId))
        if (rvt.startsWith("Ref<") == 1) {
            const refObj = preObj != "" ? preObj : genExpr(objId)
            return emitRefValueRead(refObj, refElemType(rvt))
        }
    }
    const objVal = preObj != "" ? preObj : genExpr(objId)
    // D082: Ref<T>.value read (non-IDENT object, e.g., method call result)
    if (member == "value") {
        const roc = resolveObjClass(objId)
        if (roc == "Ref") {
            const rvt = inferType(objId)
            const rElem = rvt.startsWith("Ref<") == 1 ? refElemType(rvt) : "int"
            return emitRefValueRead(objVal, rElem)
        }
    }
    if (objKind == "IDENT") {
        const cn = getObjClass(nGetS1(objId))
        if (cn != "") { return emitFieldOrAccessorGet(cn, objVal, member) }
    }
    // Generic fallback: resolve class via resolveObjClass for nested access, calls, etc.
    const resolvedClass = resolveObjClass(objId)
    if (resolvedClass != "") { return emitFieldOrAccessorGet(resolvedClass, objVal, member) }
    return objVal
}

// D082: Read Ref<T>.value — call ss_refGet and convert i64 → element type
function emitRefValueRead(refReg: string, elemType: string): string {
    const raw = nextReg()
    emitIR(`  ${raw} = call i64 @ss_refGet(ptr ${refReg})`)
    return emitI64ToValue(raw, elemType)
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

