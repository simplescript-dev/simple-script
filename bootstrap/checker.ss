// SimpleScript Bootstrap Type Checker
// Core: initialization, scope management, function registry, error reporting, entry point.
// Statement/expression checking logic in check_stmts.ss.

import { nGetKind, nGetS1, nGetS2, nGetS3, nGetI1, nGetI2, nGetI3, nGetI4, nGetList, nGetLine, nGetCol, getLineOffset, classTypeParams } from "./parser"
import { getSourceLine } from "./lexer"
import { checkStmtList } from "./check_stmts"

// ── Scope + function registry ─────────────────────────────────

let scopeId = 0
let currentScope = 0
let scopeParent = ""  // Map: "scopeId" -> "parentScopeId" (chain-based scope)
let varNames = ""     // "scopeId:name" -> "type"
let varConst = ""     // "scopeId:name" -> "const" if const
let funcNames = ""    // "funcName" -> "retType"
let ifaceMethods = ""
let funcParamMin = ""  // "funcName" -> min args (required params)
let funcParamMax = ""  // "funcName" -> max args (total params)
let funcReady = 0
let errorCount = 0     // collected error count (Phase 3: multi-error reporting)
let scopeVarNames = "" // Map: "scopeId" -> comma-separated var names (for suggestions)
let allFuncNameList = "" // comma-separated function names (for suggestions)
let classConsMin = ""        // "ClassName" -> min constructor args
let classConsMax = ""        // "ClassName" -> max constructor args
let checkerClassParents = "" // "ClassName" -> parent class name
let methodParamMin = ""      // "ClassName.method" -> min method args
let methodParamMax = ""      // "ClassName.method" -> max method args
let currentCheckerClass = "" // current class context (for this.method() resolution)
let constFields = ""         // "ClassName.fieldName" -> "1" if const field
let checkerFieldTypes = ""   // "ClassName.fieldName" -> type string
let checkerClassFields = ""  // "ClassName" -> "field1,field2,..." (ordered field list)

function initChecker() {
    if (funcReady == 1) { return }
    varNames = Map()
    varConst = Map()
    funcNames = Map()
    ifaceMethods = Map()
    scopeParent = Map()
    funcParamMin = Map()
    funcParamMax = Map()
    scopeId = 0
    currentScope = 0
    scopeVarNames = Map()
    allFuncNameList = ""
    classConsMin = Map()
    classConsMax = Map()
    checkerClassParents = Map()
    methodParamMin = Map()
    methodParamMax = Map()
    currentCheckerClass = ""
    constFields = Map()
    checkerFieldTypes = Map()
    checkerClassFields = Map()
    // Built-in class: Map
    classConsMin.set("Map", "0")
    classConsMax.set("Map", "0")
    registerMethodParams("Map", "set", 2, 2)
    registerMethodParams("Map", "get", 1, 1)
    registerMethodParams("Map", "getString", 1, 1)
    registerMethodParams("Map", "has", 1, 1)
    registerMethodParams("Map", "delete", 1, 1)
    registerMethodParams("Map", "size", 0, 0)
    registerMethodParams("Map", "keys", 0, 0)
    // Built-in class: Set (Map wrapper, D021)
    classConsMin.set("Set", "0")
    classConsMax.set("Set", "0")
    registerMethodParams("Set", "add", 1, 1)
    registerMethodParams("Set", "has", 1, 1)
    registerMethodParams("Set", "remove", 1, 1)
    registerMethodParams("Set", "size", 0, 0)
    registerMethodParams("Set", "values", 0, 0)
    // Built-in namespace: Math (registered in classConsMin for method lookup resolution)
    classConsMin.set("Math", "0")
    classConsMax.set("Math", "0")
    registerMethodParams("Math", "sqrt", 1, 1)
    registerMethodParams("Math", "abs", 1, 1)
    registerMethodParams("Math", "floor", 1, 1)
    registerMethodParams("Math", "ceil", 1, 1)
    registerMethodParams("Math", "round", 1, 1)
    registerMethodParams("Math", "log", 1, 1)
    registerMethodParams("Math", "sin", 1, 1)
    registerMethodParams("Math", "cos", 1, 1)
    registerMethodParams("Math", "random", 0, 0)
    registerMethodParams("Math", "pow", 2, 2)
    registerMethodParams("Math", "min", 2, 2)
    registerMethodParams("Math", "max", 2, 2)
    // Built-in functions (synced with codegen.ss funcRetTypes)
    const builtins = "println,print,readLine,readFile,writeFile,appendFile,args,arg,exit,system,parseInt,parseDouble,Map,Set,timeMs,timeUnix,fileSize,getenv,listDir,sha256,fromCharCode,charCodeAt,base64Encode,base64Decode,tcpListen,tcpAccept,tcpRead,tcpWrite,tcpClose,mkdir,mkdirp,fileExists,removeFile,renameFile"
    const parts = builtins.split(",")
    for (name in parts) {
        funcNames.set(name, "builtin")
    }
    allFuncNameList = builtins
    // Built-in namespaces (accessed as Math.sqrt() etc.)
    defineVar("Math", "namespace", 0)
    // Built-in param counts
    const zeroArgFns = "readLine,args,Map,timeMs,timeUnix"
    const za = zeroArgFns.split(",")
    for (z in za) {
        funcParamMin.set(z, "0")
        funcParamMax.set(z, "0")
    }
    // println/print are variadic (genPrintCall concatenates with spaces)
    funcParamMin.set("println", "0")
    funcParamMax.set("println", "99")
    funcParamMin.set("print", "0")
    funcParamMax.set("print", "99")
    const oneArgFns = "readFile,arg,exit,system,parseInt,parseDouble,getenv,listDir,sha256,fromCharCode,base64Encode,base64Decode,tcpListen,tcpAccept,tcpRead,tcpClose,mkdir,mkdirp,fileExists,removeFile,fileSize"
    const oa = oneArgFns.split(",")
    for (o in oa) {
        funcParamMin.set(o, "1")
        funcParamMax.set(o, "1")
    }
    const twoArgFns = "writeFile,appendFile,tcpWrite,renameFile,charCodeAt"
    const ta = twoArgFns.split(",")
    for (t in ta) {
        funcParamMin.set(t, "2")
        funcParamMax.set(t, "2")
    }
    funcReady = 1
}

