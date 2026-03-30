// SimpleScript Bootstrap Code Generator
// Walks the Map-based AST and produces LLVM IR text (.ll format).
// Uses SSA registers (%1, %2, ...) and named allocas for variables.

import { nGetKind, nGetS1, nGetS2, nGetS3, nGetI1, nGetI2, nGetI3, nGetI4, nGetList } from "./parser"

// ── State ─────────────────────────────────────────────────────

let irBuf = ""
let strConsts = ""
let strCount = 0
let irOutFile = ""
let strOutFile = ""
let regCount = 0
let labelCount = 0
let varTypes = ""
let varTypesReady = 0
let currentFunc = ""
let terminated = 0
let varCounter = 0
let varAliases = ""
let globalAliases = ""
let varAliasReady = 0

function initVarAliases() {
    if (varAliasReady == 1) { return }
    varAliases = Map()
    globalAliases = Map()
    varAliasReady = 1
}

function allocVarName(name: string): string {
    initVarAliases()
    varCounter = varCounter + 1
    const llName = `${name}.${varCounter}`
    varAliases.set(name, llName)
    return llName
}

function llVarName(name: string): string {
    initVarAliases()
    if (varAliases.has(name) == 1) {
        return varAliases.getString(name)
    }
    if (globalAliases.has(name) == 1) {
        return globalAliases.getString(name)
    }
    return name
}
// Returns "%" + name or "@name" for globals
function varRef(name: string): string {
    const ln = llVarName(name)
    if (ln.startsWith("@") == 1) { return ln }
    return `%${ln}`
}

let funcRetTypes = ""
let funcRetReady = 0
let classFields = ""     // "ClassName" -> "field1,field2,..."
let classFieldTypes = "" // "ClassName.field" -> "type"
let classMethods = ""    // "ClassName" -> "method1,method2,..."
let objClasses = ""      // "varName" -> "ClassName"
let classParents = ""    // "ClassName" -> "ParentClassName"
let classNeedsVtable = "" // "ClassName" -> "1" (if class has vtable)
let classVtableSlots = "" // "ClassName" -> "method1,method2,..." (ordered vtable slots)
let classVtableImpl = ""  // "ClassName.method" -> "ImplClassName_method" (actual func)
let classDtorTags = ""    // "ClassName" -> "tag" (tag >= 10 for classes with ptr fields)
let dtorNextTag = 10      // next available class dtor tag
let funcDefaults = ""    // "funcName" -> "paramIdx:defaultNodeId,..."
let funcParamCount = ""  // "funcName" -> param count
let currentClassName = ""
let breakLabel = ""
let continueLabel = ""
// RC state moved to gen_rc.ss (localPtrVars, rcBlockDepth, blockPtrVarStack, etc.)
let enumValues = ""
let enumReady = 0
let methodRetTypes = ""   // "methodName" -> return type (built-in method fallback)
let overloadCount = ""
let overloadReady = 0
let annotatedRoutes = ""

