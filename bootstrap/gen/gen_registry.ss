// Function/method registry for bootstrap codegen
// Manages return types, parameter counts, defaults, overloads, and builtin name mapping.

// ── Registry state ──────────────────────────────────────────

let funcRetTypes = ""
let funcRetReady = 0
let funcDefaults = ""    // "funcName" -> "paramIdx:defaultNodeId,..."
let funcParamCount = ""  // "funcName" -> param count
let funcParamTypes = ""  // "funcName:paramIndex" -> SS type
let methodRetTypes = ""  // "methodName" -> return type (built-in method fallback)
let overloadCount = ""
let overloadReady = 0
let builtinMap = ""
let builtinMapReady = 0

// ── Init ────────────────────────────────────────────────────

function initFuncRegistry() {
    funcRetReady = 0
    initFuncRetTypes()
    initBuiltinMap()
    overloadCount = new Map()
    overloadReady = 1
}

function trackOverload(name: string) {
    if (overloadCount.has(name) == 1) {
        const cnt = parseInt(overloadCount.getString(name))
        overloadCount.set(name, `${cnt + 1}`)
    } else {
        overloadCount.set(name, "1")
    }
}

// Register a class method's return type under both base (`Cls_m`) and
// overload-mangled (`Cls_m_sig`) keys, plus overload tracking. Keep the three
// ops together so callers can't drift (gen_generic_class.ss once missed trackOverload).
// I018 §路径 A:同时注册 funcParamCount(形参数,不含 this),供 bootstrap/eval/method_call.ss
// invoke sentinel 按 arity 追加 runtime args。必须在 pre-register 阶段 set(早于任何 dispatch
// 函数 emit),否则先 emit 的 call site 查不到 param count,退化到单 this 参路径。
function registerClassMethodRetType(className: string, methodId: int, retType: string) {
    const baseName = `${className}_${funcName(methodId)}`
    funcRetTypes.set(baseName, retType)
    const paramList = funcParams(methodId)
    let pCount = 0
    const mSig = paramSig(paramList)
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                // I021bc — funcParamTypes class method 路径补全(对称 codegen.ss:107-111 普通函数)。
                // invoke sentinel (method_call.ss) 按 funcParamTypes[mangled:idx] 分派 cast emit,
                // V=int → ss_parseInt、V=double → ss_parseDouble、V=string/默认 → ptr 透传。
                funcParamTypes.set(`${baseName}:${pCount}`, nGetS2(pId))
                if (mSig != "") { funcParamTypes.set(`${baseName}_${mSig}:${pCount}`, nGetS2(pId)) }
                pCount = pCount + 1
            }
        }
    }
    funcParamCount.set(baseName, `${pCount}`)
    if (mSig != "") { funcRetTypes.set(`${baseName}_${mSig}`, retType) }
    trackOverload(baseName)
}

