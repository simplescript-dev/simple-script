// gen_annotations.ss — Generic Annotation Dispatch
//
// D086: compiler provides ONE tool — annotation dispatch.
// annotationMapping(name, handler) in lib registers annotation→handler mapping.
// Compiler generates factories + method wrappers, calls handler with fn pointers.
// ALL framework logic (DI, routing, lifecycle) lives in lib handler functions.

import { nGetKind, nGetS1, nGetS2, nGetI2, nGetI4, nGetList } from "./parser"

// ── State ──────────────────────────────────────────────────────

// Handler registry: annName → handler function name
let annHandlerMap = new Map()

// Collected class annotation data (parallel arrays)
let annClassNodeIds: Array<string> = []
let annClassAnnNames: Array<string> = []
let annClassAnnArgs: Array<string> = []

// Collected method annotation data (parallel arrays)
let annMethodClassIds: Array<string> = []
let annMethodFuncIds: Array<string> = []
let annMethodAnnNames: Array<string> = []
let annMethodAnnArgs: Array<string> = []

// Set of all annotated class names (for factory dependency detection)
let annClassSet = new Map()

function resetAnnotationState() {
    annHandlerMap = new Map()
    annClassNodeIds = []
    annClassAnnNames = []
    annClassAnnArgs = []
    annMethodClassIds = []
    annMethodFuncIds = []
    annMethodAnnNames = []
    annMethodAnnArgs = []
    annClassSet = new Map()
}

// ── Registration (called from codegen.ss for annotationMapping() directives) ──

function registerAnnotation(annName: string, handlerFuncName: string) {
    annHandlerMap.set(annName, handlerFuncName)
}

// ── Collection ────────────────────────────────────────────────

function collectClassAnnotations(classId: int) {
    const annListId = nGetI4(classId)
    if (annListId <= 0) { return }
    if (nGetKind(annListId) != "ANNOTATION_LIST") { return }
    const annList = nGetList(annListId)
    if (annList == "") { return }

    const className = nGetS1(classId)
    let hasAnn = 0
    const annParts = annList.split(",")
    for (ap in annParts) {
        const aId = parseInt(ap)
        if (aId <= 0 || nGetKind(aId) != "ANNOTATION") { continue }
        const annName = nGetS1(aId)
        if (annHandlerMap.has(annName) == 0) { continue }
        annClassNodeIds = annClassNodeIds.push(`${classId}`)
        annClassAnnNames = annClassAnnNames.push(annName)
        annClassAnnArgs = annClassAnnArgs.push(nGetS2(aId))
        hasAnn = 1
    }
    if (hasAnn == 1) {
        annClassSet.set(className, "1")
    }
    collectMethodAnnotations(classId)
}

function collectMethodAnnotations(classId: int) {
    const methodsBlockId = nGetI2(classId)
    if (methodsBlockId <= 0) { return }
    const mList = nGetList(methodsBlockId)
    if (mList == "") { return }
    const className = nGetS1(classId)
    const mParts = mList.split(",")
    for (mp in mParts) {
        const mId = parseInt(mp)
        if (mId <= 0 || nGetKind(mId) != "FUNC_DECL") { continue }
        const mAnnId = nGetI4(mId)
        if (mAnnId <= 0) { continue }
        if (nGetKind(mAnnId) != "ANNOTATION_LIST") { continue }
        const mAnnList = nGetList(mAnnId)
        if (mAnnList == "") { continue }
        const mAnnParts = mAnnList.split(",")
        for (ma in mAnnParts) {
            const maId = parseInt(ma)
            if (maId <= 0 || nGetKind(maId) != "ANNOTATION") { continue }
            const mAnnName = nGetS1(maId)
            if (annHandlerMap.has(mAnnName) == 0) { continue }
            annMethodClassIds = annMethodClassIds.push(`${classId}`)
            annMethodFuncIds = annMethodFuncIds.push(`${mId}`)
            annMethodAnnNames = annMethodAnnNames.push(mAnnName)
            annMethodAnnArgs = annMethodAnnArgs.push(nGetS2(maId))
            annClassSet.set(className, "1")
        }
    }
}

