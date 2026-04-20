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

// L2ζ/L2η: fill namesMap[keyPrefix] with annotation name CSV. When withArgs=1,
// also fill argsMap["${keyPrefix}.${annName}"] with STRING_LIT arg CSV.
// withArgs=0 path ignores argsMap entirely — safe to pass namesMap as placeholder.
function extractAnnotationsReflection(annListId: int, namesMap: Map, argsMap: Map, keyPrefix: string, withArgs: int) {
    if (annListId <= 0 || nGetKind(annListId) != "ANNOTATION_LIST") { return }
    const anns = nGetList(annListId)
    if (anns == "") { return }
    let names = ""
    for (ap in anns.split(",")) {
        const aId = parseInt(ap)
        if (aId <= 0 || nGetKind(aId) != "ANNOTATION") { continue }
        const annName = nGetS1(aId)
        names = listAppendStr(names, annName)
        if (withArgs == 0) { continue }
        const argsCsv = nGetList(aId)
        if (argsCsv == "") { continue }
        let argVals = ""
        for (arp in argsCsv.split(",")) {
            const argId = parseInt(arp)
            if (argId > 0 && nGetKind(argId) == "STRING_LIT") {
                argVals = listAppendStr(argVals, nGetS1(argId))
            }
        }
        if (argVals != "") { argsMap.set(`${keyPrefix}.${annName}`, argVals) }
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
                        extractAnnotationsReflection(parseInt(fAnnListRaw), classFieldAnnotations, classFieldAnnotationArgs, `${name}.${fName}`, 1)
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
                    } else {
                        // L2κ: non-abstract FUNC_DECL's I4 holds ANNOTATION_LIST id
                        // (parser.ss:273 via attachAnnotations); abstract overwrites
                        // I4 with 1, so abstract method annotations cannot be read here.
                        extractAnnotationsReflection(nGetI4(mId), classMethodAnnotations, classMethodAnnotations, `${name}.${mName}`, 0)
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
                    // L2κ: accessor get/set share the same mName, so their
                    // annotations collapse onto one classMethodAnnotations key.
                    // Per-kind annotation reflection for accessors remains future work.
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