function initFuncRetTypes() {
    if (funcRetReady == 1) { return }
    funcRetTypes = Map()
    funcDefaults = Map()
    funcParamCount = Map()
    funcParamTypes = Map()
    // Map method return types (class registration in initClassState)
    funcRetTypes.set("Map_set", "void")
    funcRetTypes.set("Map_get", "i64")
    funcRetTypes.set("Map_getString", "string")
    funcRetTypes.set("Map_has", "int")
    funcRetTypes.set("Map_delete", "void")
    funcRetTypes.set("Map_size", "int")
    funcRetTypes.set("Map_keys", "Array<string>")
    funcRetTypes.set("Map_new", "Map")
    // Set method return types (Map wrapper, D021)
    funcRetTypes.set("Set_add", "void")
    funcRetTypes.set("Set_has", "int")
    funcRetTypes.set("Set_remove", "void")
    funcRetTypes.set("Set_size", "int")
    funcRetTypes.set("Set_values", "string")
    funcRetTypes.set("Set_new", "Set")
    // Math method return types (class registration in initClassState)
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
    funcRetTypes.set("Math_tan", "double")
    funcRetTypes.set("Math_asin", "double")
    funcRetTypes.set("Math_acos", "double")
    funcRetTypes.set("Math_atan", "double")
    funcRetTypes.set("Math_atan2", "double")
    funcRetTypes.set("Math_exp", "double")
    funcRetTypes.set("Math_log10", "double")
    funcRetTypes.set("Math_log2", "double")
    funcRetTypes.set("Math_trunc", "double")
    funcRetTypes.set("Math_sign", "double")
    funcRetTypes.set("Math_hypot", "double")
    funcRetTypes.set("Math_cbrt", "double")
    funcRetTypes.set("Math_fmod", "double")
    funcRetTypes.set("Math_randomInt", "int")
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
    funcRetTypes.set("shell", "string")
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
    funcRetTypes.set("tcpWriteBytes", "int")
    funcRetTypes.set("tcpConnect", "int")
    funcRetTypes.set("tcpReadBytes", "int")
    funcRetTypes.set("writeDoubleLE", "int")
    funcRetTypes.set("readDoubleLE", "double")
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
    funcRetTypes.set("Set", "Set")
    // D079: test framework
    funcRetTypes.set("test", "void")
    // D080: exec process capture
    funcRetTypes.set("exec", "ExecResult")
    // D081: inotify file watcher
    funcRetTypes.set("_ss_inotify_init", "int")
    funcRetTypes.set("_ss_inotify_add_watch", "int")
    funcRetTypes.set("_ss_inotify_poll", "string")
    funcRetTypes.set("_ss_inotify_close", "void")
    // D082: ref/watch reactive concurrency
    funcRetTypes.set("ref", "Ref")
    funcRetTypes.set("watch", "void")
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
    methodRetTypes.set("keys", "Array<string>")
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
    // D082 Phase 4: Channel methods
    methodRetTypes.set("send", "void")
    methodRetTypes.set("receive", "i64")
    methodRetTypes.set("close", "void")
    methodRetTypes.set("find", "int")
    methodRetTypes.set("findIndex", "int")
    methodRetTypes.set("some", "int")
    methodRetTypes.set("every", "int")
    methodRetTypes.set("includes", "int")
    methodRetTypes.set("forEach", "void")
    methodRetTypes.set("add", "void")
    methodRetTypes.set("remove", "void")
    methodRetTypes.set("values", "string")
    funcRetReady = 1
}

// ── Builtin function name mapping ───────────────────────────

function initBuiltinMap() {
    if (builtinMapReady == 1) { return }
    builtinMap = Map()
    // Exceptions (name doesn't match ss_ + callee)
    builtinMap.set("args", "ss_argCount")
    builtinMap.set("arg", "ss_argGet")
    builtinMap.set("Map", "ss_mapNew")
    builtinMap.set("Set", "ss_mapNew")
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
    builtinMap.set("Math_tan", "ss_tan")
    builtinMap.set("Math_asin", "ss_asin")
    builtinMap.set("Math_acos", "ss_acos")
    builtinMap.set("Math_atan", "ss_atan")
    builtinMap.set("Math_atan2", "ss_atan2")
    builtinMap.set("Math_exp", "ss_exp")
    builtinMap.set("Math_log10", "ss_log10")
    builtinMap.set("Math_log2", "ss_log2")
    builtinMap.set("Math_trunc", "ss_trunc")
    builtinMap.set("Math_sign", "ss_sign")
    builtinMap.set("Math_hypot", "ss_hypot")
    builtinMap.set("Math_cbrt", "ss_cbrt")
    builtinMap.set("Math_fmod", "ss_fmod")
    builtinMap.set("Math_randomInt", "ss_randomInt")
    // All standard builtins: ss_ + callee
    const names = "println,print,readLine,readFile,writeFile,appendFile,exit,system,shell,parseInt,parseDouble,timeMs,timeUnix,tcpListen,tcpAccept,tcpRead,tcpWrite,tcpWriteBytes,tcpClose,tcpConnect,tcpReadBytes,getenv,mkdir,mkdirp,fileExists,fileSize,removeFile,renameFile,listDir,sha256,charCodeAt,fromCharCode,base64Encode,base64Decode,strcmp,writeDoubleLE,readDoubleLE"
    const parts = names.split(",")
    for (n in parts) {
        builtinMap.set(n, `ss_${n}`)
    }
    builtinMapReady = 1
}

// ── Lookup ──────────────────────────────────────────────────

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
