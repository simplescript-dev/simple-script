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
let funcParamTypes = ""     // "funcName:paramIndex" -> type string
let funcOverloaded = ""     // "funcName" -> "1" if overloaded (skip type check)
let methodParamTypes = ""   // "ClassName.methodName:paramIndex" -> type string
let methodRetTypes = ""     // "ClassName.methodName" -> return type string

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
    funcParamTypes = Map()
    funcOverloaded = Map()
    methodParamTypes = Map()
    methodRetTypes = Map()
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
    registerMethodParams("Math", "tan", 1, 1)
    registerMethodParams("Math", "asin", 1, 1)
    registerMethodParams("Math", "acos", 1, 1)
    registerMethodParams("Math", "atan", 1, 1)
    registerMethodParams("Math", "atan2", 2, 2)
    registerMethodParams("Math", "exp", 1, 1)
    registerMethodParams("Math", "log10", 1, 1)
    registerMethodParams("Math", "log2", 1, 1)
    registerMethodParams("Math", "trunc", 1, 1)
    registerMethodParams("Math", "sign", 1, 1)
    registerMethodParams("Math", "hypot", 2, 2)
    registerMethodParams("Math", "cbrt", 1, 1)
    registerMethodParams("Math", "fmod", 2, 2)
    registerMethodParams("Math", "randomInt", 1, 1)
    // Map method return types
    methodRetTypes.set("Map.set", "void")
    methodRetTypes.set("Map.getString", "string")
    methodRetTypes.set("Map.has", "int")
    methodRetTypes.set("Map.delete", "void")
    methodRetTypes.set("Map.size", "int")
    methodRetTypes.set("Map.keys", "Array<string>")
    // Set method return types
    methodRetTypes.set("Set.add", "void")
    methodRetTypes.set("Set.has", "int")
    methodRetTypes.set("Set.remove", "void")
    methodRetTypes.set("Set.size", "int")
    methodRetTypes.set("Set.values", "string")
    // Math method return types (all double except randomInt → int)
    const mathDoubleMethods = "sqrt,abs,floor,ceil,round,log,sin,cos,tan,asin,acos,atan,exp,log10,log2,trunc,sign,cbrt,random,pow,min,max,atan2,hypot,fmod"
    const mdParts = mathDoubleMethods.split(",")
    for (md in mdParts) {
        methodRetTypes.set(`Math.${md}`, "double")
    }
    methodRetTypes.set("Math.randomInt", "int")
    // Built-in type: string (pseudo-class for method dispatch)
    classConsMin.set("string", "0")
    classConsMax.set("string", "0")
    registerMethodParams("string", "charAt", 1, 1)
    registerMethodParams("string", "charCodeAt", 1, 1)
    registerMethodParams("string", "substring", 2, 2)
    registerMethodParams("string", "indexOf", 1, 1)
    registerMethodParams("string", "contains", 1, 1)
    registerMethodParams("string", "startsWith", 1, 1)
    registerMethodParams("string", "endsWith", 1, 1)
    registerMethodParams("string", "replace", 2, 2)
    registerMethodParams("string", "split", 1, 1)
    registerMethodParams("string", "trim", 0, 0)
    registerMethodParams("string", "toUpperCase", 0, 0)
    registerMethodParams("string", "toLowerCase", 0, 0)
    registerMethodParams("string", "repeat", 1, 1)
    registerMethodParams("string", "padStart", 2, 2)
    registerMethodParams("string", "padEnd", 2, 2)
    registerMethodParams("string", "length", 0, 0)
    registerMethodParams("string", "includes", 1, 1)
    // String method param types
    methodParamTypes.set("string.charAt:0", "int")
    methodParamTypes.set("string.charCodeAt:0", "int")
    methodParamTypes.set("string.substring:0", "int")
    methodParamTypes.set("string.substring:1", "int")
    methodParamTypes.set("string.indexOf:0", "string")
    methodParamTypes.set("string.contains:0", "string")
    methodParamTypes.set("string.startsWith:0", "string")
    methodParamTypes.set("string.endsWith:0", "string")
    methodParamTypes.set("string.replace:0", "string")
    methodParamTypes.set("string.replace:1", "string")
    methodParamTypes.set("string.split:0", "string")
    methodParamTypes.set("string.repeat:0", "int")
    methodParamTypes.set("string.padStart:0", "int")
    methodParamTypes.set("string.padStart:1", "string")
    methodParamTypes.set("string.padEnd:0", "int")
    methodParamTypes.set("string.padEnd:1", "string")
    methodParamTypes.set("string.includes:0", "string")
    // String method return types
    methodRetTypes.set("string.charAt", "string")
    methodRetTypes.set("string.charCodeAt", "int")
    methodRetTypes.set("string.substring", "string")
    methodRetTypes.set("string.indexOf", "int")
    methodRetTypes.set("string.contains", "int")
    methodRetTypes.set("string.startsWith", "int")
    methodRetTypes.set("string.endsWith", "int")
    methodRetTypes.set("string.replace", "string")
    methodRetTypes.set("string.split", "Array<string>")
    methodRetTypes.set("string.trim", "string")
    methodRetTypes.set("string.toUpperCase", "string")
    methodRetTypes.set("string.toLowerCase", "string")
    methodRetTypes.set("string.repeat", "string")
    methodRetTypes.set("string.padStart", "string")
    methodRetTypes.set("string.padEnd", "string")
    methodRetTypes.set("string.length", "int")
    methodRetTypes.set("string.includes", "int")
    // Built-in type: Array (pseudo-class for method dispatch)
    classConsMin.set("Array", "0")
    classConsMax.set("Array", "99")
    registerMethodParams("Array", "push", 1, 1)
    registerMethodParams("Array", "slice", 2, 2)
    registerMethodParams("Array", "concat", 1, 1)
    registerMethodParams("Array", "reverse", 0, 0)
    registerMethodParams("Array", "sort", 0, 0)
    registerMethodParams("Array", "includes", 1, 1)
    registerMethodParams("Array", "indexOf", 1, 1)
    registerMethodParams("Array", "length", 0, 0)
    registerMethodParams("Array", "join", 1, 1)
    registerMethodParams("Array", "map", 1, 1)
    registerMethodParams("Array", "filter", 1, 1)
    registerMethodParams("Array", "forEach", 1, 1)
    registerMethodParams("Array", "find", 1, 1)
    registerMethodParams("Array", "findIndex", 1, 1)
    registerMethodParams("Array", "some", 1, 1)
    registerMethodParams("Array", "every", 1, 1)
    registerMethodParams("Array", "reduce", 2, 2)
    // Array method return types
    methodRetTypes.set("Array.push", "Array")
    methodRetTypes.set("Array.slice", "Array")
    methodRetTypes.set("Array.concat", "Array")
    methodRetTypes.set("Array.reverse", "Array")
    methodRetTypes.set("Array.sort", "Array")
    methodRetTypes.set("Array.includes", "int")
    methodRetTypes.set("Array.indexOf", "int")
    methodRetTypes.set("Array.length", "int")
    methodRetTypes.set("Array.join", "string")
    methodRetTypes.set("Array.findIndex", "int")
    methodRetTypes.set("Array.some", "int")
    methodRetTypes.set("Array.every", "int")
    methodRetTypes.set("Array.map", "Array")
    methodRetTypes.set("Array.filter", "Array")
    methodRetTypes.set("Array.forEach", "void")
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

