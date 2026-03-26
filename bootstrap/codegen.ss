// SimpleScript Bootstrap Code Generator
// Walks the Map-based AST and produces LLVM IR text (.ll format).
// Uses SSA registers (%1, %2, ...) and named allocas for variables.

import { nGetKind, nGetS1, nGetS2, nGetS3, nGetI1, nGetI2, nGetI3, nGetI4, nGetList } from "./parser"

// ── State ─────────────────────────────────────────────────────

let irBuf = ""
let strConsts = ""
let strCount = 0
let irOutFile = ""
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
    const llName = name + "." + varCounter
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
    return "%" + ln
}

let funcRetTypes = ""
let funcRetReady = 0
let classFields = ""     // "ClassName" -> "field1,field2,..."
let classFieldTypes = "" // "ClassName.field" -> "type"
let classMethods = ""    // "ClassName" -> "method1,method2,..."
let objClasses = ""      // "varName" -> "ClassName"
let classParents = ""    // "ClassName" -> "ParentClassName"
let funcDefaults = ""    // "funcName" -> "paramIdx:defaultNodeId,..."
let funcParamCount = ""  // "funcName" -> param count
let currentClassName = ""
let breakLabel = ""
let continueLabel = ""

function initFuncRetTypes() {
    if (funcRetReady == 1) { return }
    funcRetTypes = Map()
    classFields = Map()
    classFieldTypes = Map()
    classMethods = Map()
    objClasses = Map()
    classParents = Map()
    funcDefaults = Map()
    funcParamCount = Map()
    funcRetReady = 1
}

function initCodegen() {
    if (varTypesReady == 1) { return }
    varTypes = Map()
    varTypesReady = 1
}

function emitIR(s: string) {
    if (irOutFile != "") {
        appendFile(irOutFile, s + "\n")
    } else {
        irBuf = irBuf + s + "\n"
    }
}

function nextReg(): string {
    regCount = regCount + 1
    return "%" + regCount
}

function nextLabel(prefix: string): string {
    labelCount = labelCount + 1
    return prefix + "." + labelCount
}

function addStringConst(value: string): string {
    const name = "@.str." + strCount
    strCount = strCount + 1
    // Escape the string for LLVM IR c"..." format
    let escaped = ""
    let i = 0
    const sLen = value.length()
    while (i < sLen) {
        const ch = value.charAt(i)
        if (ch == "\n") { escaped = escaped + "\\0A" } else if (ch == "\r") { escaped = escaped + "\\0D" } else if (ch == "\t") { escaped = escaped + "\\09" } else if (ch == "\\") { escaped = escaped + "\\5C" } else if (ch == "\"") { escaped = escaped + "\\22" } else { escaped = escaped + ch }
        i = i + 1
    }
    const line = name + " = constant [" + (sLen + 1) + " x i8] c\"" + escaped + "\\00\"\n"
    if (irOutFile != "") {
        appendFile(irOutFile + ".str", line)
    } else {
        strConsts = strConsts + line
    }
    return name
}

// ── Runtime declarations ──────────────────────────────────────

function emitDeclGroup(ret: string, params: string, names: string) {
    const parts = names.split(",")
    for (n in parts) { emitIR("declare " + ret + " @" + n + "(" + params + ")") }
}