function initFuncRetTypes() {
    if (funcRetReady == 1) { return }
    funcRetTypes = Map()
    classFields = Map()
    classFieldTypes = Map()
    classMethods = Map()
    objClasses = Map()
    classNeedsVtable = Map()
    classVtableSlots = Map()
    classVtableImpl = Map()
    classDtorTags = Map()
    dtorNextTag = 10
    classParents = Map()
    funcDefaults = Map()
    funcParamCount = Map()
    // Register Map as a built-in class (eliminates special cases)
    classFields.set("Map", "")
    classMethods.set("Map", "set,get,getString,has,delete,size,keys")
    funcRetTypes.set("Map_set", "void")
    funcRetTypes.set("Map_get", "i64")
    funcRetTypes.set("Map_getString", "string")
    funcRetTypes.set("Map_has", "int")
    funcRetTypes.set("Map_delete", "void")
    funcRetTypes.set("Map_size", "int")
    funcRetTypes.set("Map_keys", "string")
    funcRetTypes.set("Map_new", "Map")
    // Register Math as built-in class with static methods (Java/JS style)
    classFields.set("Math", "")
    funcRetTypes.set("Math_sqrt", "double")
    funcRetTypes.set("Math_abs", "double")
    funcRetTypes.set("Math_floor", "double")
    funcRetTypes.set("Math_ceil", "double")
    funcRetTypes.set("Math_round", "double")
    funcRetTypes.set("Math_pow", "double")
    funcRetTypes.set("Math_log", "double")
    funcRetTypes.set("Math_sin", "double")
    funcRetTypes.set("Math_cos", "double")
    funcRetTypes.set("Math_random", "double")
    funcRetTypes.set("Math_min", "double")
    funcRetTypes.set("Math_max", "double")
    // Built-in function return types (from callReturnType hardcoded lists)
    funcRetTypes.set("readLine", "string")
    funcRetTypes.set("readFile", "string")
    funcRetTypes.set("arg", "string")
    funcRetTypes.set("getenv", "string")
    funcRetTypes.set("listDir", "string")
    funcRetTypes.set("sha256", "string")
    funcRetTypes.set("tcpRead", "string")
    funcRetTypes.set("fromCharCode", "string")
    funcRetTypes.set("base64Encode", "string")
    funcRetTypes.set("base64Decode", "string")
    funcRetTypes.set("ss_sqlite3_query", "string")
    funcRetTypes.set("ss_sqlite3_open", "string")
    funcRetTypes.set("println", "void")
    funcRetTypes.set("print", "void")
    funcRetTypes.set("writeFile", "void")
    funcRetTypes.set("appendFile", "void")
    funcRetTypes.set("exit", "void")
    funcRetTypes.set("tcpClose", "void")
    funcRetTypes.set("parseInt", "int")
    funcRetTypes.set("args", "int")
    funcRetTypes.set("system", "int")
    funcRetTypes.set("tcpListen", "int")
    funcRetTypes.set("tcpAccept", "int")
    funcRetTypes.set("tcpWrite", "int")
    funcRetTypes.set("mkdir", "int")
    funcRetTypes.set("mkdirp", "int")
    funcRetTypes.set("fileExists", "int")
    funcRetTypes.set("removeFile", "int")
    funcRetTypes.set("renameFile", "int")
    funcRetTypes.set("charCodeAt", "int")
    funcRetTypes.set("parseDouble", "double")
    funcRetTypes.set("timeMs", "i64")
    funcRetTypes.set("timeUnix", "i64")
    funcRetTypes.set("fileSize", "i64")
    funcRetTypes.set("Map", "Map")
    // Built-in method return types (type-agnostic fallback for string/array methods)
    methodRetTypes = Map()
    methodRetTypes.set("length", "int")
    methodRetTypes.set("indexOf", "int")
    methodRetTypes.set("has", "int")
    methodRetTypes.set("size", "int")
    methodRetTypes.set("contains", "int")
    methodRetTypes.set("startsWith", "int")
    methodRetTypes.set("endsWith", "int")
    methodRetTypes.set("charCodeAt", "int")
    methodRetTypes.set("reduce", "int")
    methodRetTypes.set("charAt", "string")
    methodRetTypes.set("substring", "string")
    methodRetTypes.set("trim", "string")
    methodRetTypes.set("toUpperCase", "string")
    methodRetTypes.set("toLowerCase", "string")
    methodRetTypes.set("replace", "string")
    methodRetTypes.set("join", "string")
    methodRetTypes.set("repeat", "string")
    methodRetTypes.set("padStart", "string")
    methodRetTypes.set("padEnd", "string")
    methodRetTypes.set("keys", "string")
    methodRetTypes.set("getString", "string")
    methodRetTypes.set("split", "ptr")
    methodRetTypes.set("push", "ptr")
    methodRetTypes.set("slice", "ptr")
    methodRetTypes.set("concat", "ptr")
    methodRetTypes.set("reverse", "ptr")
    methodRetTypes.set("sort", "ptr")
    methodRetTypes.set("map", "ptr")
    methodRetTypes.set("filter", "ptr")
    methodRetTypes.set("get", "i64")
    methodRetTypes.set("delete", "void")
    methodRetTypes.set("forEach", "void")
    funcRetReady = 1
}

