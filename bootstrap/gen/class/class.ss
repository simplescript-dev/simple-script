// gen/class.ss — Class codegen 分发器 + 状态 + RC 分派 + 基础查询
// 分发器仅分发,细项实现在 class_register/class_comptime/class_annotation/class_method/class_member。

import { emitClassStruct, emitClassConstructor } from "./class_register"
import { emitClassComptimeMethods, runComptimeAnnotationCall } from "./class_annotation"
import { genClassMethod, genNamedConstructorArgs, genCtorArgsWithDefaults } from "./class_method"
import { emitFieldLoad, genMemberAccess, genOptionalMemberAccess } from "./class_member"
import { emitClassVtableConst, emitClassDropFieldsFn, emitClassConstructorReuse, genAutoToJson, emitClassDtorRegister, emitClassTypeInfo } from "../gen_type_ops"
import { genGenericNewExpr } from "../gen_generic_class"

// ── Class state ──────────────────────────────────────────────

let classFields = ""     // "ClassName" -> "field1,field2,..."
let classFieldTypes = "" // "ClassName.field" -> "type" (stripped — D067 codegen invariant)
let classFieldDefaultIds = "" // D149: "ClassName.field" -> "<defExprNodeId>" string (PARAM I1 slot)
// I021-requestbody-nested-optional + D067 — 字段 nullable metadata,emit 反序列化时
//   恢复 nullable 标记给 emitDeserializeForType。classFieldTypes 保 stripped 不变(D067
//   codegen invariant);本 Map 局部 metadata 单独 track,反序列化路径 emitClassDeserializeFn
//   字段循环查此 Map 决定是否走 nullable case。
let classFieldNullable = "" // "ClassName.field" -> "1" (if field declared as T?)
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
    classFieldDefaultIds = Map()
    classFieldNullable = Map()
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

// Returns 1 if typeName is an interface (declared with `interface X { ... }`),
// 0 if it's a concrete class. Used by codegen to dispatch deep_clone /
// shallow_clone through the obj's TypeInfo vtable for interface-typed fields
// (no static `ss_deep_clone_<Iface>` exists — only concrete classes have one).
function isInterfaceType(typeName: string): int {
    if (ifaceMethodsCG.has(typeName) == 1 && classFields.has(typeName) == 0) { return 1 }
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

// ── Class decl dispatcher ─────────────────────────────────────

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

// ── New expression dispatcher ─────────────────────────────────

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
        // D149: 全 default 空 ctor — fields with default expr use that expr;
        // remaining fields fall back to LLVM zero. Unified with partial path via helper.
        args = genCtorArgsWithDefaults(className, Map(), Map())
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

// ── Obj/class tracking + field index ──────────────────────────

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