function pushScope() {
    scopeId = scopeId + 1
    scopeParent.set(`${scopeId}`, `${currentScope}`)
    currentScope = scopeId
}

function popScope() {
    currentScope = parseInt(scopeParent.getString(`${currentScope}`))
}

function defineVar(name: string, varType: string, isConst: int) {
    const key = `${currentScope}:${name}`
    varNames.set(key, varType)
    if (isConst == 1) {
        varConst.set(key, "const")
    }
    const scopeKey = `${currentScope}`
    if (scopeVarNames.has(scopeKey) == 1) {
        scopeVarNames.set(scopeKey, `${scopeVarNames.getString(scopeKey)},${name}`)
    } else {
        scopeVarNames.set(scopeKey, name)
    }
}

function lookupVar(name: string): string {
    let s = currentScope
    while (s >= 0) {
        const key = `${s}:${name}`
        if (varNames.has(key) == 1) {
            return varNames.getString(key)
        }
        if (s == 0) { break }
        s = parseInt(scopeParent.getString(`${s}`))
    }
    return ""
}

function isVarConst(name: string): int {
    let s = currentScope
    while (s >= 0) {
        const key = `${s}:${name}`
        if (varNames.has(key) == 1) {
            return varConst.has(key)
        }
        if (s == 0) { break }
        s = parseInt(scopeParent.getString(`${s}`))
    }
    return 0
}

// Infer class name from an expression node (for const field checking)
function inferCheckerClass(nodeId: int): string {
    if (nodeId <= 0) { return "" }
    const kind = nGetKind(nodeId)
    if (kind == "IDENT") {
        return lookupVar(nGetS1(nodeId))
    }
    if (kind == "THIS") { return currentCheckerClass }
    if (kind == "NEW_EXPR") { return nGetS1(nodeId) }
    if (kind == "MEMBER_ACCESS") {
        const objClass = inferCheckerClass(nGetI1(nodeId))
        if (objClass == "") { return "" }
        const fieldKey = `${objClass}.${nGetS1(nodeId)}`
        if (checkerFieldTypes.has(fieldKey) == 1) {
            return checkerFieldTypes.getString(fieldKey)
        }
        return ""
    }
    if (kind == "CALL") {
        const fname = nGetS1(nodeId)
        if (funcNames.has(fname) == 1) {
            return funcNames.getString(fname)
        }
        return ""
    }
    return ""
}

function checkInterfaceImpl(classNodeId: int, className: string, implList: string, classMethods: string) {
    // Scan comma-separated interface names without for-in (avoids i64/ptr issue)
    let remaining = implList
    while (remaining != "") {
        let iface = remaining
        const commaIdx = remaining.indexOf(",")
        if (commaIdx >= 0) {
            iface = remaining.substring(0, commaIdx)
            remaining = remaining.substring(commaIdx + 1, remaining.length() - commaIdx - 1)
        } else {
            remaining = ""
        }
        if (ifaceMethods.has(iface) == 1) {
            const required = ifaceMethods.getString(iface)
            if (required != "") {
                let remReq = required
                while (remReq != "") {
                    let req = remReq
                    const ci = remReq.indexOf(",")
                    if (ci >= 0) {
                        req = remReq.substring(0, ci)
                        remReq = remReq.substring(ci + 1, remReq.length() - ci - 1)
                    } else {
                        remReq = ""
                    }
                    if (classMethods.contains(`,${req},`) == 0) {
                        checkerError(`class '${className}' missing method '${req}' required by interface '${iface}'`, nGetLine(classNodeId), nGetCol(classNodeId))
                    }
                }
            }
        }
    }
}