function initCodegen() {
    if (varTypesReady == 1) { return }
    varTypes = Map()
    varTypesReady = 1
}

function emitIR(s: string) {
    if (irOutFile != "") {
        appendFile(irOutFile, `${s}\n`)
    } else {
        irBuf = `${irBuf}${s}\n`
    }
}

function nextReg(): string {
    regCount = regCount + 1
    return `%${regCount}`
}

function nextLabel(prefix: string): string {
    labelCount = labelCount + 1
    return `${prefix}.${labelCount}`
}

function addStringConst(value: string): string {
    const name = `@.str.${strCount}`
    strCount = strCount + 1
    // Escape the string for LLVM IR c"..." format
    let escaped = ""
    let i = 0
    const sLen = value.length()
    while (i < sLen) {
        const ch = value.charAt(i)
        if (ch == "\n") { escaped = escaped + "\\0A"
        } else if (ch == "\r") { escaped = escaped + "\\0D"
        } else if (ch == "\t") { escaped = escaped + "\\09"
        } else if (ch == "\\") { escaped = escaped + "\\5C"
        } else if (ch == "\"") { escaped = escaped + "\\22"
        } else { escaped = escaped + ch }
        i = i + 1
    }
    const line = `${name} = constant [${sLen + 1} x i8] c"${escaped}\\00"\n`
    // strOutFile overrides irOutFile for string constant output (used by arrow functions)
    const strTarget = strOutFile ?? irOutFile
    if (strTarget != "") {
        appendFile(`${strTarget}.str`, line)
    } else {
        strConsts = strConsts + line
    }
    return name
}

// ── Runtime (generated by emitRuntimeDefs in gen_runtime.ss) ─

// ── Public API ────────────────────────────────────────────────

// Shared codegen passes
function registerAllDecls(rootId: int) {
    const stmtList0 = nGetList(rootId)
    if (stmtList0 == "") { return }
    const parts0 = stmtList0.split(",")
    for (p0 in parts0) {
        const sid = parseInt(p0)
        if (sid <= 0) { continue }
        const sk = nGetKind(sid)
        if (sk == "FUNC_DECL") {
            const fname = nGetS1(sid)
            let fret = nGetS2(sid)
            if (fret == "") { fret = "void" }
            funcRetTypes.set(fname, fret)
            // Register mangled name + track overload count
            const fSig = paramSig(nGetList(sid))
            if (fSig != "") {
                funcRetTypes.set(`${fname}_${fSig}`, fret)
                funcParamCount.set(`${fname}_${fSig}`, funcParamCount.getString(fname) ?? "0")
            }
            if (overloadReady == 0) { overloadCount = new Map(); overloadReady = 1 }
            if (overloadCount.has(fname) == 1) {
                const cnt = parseInt(overloadCount.getString(fname))
                overloadCount.set(fname, `${cnt + 1}`)
            } else {
                overloadCount.set(fname, "1")
            }
            const fparams = nGetList(sid)
            if (fparams != "") {
                const fps = fparams.split(",")
                let pCount = 0
                let defaults = ""
                for (fp in fps) {
                    const fpId = parseInt(fp)
                    if (fpId > 0 && nGetKind(fpId) == "PARAM") {
                        let defId = nGetI1(fpId)
                        // ? optional param without explicit default → generate default node
                        if (defId <= 0 && nGetI2(fpId) > 0) {
                            const pType = nGetS2(fpId)
                            if (pType == "string") {
                                defId = newNode("STRING_LIT")
                                nSetS1(defId, "")
                            } else if (pType == "double") {
                                defId = newNode("DOUBLE_LIT")
                                nSetS1(defId, "0.0")
                            } else {
                                defId = newNode("INT_LIT")
                                nSetS1(defId, "0")
                            }
                            nSetI1(fpId, defId)
                        }
                        if (defId > 0) {
                            if (defaults == "") { defaults = `${pCount}:${defId}` } else { defaults = `${defaults},${pCount}:${defId}` }
                        }
                        pCount = pCount + 1
                    }
                }
                funcParamCount.set(fname, `${pCount}`)
                if (defaults != "") { funcDefaults.set(fname, defaults) }
            } else {
                funcParamCount.set(fname, "0")
            }
        }
        if (sk == "CLASS_DECL") {
            registerClass(sid)
            // Scan for @RestController / @RequestMapping annotations
            collectAnnotatedRoutes(sid)
        }
    }
    // Resolve inheritance after all classes are registered
    resolveInheritance()
    // Build vtable for classes in inheritance hierarchies
    buildClassVtables()
    // Assign dtor tags to classes with ptr fields
    assignClassDtorTags()
    // Detect cyclic ownership and mark non-owning container fields
    detectCyclicOwnership()
}