// ── Factory generation ────────────────────────────────────────
// Generates a cached singleton factory: @__ann_factory_ClassName()
// Dependencies on other annotated classes resolved via their factories.

function emitFactory(className: string) {
    arrowDefs = `${arrowDefs}@__ann_cache_${className} = internal global ptr null\n`

    let body = `define ptr @__ann_factory_${className}() {\nentry:\n`
    body = `${body}  %cached = load ptr, ptr @__ann_cache_${className}\n`
    body = `${body}  %isNull = icmp eq ptr %cached, null\n`
    body = `${body}  br i1 %isNull, label %create, label %done\n`
    body = `${body}create:\n`

    const fieldStr = classFields.getString(className)
    let callArgs = ""
    if (fieldStr != "") {
        const fields = fieldStr.split(",")
        let argIdx = 0
        for (f in fields) {
            const fType = classFieldTypes.getString(`${className}.${f}`)
            let argVal = ""
            if (annClassSet.has(fType) == 1) {
                body = `${body}  %dep.${argIdx} = call ptr @__ann_factory_${fType}()\n`
                argVal = `ptr %dep.${argIdx}`
            } else {
                const llvmType = ssTypeToLLVM(fType)
                if (llvmType == "i32") { argVal = "i32 0" }
                else if (llvmType == "double") { argVal = "double 0.0" }
                else { argVal = "ptr null" }
            }
            if (callArgs == "") { callArgs = argVal } else { callArgs = `${callArgs}, ${argVal}` }
            argIdx = argIdx + 1
        }
    }

    if (callArgs == "") {
        body = `${body}  %inst = call ptr @${className}_new()\n`
    } else {
        body = `${body}  %inst = call ptr @${className}_new(${callArgs})\n`
    }
    body = `${body}  store ptr %inst, ptr @__ann_cache_${className}\n`
    body = `${body}  br label %done\n`
    body = `${body}done:\n`
    body = `${body}  %result = load ptr, ptr @__ann_cache_${className}\n`
    body = `${body}  ret ptr %result\n}\n\n`

    arrowDefs = `${arrowDefs}${body}`
}

// ── Method wrapper generation ─────────────────────────────────
// All wrappers have uniform signature: (ptr request, ptr response) -> ptr
// Wrapper calls factory to get/create instance, then calls method.

function emitMethodWrapper(wrapperName: string, className: string, funcDeclId: int) {
    let wrapBody = `define ptr @${wrapperName}(ptr %request, ptr %response) {\nentry:\n`
    wrapBody = `${wrapBody}  %inst = call ptr @__ann_factory_${className}()\n`

    let callArgs = `ptr %inst`
    let pvIdx = 0
    if (funcDeclId > 0) {
        const paramList = nGetList(funcDeclId)
        if (paramList != "") {
            const paramParts = paramList.split(",")
            for (pp in paramParts) {
                const pId = parseInt(pp)
                if (pId <= 0) { continue }
                const pAnnId = nGetI4(pId)
                if (pAnnId > 0 && nGetKind(pAnnId) == "ANNOTATION") {
                    // Any parameter annotation → extract value by param name from request
                    const pvStr = addStringConst(nGetS1(pId))
                    wrapBody = `${wrapBody}  %pv.${pvIdx} = call ptr @HttpServletRequest_getPathVariable(ptr %request, ptr ${pvStr})\n`
                    callArgs = `${callArgs}, ptr %pv.${pvIdx}`
                    pvIdx = pvIdx + 1
                } else {
                    const cpType = nGetS2(pId)
                    if (cpType == "HttpServletRequest") {
                        callArgs = `${callArgs}, ptr %request`
                    } else if (cpType == "HttpServletResponse") {
                        callArgs = `${callArgs}, ptr %response`
                    } else {
                        callArgs = `${callArgs}, ptr null`
                    }
                }
            }
        }
    }

    const methodName = nGetS1(funcDeclId)
    wrapBody = `${wrapBody}  %r = call ptr @${className}_${methodName}(${callArgs})\n`
    wrapBody = `${wrapBody}  ret ptr %r\n}\n\n`
    arrowDefs = `${arrowDefs}${wrapBody}`
}