function emitRuntimeDecls() {
    emitIR("; Runtime declarations")
    emitDeclGroup("void", "ptr", "ym_println,ym_print,ym_arrayReverse,ym_arraySort")
    emitDeclGroup("void", "ptr, ptr", "ym_writeFile,ym_appendFile,ym_mapDelete")
    emitDeclGroup("ptr", "ptr", "ym_readFile,ym_trim,ym_toUpperCase,ym_toLowerCase,ym_getenv,ym_listDir,ym_sha256,ym_arrayToString,ym_mapKeys")
    emitDeclGroup("ptr", "ptr, ptr", "ym_string_concat,ym_split,ym_join,ym_arrayConcat")
    emitDeclGroup("i32", "ptr, ptr", "ym_string_eq,ym_string_ne,ym_startsWith,ym_endsWith,ym_contains,ym_indexOf,ym_mapHas")
    emitDeclGroup("i32", "ptr", "ym_parseInt,ym_stringLength,ym_arrayLen,ym_system,ym_mkdir,ym_mkdirp,ym_fileExists,ym_removeFile,ym_mapSize")
    emitDeclGroup("double", "double", "ym_sqrt,ym_abs,ym_floor,ym_ceil,ym_round,ym_log,ym_sin,ym_cos")
    emitDeclGroup("double", "double, double", "ym_pow,ym_min,ym_max")
    emitDeclGroup("i32", "i32", "ym_tcpListen,ym_tcpAccept")
    emitDeclGroup("i64", "ptr", "ym_arrayFirst,ym_arrayLast,ym_fileSize")
    emitDeclGroup("ptr", "i32", "ym_int_to_string,ym_newArray,ym_argGet,ym_fromCharCode")
    emitDeclGroup("void", "i32", "ym_exit,ym_tcpClose")
    // Unique signatures
    emitIR("declare ptr @ym_readLine()")
    emitIR("declare ptr @ym_double_to_string(double)")
    emitIR("declare ptr @ym_i64_to_string(i64)")
    emitIR("declare double @ym_parseDouble(ptr)")
    emitIR("declare double @ym_random()")
    emitIR("declare ptr @ym_replace(ptr, ptr, ptr)")
    emitIR("declare ptr @ym_charAt(ptr, i32)")
    emitIR("declare ptr @ym_repeat(ptr, i32)")
    emitIR("declare ptr @ym_substring(ptr, i32, i32)")
    emitIR("declare ptr @ym_padStart(ptr, i32, ptr)")
    emitIR("declare ptr @ym_padEnd(ptr, i32, ptr)")
    emitIR("declare i64 @ym_arrayGet(ptr, i32)")
    emitIR("declare void @ym_arraySet(ptr, i32, i64)")
    emitIR("declare ptr @ym_arrayPush(ptr, i64)")
    emitIR("declare i32 @ym_arrayIndexOf(ptr, i64)")
    emitIR("declare ptr @ym_arraySlice(ptr, i32, i32)")
    emitIR("declare void @ym_initArgs(i32, ptr)")
    emitIR("declare i32 @ym_argCount()")
    emitIR("declare i64 @ym_timeMs()")
    emitIR("declare i64 @ym_timeUnix()")
    emitIR("declare i32 @ym_renameFile(ptr, ptr)")
    emitIR("declare ptr @ym_tcpRead(i32, i32)")
    emitIR("declare i32 @ym_tcpWrite(i32, ptr)")
    emitIR("declare i32 @ym_charCodeAt(ptr, i32)")
    emitIR("declare i32 @ym_strcmp(ptr, ptr)")
    emitIR("declare ptr @ym_base64Encode(ptr)")
    emitIR("declare ptr @ym_base64Decode(ptr)")
    emitIR("declare ptr @ym_mapNew()")
    emitIR("declare void @ym_mapSet(ptr, ptr, i64)")
    emitIR("declare i64 @ym_mapGet(ptr, ptr)")
    emitIR("declare ptr @malloc(i64)")
    emitIR("")
}

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
            const fparams = nGetList(sid)
            if (fparams != "") {
                const fps = fparams.split(",")
                let pCount = 0
                let defaults = ""
                for (fp in fps) {
                    const fpId = parseInt(fp)
                    if (fpId > 0 && nGetKind(fpId) == "PARAM") {
                        const defId = nGetI1(fpId)
                        if (defId > 0) {
                            if (defaults == "") { defaults = pCount + ":" + defId } else { defaults = defaults + "," + pCount + ":" + defId }
                        }
                        pCount = pCount + 1
                    }
                }
                funcParamCount.set(fname, pCount + "")
                if (defaults != "") { funcDefaults.set(fname, defaults) }
            } else {
                funcParamCount.set(fname, "0")
            }
        }
        if (sk == "CLASS_DECL") { registerClass(sid) }
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
    initCodegen()
    initFuncRetTypes()
    irBuf = ""
    strConsts = ""
    strCount = 0
    regCount = 0
    labelCount = 0
}

function generate(rootId: int): string {
    resetCodegen()
    emitRuntimeDecls()
    registerAllDecls(rootId)
    emitGlobalsAndCode(rootId)
    return "; ModuleID = 'simplescript'\nsource_filename = \"simplescript\"\n\n" + strConsts + "\n" + irBuf
}

function generateToFile(rootId: int, outFile: string) {
    resetCodegen()
    irOutFile = outFile
    writeFile(outFile, "")
    writeFile(outFile + ".str", "")
    emitRuntimeDecls()
    registerAllDecls(rootId)
    emitGlobalsAndCode(rootId)
    irOutFile = ""
    const body = readFile(outFile)
    writeFile(outFile, "; ModuleID = 'simplescript'\nsource_filename = \"simplescript\"\n\n" + readFile(outFile + ".str") + "\n" + body)
}

// ── Builtin function name mapping ─────────────────────────────

function runtimeName(callee: string): string {
    // Only 3 exceptions; everything else is ym_ + callee
    if (callee == "args") { return "ym_argCount" }
    if (callee == "arg") { return "ym_argGet" }
    if (callee == "Map") { return "ym_mapNew" }
    // Check if ym_ prefixed function exists in known builtins
    const builtins = ",println,print,readLine,readFile,writeFile,appendFile,exit,system,parseInt,parseDouble,sqrt,abs,floor,ceil,round,pow,log,sin,cos,random,min,max,timeMs,tcpListen,tcpAccept,tcpRead,tcpWrite,tcpWriteBytes,tcpClose,getenv,timeUnix,mkdir,mkdirp,fileExists,fileSize,removeFile,renameFile,listDir,sha256,charCodeAt,fromCharCode,base64Encode,base64Decode,strcmp,"
    if (builtins.contains("," + callee + ",") == 1) { return "ym_" + callee }
    return callee
}