// Normalize generic type to base class name for method dispatch (Array<int> → Array)
function resolveCheckerClass(cls: string): string {
    if (cls == "" || classConsMin.has(cls) == 1) { return cls }
    const base = baseTypeName(cls)
    if (base != cls && classConsMin.has(base) == 1) { return base }
    return cls
}

// Infer class name from an expression node (for method dispatch / field checking)
function inferCheckerClass(nodeId: int): string {
    if (nodeId <= 0) { return "" }
    const kind = nGetKind(nodeId)
    if (kind == "IDENT") {
        return resolveCheckerClass(lookupVar(nGetS1(nodeId)))
    }
    if (kind == "THIS") { return currentCheckerClass }
    if (kind == "NEW_EXPR") { return nGetS1(nodeId) }
    if (kind == "STRING_LIT" || kind == "TEMPLATE_LIT") { return "string" }
    if (kind == "ARRAY_LIT") { return "Array" }
    if (kind == "MEMBER_ACCESS") {
        const objClass = inferCheckerClass(nGetI1(nodeId))
        if (objClass == "") { return "" }
        const fieldKey = `${objClass}.${nGetS1(nodeId)}`
        if (checkerFieldTypes.has(fieldKey) == 1) {
            return resolveCheckerClass(checkerFieldTypes.getString(fieldKey))
        }
        return ""
    }
    if (kind == "CALL") {
        const fname = nGetS1(nodeId)
        if (funcNames.has(fname) == 1) {
            return resolveCheckerClass(funcNames.getString(fname))
        }
        return ""
    }
    if (kind == "METHOD_CALL") {
        const objClass = inferCheckerClass(nGetI1(nodeId))
        if (objClass != "" && classConsMin.has(objClass) == 1) {
            return resolveCheckerClass(lookupMethodRetType(objClass, nGetS1(nodeId)))
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

function lookupMethodParamType(className: string, methodName: string, paramIndex: int): string {
    let cls = className
    while (cls != "") {
        const key = `${cls}.${methodName}:${paramIndex}`
        if (methodParamTypes.has(key) == 1) {
            return methodParamTypes.getString(key)
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    return ""
}

function lookupMethodRetType(className: string, methodName: string): string {
    let cls = className
    while (cls != "") {
        const key = `${cls}.${methodName}`
        if (methodRetTypes.has(key) == 1) {
            return methodRetTypes.getString(key)
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

// ── Type inference + compatibility ────────────────────────────

function checkerInferType(nodeId: int): string {
    if (nodeId <= 0) { return "" }
    const kind = nGetKind(nodeId)
    if (kind == "INT_LIT") { return "int" }
    if (kind == "DOUBLE_LIT") { return "double" }
    if (kind == "STRING_LIT" || kind == "TEMPLATE_LIT") { return "string" }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT") { return "int" }
    if (kind == "NULL_LIT") { return "" }
    if (kind == "ARRAY_LIT") { return "Array" }
    if (kind == "ARROW_FUNC") { return "fn" }
    if (kind == "THIS") { return currentCheckerClass }
    if (kind == "IDENT") {
        const vType = lookupVar(nGetS1(nodeId))
        if (vType != "") {
            if (vType != "auto") { return vType }
            return ""
        }
        if (lookupFunc(nGetS1(nodeId)) == 1) { return "fn" }
        return ""
    }
    if (kind == "NEW_EXPR") { return nGetS1(nodeId) }
    if (kind == "CALL") {
        const callee = nGetS1(nodeId)
        if (funcNames.has(callee) == 1) {
            const retType = funcNames.getString(callee)
            if (retType != "" && retType != "builtin") { return retType }
        }
        return ""
    }
    if (kind == "METHOD_CALL") {
        const mcRecv = inferCheckerClass(nGetI1(nodeId))
        if (mcRecv != "" && classConsMin.has(mcRecv) == 1) {
            return lookupMethodRetType(mcRecv, nGetS1(nodeId))
        }
        return ""
    }
    if (kind == "MEMBER_ACCESS") {
        const objClass = inferCheckerClass(nGetI1(nodeId))
        if (objClass != "") {
            const fieldKey = `${objClass}.${nGetS1(nodeId)}`
            if (checkerFieldTypes.has(fieldKey) == 1) {
                return checkerFieldTypes.getString(fieldKey)
            }
        }
        return ""
    }
    if (kind == "BINARY") {
        const op = nGetS1(nodeId)
        if (op == "Eq" || op == "Ne" || op == "Lt" || op == "Gt" || op == "Le" || op == "Ge" || op == "And" || op == "Or") {
            return "int"
        }
        const blt = checkerInferType(nGetI1(nodeId))
        const brt = checkerInferType(nGetI2(nodeId))
        if (op == "Add" && (blt == "string" || brt == "string")) { return "string" }
        if (blt == "double" || brt == "double") { return "double" }
        if (blt == "int") { return "int" }
        if (brt == "int") { return "int" }
        return ""
    }
    if (kind == "UNARY") { return checkerInferType(nGetI1(nodeId)) }
    if (kind == "GROUPING") { return checkerInferType(nGetI1(nodeId)) }
    if (kind == "TERNARY") { return checkerInferType(nGetI2(nodeId)) }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { return "int" }
    if (kind == "NAMED_ARG") { return checkerInferType(nGetI1(nodeId)) }
    if (kind == "SPREAD_ELEM") { return checkerInferType(nGetI1(nodeId)) }
    return ""
}

function baseTypeName(t: string): string {
    const ltIdx = t.indexOf("<")
    if (ltIdx > 0) { return t.substring(0, ltIdx) }
    return t
}

function isTypeCompatible(declared: string, actual: string): int {
    if (declared == "" || actual == "") { return 1 }
    if (declared == "auto" || actual == "auto") { return 1 }
    if (declared == actual) { return 1 }
    if (declared == "double" && actual == "int") { return 1 }
    // bool is int in SS
    if ((declared == "bool" && actual == "int") || (declared == "int" && actual == "bool")) { return 1 }
    if (ifaceMethods.has(declared) == 1) { return 1 }
    // Class inheritance: actual is subclass of declared
    let parent = ""
    if (checkerClassParents.has(actual) == 1) {
        parent = checkerClassParents.getString(actual)
    }
    while (parent != "") {
        if (parent == declared) { return 1 }
        if (checkerClassParents.has(parent) == 1) {
            parent = checkerClassParents.getString(parent)
        } else {
            parent = ""
        }
    }
    // Generic types: compare base type (Array<int> compat with Array — imprecise but safe)
    const declBase = baseTypeName(declared)
    const actualBase = baseTypeName(actual)
    if (declBase != declared || actualBase != actual) {
        if (declBase == actualBase) { return 1 }
    }
    // List/Tuple are aliases for Array
    if ((declBase == "Array" || declBase == "List" || declBase == "Tuple") && (actualBase == "Array" || actualBase == "List" || actualBase == "Tuple")) { return 1 }
    return 0
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
                if (funcNames.has(fname) == 1) {
                    funcOverloaded.set(fname, "1")
                }
                defineFunc(fname, nGetS2(s))
                const fRange = countParamRange(nGetList(s))
                const fComma = fRange.indexOf(",")
                defineFuncParams(fname, parseInt(fRange.substring(0, fComma)), parseInt(fRange.substring(fComma + 1, fRange.length() - fComma - 1)))
                // Store parameter types for non-overloaded, non-generic user functions
                if (funcOverloaded.has(fname) == 0 && nGetS3(s) == "") {
                    const ptList = nGetList(s)
                    if (ptList != "") {
                        const ptParts = ptList.split(",")
                        let ptIdx = 0
                        for (pt in ptParts) {
                            const ptId = parseInt(pt)
                            if (ptId > 0 && nGetKind(ptId) == "PARAM") {
                                const ptType = nGetS2(ptId)
                                if (ptType != "") {
                                    funcParamTypes.set(`${fname}:${ptIdx}`, ptType)
                                }
                                ptIdx = ptIdx + 1
                            }
                        }
                    }
                }
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
                    parentName = baseTypeName(parentName)
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
                                const mName = nGetS1(cmId)
                                const mRange = countParamRange(nGetList(cmId))
                                const mComma = mRange.indexOf(",")
                                registerMethodParams(className, mName, parseInt(mRange.substring(0, mComma)), parseInt(mRange.substring(mComma + 1, mRange.length() - mComma - 1)))
                                // Store method param types + return type (non-generic classes)
                                if (classTypeParams(s) == "") {
                                    const mRetType = nGetS2(cmId)
                                    if (mRetType != "") {
                                        methodRetTypes.set(`${className}.${mName}`, mRetType)
                                    }
                                    const mPList = nGetList(cmId)
                                    if (mPList != "") {
                                        const mParts = mPList.split(",")
                                        let mPIdx = 0
                                        for (mp in mParts) {
                                            const mpId = parseInt(mp)
                                            if (mpId > 0 && nGetKind(mpId) == "PARAM") {
                                                const mpType = nGetS2(mpId)
                                                if (mpType != "") {
                                                    methodParamTypes.set(`${className}.${mName}:${mPIdx}`, mpType)
                                                }
                                                mPIdx = mPIdx + 1
                                            }
                                        }
                                    }
                                }
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


