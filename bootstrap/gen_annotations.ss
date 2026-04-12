// gen_annotations.ss — Generic Annotation Dispatch
//
// D086: compiler provides ONE tool — annotation dispatch.
// annotationMapping(name, handler) in lib registers annotation→handler mapping.
// Comptime blocks generate factories + method wrappers (D087).
// This module collects annotations and dispatches handler calls with fn pointers.
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

function resetAnnotationState() {
    annHandlerMap = new Map()
    annClassNodeIds = []
    annClassAnnNames = []
    annClassAnnArgs = []
    annMethodClassIds = []
    annMethodFuncIds = []
    annMethodAnnNames = []
    annMethodAnnArgs = []
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
    const annParts = annList.split(",")
    for (ap in annParts) {
        const aId = parseInt(ap)
        if (aId <= 0 || nGetKind(aId) != "ANNOTATION") { continue }
        const annName = nGetS1(aId)
        if (annHandlerMap.has(annName) == 0) { continue }
        annClassNodeIds = annClassNodeIds.push(`${classId}`)
        annClassAnnNames = annClassAnnNames.push(annName)
        annClassAnnArgs = annClassAnnArgs.push(nGetS2(aId))
    }
    collectMethodAnnotations(classId)
}

function collectMethodAnnotations(classId: int) {
    const methodsBlockId = nGetI2(classId)
    if (methodsBlockId <= 0) { return }
    const mList = nGetList(methodsBlockId)
    if (mList == "") { return }
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
        }
    }
}

// ── Emission ──────────────────────────────────────────────────
// Comptime blocks generate factory + wrapper IR (via emit/registerFunction).
// This function dispatches handler calls with fn pointers at init time.

function emitAnnotationInits() {
    if (annClassAnnNames.length() == 0 && annMethodAnnNames.length() == 0) { return }

    // Call handlers for class annotations (before method annotations)
    let i = 0
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

    // Call handlers for method annotations
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
