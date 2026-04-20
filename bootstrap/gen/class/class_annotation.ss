// gen/class_annotation.ss — @methodOf / @derive / comptime block:注解 handler 驱动 + pending 方法队列

import { cloneAstNode, foldComptimeIdentsInTree, foldCtTypesInFuncDecl, resolveComptimeString } from "./class_comptime"
import { genClassMethod } from "./class_method"

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

// framework annotation handling 留给 Phase 3 eval core;sub-e 只承接符号
let annClassNodeIds: Array<string> = []
let annClassAnnNames: Array<string> = []

function registerAnnotation(annName: string, handlerFuncName: string) {
}

function collectClassAnnotations(classId: int) {
}

function emitAnnotationInits() {
}
