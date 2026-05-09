// gen/class_register.ss — Class/static field 注册 + 继承解析 + struct/ctor/annotation reflection emit

import { splitParentType, preRegisterSpecializedClass } from "../gen_generic_class"
import { emitClassCtorBody } from "../gen_type_ops"

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
                    if (fType != strippedType) {
                        classFieldNullable.set(`${name}.${fName}`, "1")
                    }
                    // D149: track field default value expr id for partial named arg ctor + 全 default 路径
                    if (nGetI1(pId) > 0) {
                        classFieldDefaultIds.set(`${name}.${fName}`, `${nGetI1(pId)}`)
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
                    // D071: track abstract methods (I4=1 sentinel, overwrites ANNOTATION_LIST)
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
                    // D120 §Phase 1 accessor Meta: accessor get/set 在 interpBuildTypeInfo 经
                    // MTH|<cls>.<mth>.get / .set 后缀分离,两 FUNC_DECL 独立 MethodMeta。
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
    // Track interface implementations — D161 Phase 2: 走 ifaceParents 链注册到所有祖先接口,
    // 父接口 dispatcher switch 含 implementor 让 parent type upcast `let p: Parent = new Impl()`
    // 走 vtable 派发命中(否则 generateInterfaceDispatchers 父接口 switch 无 case 落 __default 返 0)。
    // visited 守 self-loop / cycle(`interface A extends A` 编程错误防 while 永不退出 hang)。
    const implList = nGetS3(id)
    if (implList != "") {
        const implParts = implList.split(",")
        for (iface in implParts) {
            if (iface == "") { continue }
            let visited = new Map()
            let curIface = iface
            while (curIface != "") {
                if (visited.has(curIface) == 1) { break }
                visited.set(curIface, "1")
                const prev = ifaceImplementors.has(curIface) == 1 ? ifaceImplementors.getString(curIface) : ""
                const wrappedPrev = `,${prev},`
                if (wrappedPrev.contains(`,${name},`) == 0) {
                    ifaceImplementors.set(curIface, listAppendStr(prev, name))
                }
                curIface = ifaceParents.has(curIface) == 1 ? ifaceParents.getString(curIface) : ""
            }
        }
    }
}

// D161 Phase 5 — propagate ifaceImplementors up the ifaceParents chain.
// registerClass walks the chain at class registration time, but cycle-driven
// import inversion (sql.ss ↔ jdbc.ss: jdbc.ss content gets inlined before
// sql.ss own content because resolveInner appends imported content first
// and sql.ss imports jdbc.ss for DriverManager_getConnection) can place a
// CLASS_DECL implementing a child interface BEFORE the child's
// INTERFACE_DECL is processed — at which point ifaceParents is empty and
// the walk silently misses the parent registration. This post-pass runs
// after ALL interface and class registration is done, walking ifaceParents
// once more to fill in missed propagations. Idempotent (dedupe via wrapped
// CSV contains check).
function propagateIfaceImplementorsToParents() {
    const ifaceList = ifaceParents.keys()
    for (iface in ifaceList) {
        if (iface == "") { continue }
        const impls = ifaceImplementors.has(iface) == 1 ? ifaceImplementors.getString(iface) : ""
        if (impls == "") { continue }
        const implParts = impls.split(",")
        let visited = new Map()
        let curParent = ifaceParents.has(iface) == 1 ? ifaceParents.getString(iface) : ""
        while (curParent != "") {
            if (visited.has(curParent) == 1) { break }
            visited.set(curParent, "1")
            const parentImpls = ifaceImplementors.has(curParent) == 1 ? ifaceImplementors.getString(curParent) : ""
            let mergedParent = parentImpls
            let wrapped = `,${parentImpls},`
            for (impl in implParts) {
                if (impl == "") { continue }
                if (wrapped.contains(`,${impl},`) == 0) {
                    mergedParent = listAppendStr(mergedParent, impl)
                    wrapped = `,${mergedParent},`
                }
            }
            ifaceImplementors.set(curParent, mergedParent)
            curParent = ifaceParents.has(curParent) == 1 ? ifaceParents.getString(curParent) : ""
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
                // D149: inherit field default value expr id (parallel to classFieldTypes copy)
                if (classFieldDefaultIds.has(`${parentCls}.${pf}`) == 1) {
                    classFieldDefaultIds.set(`${cls}.${pf}`, classFieldDefaultIds.getString(`${parentCls}.${pf}`))
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
