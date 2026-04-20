// SimpleScript Bootstrap Type Checker
// Core: initialization, scope management, function registry, error reporting, entry point.
// Statement/expression checking logic in check_stmts.ss.

import { nGetKind, nGetS1, nGetS2, nGetS3, nGetI1, nGetI2, nGetI3, nGetI4, nGetList, nGetLine, nGetCol, getLineOffset, classTypeParams } from "../parse/parser"
import { getSourceLine } from "../lexer/lexer"
import { checkStmtList } from "./check_stmts"
import { isNullableType, isPrimitiveNullable, stripNullable, makeNullable, getNarrowedType, checkerInferType, baseTypeName, extractElemType, isTypeCompatible } from "./check_types"
import { pushScope, popScope, defineVar, lookupVar, isVarConst } from "./check_scope"
import { defineFunc, lookupFunc, defineFuncParams, countParamRange, checkArgCount, countArgs, hasSpreadArg } from "./check_func"
import { resolveCheckerClass, inferCheckerClass, checkInterfaceImpl, checkAbstractImpl, registerMethodParams, lookupMethodParams, lookupMethodParamType, lookupMethodRetType, lookupPrivateOwner, lookupProtectedOwner, isSubclassOf, totalConstructorParams, lookupConsParamType, registerCheckerClassDecl, preScanComptimeClasses } from "./check_class"

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