// ── Emission ──────────────────────────────────────────────────

function emitAnnotationInits() {
    if (annClassAnnNames.length() == 0 && annMethodAnnNames.length() == 0) { return }

    // Generate factories for annotated classes (skip if comptime already generated them)
    let factoryGenerated = new Map()
    let i = 0
    while (i < annClassNodeIds.length()) {
        const classId = parseInt(annClassNodeIds[i])
        const className = nGetS1(classId)
        if (factoryGenerated.has(className) == 0) {
            if (funcRetTypes.has(`__ann_factory_${className}`) == 0) {
                emitFactory(className)
            }
            factoryGenerated.set(className, "1")
        }
        i = i + 1
    }
    // Also for classes that only have method annotations
    i = 0
    while (i < annMethodClassIds.length()) {
        const classId = parseInt(annMethodClassIds[i])
        const className = nGetS1(classId)
        if (factoryGenerated.has(className) == 0) {
            if (funcRetTypes.has(`__ann_factory_${className}`) == 0) {
                emitFactory(className)
            }
            factoryGenerated.set(className, "1")
        }
        i = i + 1
    }

    // Call handlers for class annotations (before method annotations)
    i = 0
    while (i < annClassAnnNames.length()) {
        const classId = parseInt(annClassNodeIds[i])
        const className = nGetS1(classId)
        const annName = annClassAnnNames[i]
        const annArg = annClassAnnArgs[i]
        const handlerName = annHandlerMap.getString(annName)

        const nameStr = addStringConst(annName)
        const classStr = addStringConst(className)
        const methStr = addStringConst("")
        const argStr = addStringConst(annArg)
        const fnPtr = nextReg()
        emitIR(`  ${fnPtr} = ptrtoint ptr @__ann_factory_${className} to i64`)
        const callR = nextReg()
        emitIR(`  ${callR} = call ptr @${handlerName}(ptr ${nameStr}, ptr ${classStr}, ptr ${methStr}, ptr ${argStr}, i64 ${fnPtr})`)

        i = i + 1
    }

    // Generate wrappers and call handlers for method annotations
    // Uses deterministic naming: __ann_wrapper_ClassName_methodName (D087 Phase 4b)
    // Skips wrapper generation when comptime already emitted it (funcRetTypes check)
    i = 0
    while (i < annMethodAnnNames.length()) {
        const classId = parseInt(annMethodClassIds[i])
        const funcId = parseInt(annMethodFuncIds[i])
        const className = nGetS1(classId)
        const methodName = nGetS1(funcId)
        const annName = annMethodAnnNames[i]
        const annArg = annMethodAnnArgs[i]
        const handlerName = annHandlerMap.getString(annName)

        const wrapperName = `__ann_wrapper_${className}_${methodName}`
        if (funcRetTypes.has(wrapperName) == 0) {
            emitMethodWrapper(wrapperName, className, funcId)
        }

        const nameStr = addStringConst(annName)
        const classStr = addStringConst(className)
        const methStr = addStringConst(methodName)
        const argStr = addStringConst(annArg)
        const wrapperPtr = nextReg()
        emitIR(`  ${wrapperPtr} = ptrtoint ptr @${wrapperName} to i64`)
        const mcallR = nextReg()
        emitIR(`  ${mcallR} = call ptr @${handlerName}(ptr ${nameStr}, ptr ${classStr}, ptr ${methStr}, ptr ${argStr}, i64 ${wrapperPtr})`)

        i = i + 1
    }
}
