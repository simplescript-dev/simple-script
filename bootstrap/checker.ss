// SimpleScript Bootstrap Type Checker
// Core: initialization, scope management, function registry, error reporting, entry point.
// Statement/expression checking logic in check_stmts.ss.

import { nGetKind, nGetS1, nGetS2, nGetS3, nGetI1, nGetI2, nGetI3, nGetI4, nGetList, nGetLine, nGetCol, getLineOffset, classTypeParams } from "./parser"
import { getSourceLine } from "./lexer"
import { checkStmtList } from "./check_stmts"
import { isNullableType, isPrimitiveNullable, stripNullable, makeNullable, getNarrowedType, checkerInferType, baseTypeName, extractElemType, isTypeCompatible } from "./check_types"
import { pushScope, popScope, defineVar, lookupVar, isVarConst } from "./check_scope"

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
let checkerFieldsForInVars = ""
let constFields = ""         // "ClassName.fieldName" -> "1" if const field
let checkerFieldTypes = ""   // "ClassName.fieldName" -> type string
let checkerClassFields = ""  // "ClassName" -> "field1,field2,..." (ordered field list)
let funcParamTypes = ""     // "funcName:paramIndex" -> type string
let funcOverloaded = ""     // "funcName" -> "1" if overloaded (skip type check)
let methodParamTypes = ""   // "ClassName.methodName:paramIndex" -> type string
let methodRetTypes = ""     // "ClassName.methodName" -> return type string
let currentFuncRetType = "" // current function's declared return type (for RETURN type checking)
let currentTypeParams = ""  // current function's type parameters (comma-separated, for generic compat)
let checkerGenericClasses = "" // "ClassName" -> "1" if class has type parameters
let narrowedTypes = ""         // Map: "varName" -> narrowed type (D067 Phase 2: smart narrowing)
let privateFields = ""         // "ClassName.fieldName" -> "1" if private (D068)
let privateMethods = ""        // "ClassName.methodName" -> "1" if private (D068)
let protectedFields = ""       // "ClassName.fieldName" -> "1" if protected (D068 Phase 2)
let protectedMethods = ""      // "ClassName.methodName" -> "1" if protected (D068 Phase 2)
let staticMethods = ""         // "ClassName.methodName" -> "1" if static (D070)
let staticFields = ""          // "ClassName.fieldName" -> "1" if static (D078)
let currentStaticMethod = 0    // 1 when inside a static method body (D070)
let abstractClasses = ""       // "ClassName" -> "1" if abstract class (D071)
let abstractMethods = ""       // "ClassName.methodName" -> "1" if abstract method (D071)
let classMethodNames = ""      // "ClassName" -> ",method1,method2," for abstract impl check (D071)
let checkerDeferredAliases = "" // "aliasName" -> "1" if alias 绑定到泛型 type param(由 specialization 决定 class) — 跳过字段严校验,codegen 兜底

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
    currentFuncRetType = ""
    currentTypeParams = ""
    checkerGenericClasses = Map()
    narrowedTypes = Map()
    privateFields = Map()
    privateMethods = Map()
    protectedFields = Map()
    protectedMethods = Map()
    staticMethods = Map()
    staticFields = Map()
    currentStaticMethod = 0
    abstractClasses = Map()
    abstractMethods = Map()
    classMethodNames = Map()
    checkerDeferredAliases = Map()
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
    // Built-in class: Thread (D082 Phase 2)
    classConsMin.set("Thread", "0")
    classConsMax.set("Thread", "0")
    registerMethodParams("Thread", "start", 1, 1)
    registerMethodParams("Thread", "join", 0, 0)
    // Built-in class: Channel (D082 Phase 4)
    classConsMin.set("Channel", "0")
    classConsMax.set("Channel", "1")
    registerMethodParams("Channel", "send", 1, 1)
    registerMethodParams("Channel", "receive", 0, 0)
    registerMethodParams("Channel", "close", 0, 0)
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
    // Built-in functions with return types (synced with gen_registry.ss)
    const strFns = "readLine,readFile,arg,getenv,listDir,sha256,tcpRead,fromCharCode,base64Encode,base64Decode,_ss_inotify_poll"
    const sf = strFns.split(",")
    for (s in sf) { funcNames.set(s, "string") }
    const intFns = "parseInt,args,system,tcpListen,tcpAccept,tcpWrite,mkdir,mkdirp,fileExists,removeFile,renameFile,charCodeAt,timeMs,timeUnix,fileSize,_ss_inotify_init,_ss_inotify_add_watch"
    const intf = intFns.split(",")
    for (i in intf) { funcNames.set(i, "int") }
    const voidFns = "println,print,writeFile,appendFile,exit,tcpClose,test,_ss_inotify_close"
    const vf = voidFns.split(",")
    for (v in vf) { funcNames.set(v, "void") }
    funcNames.set("parseDouble", "double")
    funcNames.set("Map", "Map")
    funcNames.set("Set", "Set")
    funcNames.set("exec", "ExecResult")
    // D082: ref/watch
    funcNames.set("ref", "Ref")
    funcNames.set("watch", "void")
    allFuncNameList = `${voidFns},${strFns},${intFns},parseDouble,Map,Set,ref,watch`
    // Built-in namespaces (accessed as Math.sqrt(), Thread.start() etc.)
    defineVar("Math", "namespace", 0)
    defineVar("Thread", "namespace", 0)
    // Built-in param counts
    const zeroArgFns = "readLine,args,Map,timeMs,timeUnix,_ss_inotify_init"
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
    const oneArgFns = "readFile,arg,exit,system,parseInt,parseDouble,getenv,listDir,sha256,fromCharCode,base64Encode,base64Decode,tcpListen,tcpAccept,tcpClose,mkdir,mkdirp,fileExists,removeFile,fileSize,_ss_popen_read,exec,_ss_inotify_close,ref"
    const oa = oneArgFns.split(",")
    for (o in oa) {
        funcParamMin.set(o, "1")
        funcParamMax.set(o, "1")
    }
    const twoArgFns = "writeFile,appendFile,tcpWrite,tcpRead,renameFile,charCodeAt,test,_ss_inotify_poll,watch"
    const ta = twoArgFns.split(",")
    for (t in ta) {
        funcParamMin.set(t, "2")
        funcParamMax.set(t, "2")
    }
    // 3-param builtin (no batch list for 3-arg functions)
    funcParamMin.set("_ss_inotify_add_watch", "3")
    funcParamMax.set("_ss_inotify_add_watch", "3")
    funcReady = 1
}