function collectAnnotatedRoutes(classId: int) {
    const annListId = nGetI4(classId)
    if (annListId <= 0) { return }
    if (nGetKind(annListId) != "ANNOTATION_LIST") { return }
    const annList = nGetList(annListId)
    if (annList == "") { return }
    // Check if class has @RestController
    let isController = 0
    let basePath = ""
    const annParts = annList.split(",")
    for (ap in annParts) {
        const aId = parseInt(ap)
        if (aId > 0 && nGetKind(aId) == "ANNOTATION") {
            if (nGetS1(aId) == "RestController") { isController = 1 }
            if (nGetS1(aId) == "RequestMapping") { basePath = nGetS2(aId) }
        }
    }
    if (isController == 0) { return }
    // Scan methods for @GetMapping, @PostMapping, etc.
    const className = nGetS1(classId)
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
            const annName = nGetS1(maId)
            const annPath = nGetS2(maId)
            let httpMethod = ""
            if (annName == "GetMapping") { httpMethod = "GET" }
            if (annName == "PostMapping") { httpMethod = "POST" }
            if (annName == "PutMapping") { httpMethod = "PUT" }
            if (annName == "DeleteMapping") { httpMethod = "DELETE" }
            if (annName == "PatchMapping") { httpMethod = "PATCH" }
            if (httpMethod != "") {
                const fullPath = `${basePath}${annPath}`
                const methodName = nGetS1(mId)
                // Store: "METHOD:path:ClassName:methodName"
                if (annotatedRoutes == "") {
                    annotatedRoutes = `${httpMethod}:${fullPath}:${className}:${methodName}`
                } else {
                    annotatedRoutes = `${annotatedRoutes}\n${httpMethod}:${fullPath}:${className}:${methodName}`
                }
            }
        }
    }
}

function emitGlobalsAndCode(rootId: int) {
    const sl = nGetList(rootId)
    if (sl == "") { return }
    const parts = sl.split(",")
    for (x1 in parts) { const s1 = parseInt(x1); if (s1 > 0 && nGetKind(s1) == "VAR_DECL") { genGlobalVar(s1) } }
    emitIR("")
    for (x2 in parts) { const s2 = parseInt(x2); if (s2 > 0 && nGetKind(s2) != "VAR_DECL") { genStmt(s2) } }
}