function defineFunc(name: string, retType: string) {
    if (funcNames.has(name) == 0) {
        allFuncNameList = listAppendStr(allFuncNameList, name)
    }
    funcNames.set(name, retType)
}

function lookupFunc(name: string): int {
    return funcNames.has(name)
}

function defineFuncParams(name: string, minArgs: int, maxArgs: int) {
    if (funcParamMin.has(name) == 1) {
        const existMin = parseInt(funcParamMin.getString(name))
        const existMax = parseInt(funcParamMax.getString(name))
        if (minArgs < existMin) { funcParamMin.set(name, `${minArgs}`) }
        if (maxArgs > existMax) { funcParamMax.set(name, `${maxArgs}`) }
    } else {
        funcParamMin.set(name, `${minArgs}`)
        funcParamMax.set(name, `${maxArgs}`)
    }
}

function registerMethodParams(className: string, methodName: string, minArgs: int, maxArgs: int) {
    const key = `${className}.${methodName}`
    methodParamMin.set(key, `${minArgs}`)
    methodParamMax.set(key, `${maxArgs}`)
}

// Walk parent chain to find method param counts. Returns "min,max" or "".
function lookupMethodParams(className: string, methodName: string): string {
    let cls = className
    while (cls != "") {
        const key = `${cls}.${methodName}`
        if (methodParamMin.has(key) == 1) {
            return `${methodParamMin.getString(key)},${methodParamMax.getString(key)}`
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    return ""
}

// Walk parent chain and sum constructor params (own + inherited). Returns "min,max".
function totalConstructorParams(className: string): string {
    let totalMin = 0
    let totalMax = 0
    let cls = className
    while (cls != "") {
        if (classConsMin.has(cls) == 1) {
            totalMin = totalMin + parseInt(classConsMin.getString(cls))
            totalMax = totalMax + parseInt(classConsMax.getString(cls))
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    return `${totalMin},${totalMax}`
}

// Count min/max required params from a PARAM node list. Returns "min,max".
function countParamRange(paramListStr: string): string {
    let pMin = 0
    let pMax = 0
    if (paramListStr != "") {
        const parts = paramListStr.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                pMax = pMax + 1
                if (nGetI1(pId) <= 0 && nGetI2(pId) <= 0) {
                    pMin = pMin + 1
                }
            }
        }
    }
    return `${pMin},${pMax}`
}

// Emit checker error if argCount is outside [minArgs, maxArgs].
function checkArgCount(label: string, name: string, argCount: int, minArgs: int, maxArgs: int, line: int, col: int) {
    if (argCount < minArgs || argCount > maxArgs) {
        if (minArgs == maxArgs) {
            checkerError(`${label} '${name}' expects ${minArgs} arguments, got ${argCount}`, line, col)
        } else {
            checkerError(`${label} '${name}' expects ${minArgs}-${maxArgs} arguments, got ${argCount}`, line, col)
        }
    }
}

function countArgs(listStr: string): int {
    if (listStr == "") { return 0 }
    let count = 0
    const parts = listStr.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0) { count = count + 1 }
    }
    return count
}

function hasSpreadArg(listStr: string): int {
    if (listStr == "") { return 0 }
    const parts = listStr.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0 && nGetKind(argId) == "SPREAD_ELEM") { return 1 }
    }
    return 0
}

// ── Error reporting ───────────────────────────────────────────

function checkerError(msg: string, line: int, col: int, suggestion: string = "") {
    errorCount = errorCount + 1
    if (errorCount > 20) { return }
    if (line <= 0) {
        println(`error: ${msg}`)
        println("")
        return
    }
    const rawLine = line + getLineOffset()
    const srcLine = getSourceLine(rawLine)
    if (srcLine == "") {
        println(`error at line ${line}: ${msg}`)
        println("")
        return
    }
    const lineStr = `${line}`
    const gutter = " ".repeat(lineStr.length())
    println(`error: ${msg}`)
    println(`${gutter}--> line ${line}:${col}`)
    println(`${gutter} |`)
    println(`${lineStr} | ${srcLine}`)
    if (col > 0) {
        println(`${gutter} | ${" ".repeat(col - 1)}^`)
    }
    if (suggestion != "") {
        println(`${gutter} = help: did you mean '${suggestion}'?`)
    }
    println("")
}

// ── Public API ────────────────────────────────────────────────