// Normalize generic type to base class name for method dispatch (Array<int> → Array, Player? → Player)
function resolveCheckerClass(cls: string): string {
    if (cls == "" || cls == "null") { return "" }
    const stripped = stripNullable(cls)
    if (classConsMin.has(stripped) == 1) { return stripped }
    const base = baseTypeName(stripped)
    if (base != stripped && classConsMin.has(base) == 1) { return base }
    return stripped
}

// Infer class name from an expression node (for method dispatch / field checking)
function inferCheckerClass(nodeId: int): string {
    if (nodeId <= 0) { return "" }
    const kind = nGetKind(nodeId)
    if (kind == "IDENT") {
        return resolveCheckerClass(lookupVar(nGetS1(nodeId)))
    }
    if (kind == "THIS") { return currentCheckerClass }
    if (kind == "SUPER") {
        if (currentCheckerClass != "" && checkerClassParents.has(currentCheckerClass) == 1) {
            return checkerClassParents.getString(currentCheckerClass)
        }
        return ""
    }
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

// D071: Check that a non-abstract class implements all inherited abstract methods
function checkAbstractImpl(className: string, parentName: string, ownMethods: string, line: int, col: int) {
    // Collect all concrete method names from self + parent chain (non-abstract)
    let allImpl = ownMethods
    let p = parentName
    while (p != "") {
        if (classMethodNames.has(p) == 1) {
            const pMethods = classMethodNames.getString(p)
            if (pMethods != ",") {
                // Add each non-abstract parent method
                let rem = pMethods.substring(1, pMethods.length() - 1)
                while (rem != "") {
                    let m = rem
                    const ci = rem.indexOf(",")
                    if (ci >= 0) {
                        m = rem.substring(0, ci)
                        rem = rem.substring(ci + 1, rem.length() - ci - 1)
                    } else {
                        rem = ""
                    }
                    if (m != "" && abstractMethods.has(`${p}.${m}`) == 0) {
                        if (allImpl.contains(`,${m},`) == 0) {
                            allImpl = `${allImpl}${m},`
                        }
                    }
                }
            }
        }
        if (checkerClassParents.has(p) == 1) {
            p = checkerClassParents.getString(p)
        } else {
            p = ""
        }
    }
    // Check all abstract methods from parent chain are implemented
    p = parentName
    while (p != "") {
        if (classMethodNames.has(p) == 1) {
            const pMethods = classMethodNames.getString(p)
            if (pMethods != ",") {
                let rem = pMethods.substring(1, pMethods.length() - 1)
                while (rem != "") {
                    let m = rem
                    const ci = rem.indexOf(",")
                    if (ci >= 0) {
                        m = rem.substring(0, ci)
                        rem = rem.substring(ci + 1, rem.length() - ci - 1)
                    } else {
                        rem = ""
                    }
                    if (m != "" && abstractMethods.has(`${p}.${m}`) == 1) {
                        if (allImpl.contains(`,${m},`) == 0) {
                            checkerError(`class '${className}' must implement abstract method '${m}' from '${p}'`, line, col)
                        }
                    }
                }
            }
        }
        if (checkerClassParents.has(p) == 1) {
            p = checkerClassParents.getString(p)
        } else {
            p = ""
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

// D068: Walk parent chain to find which class owns a private field/method
function lookupPrivateOwner(className: string, memberName: string, isMethod: int): string {
    let cls = className
    while (cls != "") {
        const key = `${cls}.${memberName}`
        if (isMethod == 1) {
            if (privateMethods.has(key) == 1) { return cls }
        } else {
            if (privateFields.has(key) == 1) { return cls }
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    return ""
}

// D068 Phase 2: Walk parent chain to find which class owns a protected field/method
function lookupProtectedOwner(className: string, memberName: string, isMethod: int): string {
    let cls = className
    while (cls != "") {
        const key = `${cls}.${memberName}`
        if (isMethod == 1) {
            if (protectedMethods.has(key) == 1) { return cls }
        } else {
            if (protectedFields.has(key) == 1) { return cls }
        }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    return ""
}

// D068 Phase 2: Check if child class is a subclass of ancestor (walks parent chain)
function isSubclassOf(child: string, ancestor: string): int {
    if (child == "" || ancestor == "") { return 0 }
    let cls = child
    while (checkerClassParents.has(cls) == 1) {
        cls = checkerClassParents.getString(cls)
        if (cls == ancestor) { return 1 }
    }
    return 0
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

// Look up constructor param type by walking parent chain (parent fields first).
// Returns "" if type unknown (generic class field, out of range, etc).
function lookupConsParamType(className: string, paramIndex: int): string {
    // Build parent chain from root to leaf
    let chain = ""
    let cls = className
    while (cls != "") {
        if (chain == "") { chain = cls }
        else { chain = `${cls},${chain}` }
        if (checkerClassParents.has(cls) == 1) {
            cls = checkerClassParents.getString(cls)
        } else {
            cls = ""
        }
    }
    // Walk chain from root to leaf, counting fields
    let idx = 0
    const chainParts = chain.split(",")
    for (cp in chainParts) {
        if (checkerClassFields.has(cp) == 0) { continue }
        const fields = checkerClassFields.getString(cp)
        if (fields == "") { continue }
        const isGeneric = checkerGenericClasses.has(cp)
        const fParts = fields.split(",")
        for (fp in fParts) {
            if (idx == paramIndex) {
                if (isGeneric == 1) { return "" }
                const key = `${cp}.${fp}`
                if (checkerFieldTypes.has(key) == 1) {
                    return checkerFieldTypes.getString(key)
                }
                return ""
            }
            idx = idx + 1
        }
    }
    return ""
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

// overrideName == "" 按 nGetS1(s) 注册;否则以别名注册,让 `const W=comptime{...return Wrap}` 的 W 与 Wrap 共享字段/方法签名
function registerCheckerClassDecl(s: int, overrideName: string) {
    const className = overrideName != "" ? overrideName : nGetS1(s)
    defineVar(className, "class", 0)
    if (nGetI1(s) == 1) {
        abstractClasses.set(className, "1")
    }
    let parentName = nGetS2(s)
    if (parentName != "") {
        parentName = baseTypeName(parentName)
        checkerClassParents.set(className, parentName)
    }
    const fieldList = nGetList(s)
    let fieldNameList = ""
    let instanceParamList = ""
    if (fieldList != "") {
        const flds = fieldList.split(",")
        for (f in flds) {
            const fId = parseInt(f)
            if (fId > 0 && nGetKind(fId) == "PARAM") {
                const fName = nGetS1(fId)
                const fType = nGetS2(fId)
                const fKey = `${className}.${fName}`
                checkerFieldTypes.set(fKey, fType)
                if (nGetI4(fId) == 1) {
                    staticFields.set(fKey, "1")
                } else {
                    fieldNameList = listAppendStr(fieldNameList, fName)
                    instanceParamList = listAppend(instanceParamList, fId)
                }
                if (nGetS3(fId) == "const") {
                    constFields.set(fKey, "1")
                }
                if (nGetI3(fId) == 1) {
                    privateFields.set(fKey, "1")
                }
                if (nGetI3(fId) == 2) {
                    protectedFields.set(fKey, "1")
                }
            }
        }
    }
    checkerClassFields.set(className, fieldNameList)
    if (classTypeParams(s) != "") {
        classConsMin.set(className, "0")
        classConsMax.set(className, "99")
        checkerGenericClasses.set(className, "1")
    } else {
        const consRange = countParamRange(instanceParamList)
        const consComma = consRange.indexOf(",")
        classConsMin.set(className, consRange.substring(0, consComma))
        classConsMax.set(className, consRange.substring(consComma + 1, consRange.length() - consComma - 1))
    }
    let clsMethodNameList = ","
    const clsMethodsBlock = nGetI2(s)
    if (clsMethodsBlock > 0) {
        const clsML = nGetList(clsMethodsBlock)
        if (clsML != "") {
            const clsMS = clsML.split(",")
            for (cm in clsMS) {
                const cmId = parseInt(cm)
                if (cmId > 0 && nGetKind(cmId) == "FUNC_DECL") {
                    const mName = nGetS1(cmId)
                    clsMethodNameList = `${clsMethodNameList}${mName},`
                    if (nGetI3(cmId) == 1) {
                        privateMethods.set(`${className}.${mName}`, "1")
                    }
                    if (nGetI3(cmId) == 2) {
                        protectedMethods.set(`${className}.${mName}`, "1")
                    }
                    if (nGetI2(cmId) == 1) {
                        staticMethods.set(`${className}.${mName}`, "1")
                    }
                    if (nGetI4(cmId) == 1) {
                        abstractMethods.set(`${className}.${mName}`, "1")
                        if (abstractClasses.has(className) == 0) {
                            checkerError(`abstract method '${mName}' can only be declared in an abstract class`, nGetLine(cmId), nGetCol(cmId))
                        }
                        if (nGetI3(cmId) == 1) {
                            checkerError(`'private' modifier cannot be used with 'abstract' modifier`, nGetLine(cmId), nGetCol(cmId))
                        }
                        if (nGetI2(cmId) == 1) {
                            checkerError(`'static' modifier cannot be used with 'abstract' modifier`, nGetLine(cmId), nGetCol(cmId))
                        }
                    }
                    const mRange = countParamRange(nGetList(cmId))
                    const mComma = mRange.indexOf(",")
                    registerMethodParams(className, mName, parseInt(mRange.substring(0, mComma)), parseInt(mRange.substring(mComma + 1, mRange.length() - mComma - 1)))
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
    classMethodNames.set(className, clsMethodNameList)
    if (abstractClasses.has(className) == 0 && parentName != "") {
        checkAbstractImpl(className, parentName, clsMethodNameList, nGetLine(s), nGetCol(s))
    }
}

// 扫 stmtList 里所有 VAR_DECL,若 init 是 COMPTIME_EXPR:
//   - 把 body 里的 CLASS_DECL 按原名注册到 checker
//   - 若 body 末尾 return IDENT 指向某 CLASS_DECL 名,把 VAR_DECL 名注册为该 class 的 alias(字段/方法签名共享)
//   - 若 return IDENT 指向 enclosing function 的 type param(如 `function f<T>() { const R = comptime { return T } }`),
//     把 VAR_DECL 名登记到 checkerDeferredAliases:具体 class 由 specialization 决定,checker 跳过字段严校验。
// 递归进 FUNC_DECL body,传下该函数的 type params。
function preScanComptimeClasses(stmtList: string, enclosingTypeParams: string) {
    if (stmtList == "") { return }
    const parts = stmtList.split(",")
    for (p in parts) {
        const s = parseInt(p)
        if (s <= 0) { continue }
        const sk = nGetKind(s)
        if (sk == "FUNC_DECL") {
            const fbId = nGetI1(s)
            if (fbId > 0) { preScanComptimeClasses(nGetList(fbId), nGetS3(s)) }
            continue
        }
        if (sk != "VAR_DECL") { continue }
        const initId = nGetI1(s)
        if (initId <= 0 || nGetKind(initId) != "COMPTIME_EXPR") { continue }
        const bodyId = nGetI1(initId)
        if (bodyId <= 0) { continue }
        const bList = nGetList(bodyId)
        if (bList == "") { continue }
        const bParts = bList.split(",")
        let returnName = ""
        for (bp in bParts) {
            const bs = parseInt(bp)
            if (bs <= 0) { continue }
            if (nGetKind(bs) == "CLASS_DECL") {
                registerCheckerClassDecl(bs, "")
            }
            if (nGetKind(bs) == "RETURN") {
                const retExpr = nGetI1(bs)
                if (retExpr > 0 && nGetKind(retExpr) == "IDENT") {
                    returnName = nGetS1(retExpr)
                }
            }
        }
        if (returnName != "") {
            const varName = nGetS1(s)
            let resolvedAsClassDecl = 0
            for (bp2 in bParts) {
                const bs2 = parseInt(bp2)
                if (bs2 > 0 && nGetKind(bs2) == "CLASS_DECL" && nGetS1(bs2) == returnName) {
                    registerCheckerClassDecl(bs2, varName)
                    resolvedAsClassDecl = 1
                }
            }
            if (resolvedAsClassDecl == 0 && enclosingTypeParams != "") {
                const tpParts = enclosingTypeParams.split(",")
                for (tp in tpParts) {
                    if (tp == returnName) {
                        checkerDeferredAliases.set(varName, "1")
                    }
                }
            }
        }
    }
}

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
                registerCheckerClassDecl(s, "")
            }
            if (sk == "ENUM_DECL") {
                defineVar(nGetS1(s), "enum", 0)
                // D076: string enum — all variants must have explicit string values, no mixing
                if (nGetI1(s) == 1) {
                    const evl = nGetList(s)
                    if (evl != "") {
                        const evParts = evl.split(",")
                        for (ev in evParts) {
                            const evId = parseInt(ev)
                            if (evId > 0 && nGetS2(evId) == "") {
                                checkerError(`enum '${nGetS1(s)}' cannot mix string and integer values`, nGetLine(evId), nGetCol(evId))
                            }
                        }
                    }
                }
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
    // Pass 2 前注册 comptime 块内声明的 class,让 `new W(...)` 可被 checker 识别
    preScanComptimeClasses(stmtList, "")
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