function resetCodegen() {
    // Reset guard flags so init functions re-create fresh Maps
    varTypesReady = 0
    funcRetReady = 0
    varAliasReady = 0
    initCodegen()
    initFuncRetTypes()
    initVarAliases()
    // IR output
    irBuf = ""
    strConsts = ""
    strCount = 0
    strOutFile = ""
    // SSA counters
    regCount = 0
    labelCount = 0
    varCounter = 0
    // Function/class context
    currentFunc = ""
    currentClassName = ""
    terminated = 0
    breakLabel = ""
    continueLabel = ""
    // RC state (gen_rc.ss)
    initRcState()
    // Enum / overload / routes
    enumValues = ""
    enumReady = 0
    overloadCount = ""
    overloadReady = 0
    annotatedRoutes = ""
    // Arrow functions (gen_exprs.ss)
    arrowCount = 0
    arrowDefs = ""
    // Global var init tracking (gen_stmts.ss)
    globalInitIds = ""
}

function generate(rootId: int): string {
    resetCodegen()
    emitRuntimeDefs()
    registerAllDecls(rootId)
    emitGlobalsAndCode(rootId)
    return `; ModuleID = 'simplescript'\nsource_filename = "simplescript"\n\n${strConsts}\n${irBuf}`
}

function generateToFile(rootId: int, outFile: string) {
    resetCodegen()
    irOutFile = outFile
    writeFile(outFile, "")
    writeFile(`${outFile}.str`, "")
    emitRuntimeDefs()
    registerAllDecls(rootId)
    emitGlobalsAndCode(rootId)
    irOutFile = ""
    const body = readFile(outFile)
    writeFile(outFile, `; ModuleID = 'simplescript'\nsource_filename = "simplescript"\n\n${readFile(`${outFile}.str`)}\n${body}`)
}

// ── Builtin function name mapping ─────────────────────────────

let builtinMap = ""
let builtinMapReady = 0

function initBuiltinMap() {
    if (builtinMapReady == 1) { return }
    builtinMap = Map()
    // Exceptions (name doesn't match ss_ + callee)
    builtinMap.set("args", "ss_argCount")
    builtinMap.set("arg", "ss_argGet")
    builtinMap.set("Map", "ss_mapNew")
    // Math.xxx() → ss_xxx
    builtinMap.set("Math_sqrt", "ss_sqrt")
    builtinMap.set("Math_abs", "ss_abs")
    builtinMap.set("Math_floor", "ss_floor")
    builtinMap.set("Math_ceil", "ss_ceil")
    builtinMap.set("Math_round", "ss_round")
    builtinMap.set("Math_pow", "ss_pow")
    builtinMap.set("Math_log", "ss_log")
    builtinMap.set("Math_sin", "ss_sin")
    builtinMap.set("Math_cos", "ss_cos")
    builtinMap.set("Math_random", "ss_random")
    builtinMap.set("Math_min", "ss_min")
    builtinMap.set("Math_max", "ss_max")
    // All standard builtins: ss_ + callee
    // Math functions moved to Math.xxx() — NOT in builtinMap
    const names = "println,print,readLine,readFile,writeFile,appendFile,exit,system,parseInt,parseDouble,timeMs,timeUnix,tcpListen,tcpAccept,tcpRead,tcpWrite,tcpWriteBytes,tcpClose,getenv,mkdir,mkdirp,fileExists,fileSize,removeFile,renameFile,listDir,sha256,charCodeAt,fromCharCode,base64Encode,base64Decode,strcmp"
    const parts = names.split(",")
    for (n in parts) {
        builtinMap.set(n, `ss_${n}`)
    }
    builtinMapReady = 1
}

function runtimeName(callee: string): string {
    initBuiltinMap()
    // User-defined functions take priority over builtins
    if (funcRetTypes.has(callee) == 1) {
        // But NOT for built-in class methods (Math_min etc.) — always use builtinMap
        if (builtinMap.has(callee) == 1) {
            return builtinMap.getString(callee)
        }
        return callee
    }
    if (builtinMap.has(callee) == 1) {
        return builtinMap.getString(callee)
    }
    return callee
}