function check(rootId: int): int {
    initChecker()
    errorCount = 0
    const kind = nGetKind(rootId)
    if (kind != "PROGRAM") {
        println("fatal: expected PROGRAM node, got " + kind)
        exit(1)
    }
    const stmtList = nGetList(rootId)
    if (stmtList != "") {
        const p1 = stmtList.split(",")
        for (p in p1) {
            const s = parseInt(p)
            if (s <= 0) { continue }
            const sk = nGetKind(s)
            if (sk == "FUNC_DECL") {
                const fname = nGetS1(s)
                defineFunc(fname, nGetS2(s))
                const fRange = countParamRange(nGetList(s))
                const fComma = fRange.indexOf(",")
                defineFuncParams(fname, parseInt(fRange.substring(0, fComma)), parseInt(fRange.substring(fComma + 1, fRange.length() - fComma - 1)))
            }
            if (sk == "VAR_DECL") {
                const vname = nGetS1(s)
                const vkind = nGetS2(s)
                let vtype = nGetS3(s)
                if (vtype == "") { vtype = "auto" }
                defineVar(vname, vtype, vkind == "CONST")
            }
            if (sk == "DESTRUCTURE_ARRAY" || sk == "DESTRUCTURE_OBJECT") {
                const dNames = nGetS1(s)
                const dKind = nGetS2(s)
                const dParts = dNames.split(",")
                for (dn in dParts) {
                    defineVar(dn, "auto", dKind == "CONST")
                }
            }
            if (sk == "CLASS_DECL") {
                const className = nGetS1(s)
                defineVar(className, "class", 0)
                // Register parent class (strip generic type args: "Box<int>" → "Box")
                let parentName = nGetS2(s)
                if (parentName != "") {
                    const ltIdx = parentName.indexOf("<")
                    if (ltIdx > 0) { parentName = parentName.substring(0, ltIdx) }
                    checkerClassParents.set(className, parentName)
                }
                // Register field const status, types, and ordered field list
                const fieldList = nGetList(s)
                let fieldNameList = ""
                if (fieldList != "") {
                    const flds = fieldList.split(",")
                    for (f in flds) {
                        const fId = parseInt(f)
                        if (fId > 0 && nGetKind(fId) == "PARAM") {
                            const fName = nGetS1(fId)
                            const fType = nGetS2(fId)
                            checkerFieldTypes.set(`${className}.${fName}`, fType)
                            fieldNameList = listAppendStr(fieldNameList, fName)
                            if (nGetS3(fId) == "const") {
                                constFields.set(`${className}.${fName}`, "1")
                            }
                        }
                    }
                }
                checkerClassFields.set(className, fieldNameList)
                // Register constructor params (CLASS_DECL List = constructor PARAM nodes)
                if (classTypeParams(s) != "") {
                    // Generic class: accept any arg count (specialized at codegen)
                    classConsMin.set(className, "0")
                    classConsMax.set(className, "99")
                } else {
                    const consRange = countParamRange(nGetList(s))
                    const consComma = consRange.indexOf(",")
                    classConsMin.set(className, consRange.substring(0, consComma))
                    classConsMax.set(className, consRange.substring(consComma + 1, consRange.length() - consComma - 1))
                }
                // Register method params
                const clsMethodsBlock = nGetI2(s)
                if (clsMethodsBlock > 0) {
                    const clsML = nGetList(clsMethodsBlock)
                    if (clsML != "") {
                        const clsMS = clsML.split(",")
                        for (cm in clsMS) {
                            const cmId = parseInt(cm)
                            if (cmId > 0 && nGetKind(cmId) == "FUNC_DECL") {
                                const mRange = countParamRange(nGetList(cmId))
                                const mComma = mRange.indexOf(",")
                                registerMethodParams(className, nGetS1(cmId), parseInt(mRange.substring(0, mComma)), parseInt(mRange.substring(mComma + 1, mRange.length() - mComma - 1)))
                            }
                        }
                    }
                }
            }
            if (sk == "ENUM_DECL") {
                defineVar(nGetS1(s), "enum", 0)
            }
            if (sk == "INTERFACE_DECL") {
                const ifName = nGetS1(s)
                const ml = nGetList(s)
                let methodNames = ""
                if (ml != "") {
                    const ms = ml.split(",")
                    for (m in ms) {
                        const mId = parseInt(m)
                        if (mId > 0) {
                            methodNames = listAppendStr(methodNames, nGetS1(mId))
                        }
                    }
                }
                ifaceMethods.set(ifName, methodNames)
                defineVar(ifName, "interface", 0)
            }
        }
    }
    // Pass 2: check all statements
    checkStmtList(stmtList)
    // Report collected errors
    if (errorCount > 0) {
        if (errorCount == 1) {
            println("aborting due to 1 error")
        } else if (errorCount <= 20) {
            println(`aborting due to ${errorCount} errors`)
        } else {
            println(`aborting due to ${errorCount} errors (20 shown)`)
        }
        exit(1)
    }
    return 1
}


