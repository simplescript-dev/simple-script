// SimpleScript Bootstrap Code Generator
// Walks the Map-based AST and produces LLVM IR text (.ll format).
// Uses SSA registers (%1, %2, ...) and named allocas for variables.

import { nGetKind, nGetS1, nGetS2, nGetS3, nGetI1, nGetI2, nGetI3, nGetI4, nGetList, classTypeParams } from "./parse/parser"
import { interpClearComptimeIR, interpClearComptimeSS, ctVal, isCt, payload, constVal, reg, materialize, initTypedValue, allocTv, newTvInt, newTvString, newTvType, newTvBool, newTvNull, newTvArray, tvKindOf, tvIntOf, tvStringOf } from "./eval/interp_core"
import { flushComptimeSS, flushComptimeIR, fullyRegisterCtClass, preScanCodegenCtClassesInStmts, flushPendingCtClasses, pendingCtClassIds } from "./eval/ct_driver"
import { registerInterface, generateInterfaceDispatchers } from "./gen/gen_iface"
import { internPoolGetOrInsert } from "./intern_pool"
import { irLabel, irAlloca, irLoad, irStore, irGEP, irICmp, irBr, irBrCond, irRet, irRetVoid, irAdd, irSub, irMul, irCall, irCallVoid, irSext, irZext, irSelect, irSDiv, irOr, irTrunc, irPtrToInt, irIntToPtr, irLoadArrayData } from "./gen/ir_builder"

// ── State ─────────────────────────────────────────────────────

let irBuf = ""
let strConsts = ""
let strCount = 0
let irOutFile = ""
let strOutFile = ""
let regCount = 0
let regTable: Array<string> = []
let ctVars = new Map()
let ctInvalidated = new Map()
let ctFuncNodes = new Map()
let ctScopeStack: Array<string> = []
let ctCallCounter = 0
let comptimeDepth = 0
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

// Function registry moved to gen_registry.ss (funcRetTypes, funcDefaults, funcParamCount, etc.)
let breakLabel = ""
let continueLabel = ""
// RC state moved to gen_rc.ss (localPtrVars, rcBlockDepth, blockPtrVarStack, etc.)
let enumValues = ""
let enumTypes = ""
let enumDeclNodes = ""
let enumReady = 0
let isThreadClosure = 0    // D082 Phase 3: set to 1 when generating Thread.start arrow

// Inline comptime expression cache (evaluated once in inferType, read in genExpr)
let comptimeExprType = new Map()
let comptimeExprLiteral = new Map()

// Compile-time constant bindings (D088: for-in unrolling propagates field names)
let comptimeConsts = new Map()

// D112: `const T = comptime { return X }` 的 alias 并入 ctVars(key `${currentFunc}:${name}` / `:${name}`),
// value = ctVal(interpNewType(X))。ctLookupTypeVal 双 scope 反查 type ctVal,供 resolveCtTypeAlias(string)
// 与 evalIdent(int) 共用,避免 dual-scope 查询重复实现膨胀 Dispatch 深度。
function ctLookupTypeVal(name: string): int {
    const k1 = `${currentFunc}:${name}`
    const k2 = `:${name}`
    const key = ctVars.has(k1) == 1 ? k1 : (ctVars.has(k2) == 1 ? k2 : "")
    const v = key == "" ? 0 : parseInt(ctVars.getString(key))
    if (v != 0 && isCt(v) == 1 && interpType(payload(v)) == "type") { return v }
    return 0
}
function resolveCtTypeAlias(name: string): string {
    const v = ctLookupTypeVal(name)
    return v == 0 ? name : tvStringOf(payload(v))
}

// Generic function state (monomorphization)
let genericFuncNodes = ""
let specializedFuncs = ""
let genericTypeSubs = ""
let genericSpecDefs = ""
let specFuncName = ""
// Generic class state (monomorphization)
let genericClassNodes = ""
let specializedClasses = ""
let specClassName = ""

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

// framework annotation handling 留给 Phase 3 eval core；sub-e 只承接符号
let annClassNodeIds: Array<string> = []
let annClassAnnNames: Array<string> = []

function registerAnnotation(annName: string, handlerFuncName: string) {
}

function collectClassAnnotations(classId: int) {
}

function emitAnnotationInits() {
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
// Register a single FUNC_DECL node: retType, paramCount, overloads, generics, defaults.
// Used by registerAllDecls and comptime @comptimeEmit processing.
function registerFuncDeclNode(sid: int) {
    const fname = nGetS1(sid)
    ctFuncNodes.set(fname, `${sid}`)
    let fret = stripNullableCG(nGetS2(sid))
    if (fret == "") { fret = "void" }
    funcRetTypes.set(fname, fret)
    const fparams = nGetList(sid)
    const fSig = paramSig(fparams)
    if (fSig != "") {
        funcRetTypes.set(`${fname}_${fSig}`, fret)
        funcParamCount.set(`${fname}_${fSig}`, funcParamCount.getString(fname) ?? "0")
    }
    trackOverload(fname)
    if (nGetS3(sid) != "") {
        genericFuncNodes.set(fname, `${sid}`)
    }
    if (fparams != "") {
        const fps = fparams.split(",")
        let pCount = 0
        let defaults = ""
        for (fp in fps) {
            const fpId = parseInt(fp)
            if (fpId > 0 && nGetKind(fpId) == "PARAM") {
                let defId = nGetI1(fpId)
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
                    defaults = listAppendStr(defaults, `${pCount}:${defId}`)
                }
                funcParamTypes.set(`${fname}:${pCount}`, nGetS2(fpId))
                if (fSig != "") {
                    funcParamTypes.set(`${fname}_${fSig}:${pCount}`, nGetS2(fpId))
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

function registerAllDecls(rootId: int) {
    const stmtList0 = nGetList(rootId)
    if (stmtList0 == "") { return }
    const parts0 = stmtList0.split(",")
    registrationPhase = 1
    for (p0 in parts0) {
        const sid = parseInt(p0)
        if (sid <= 0) { continue }
        const sk = nGetKind(sid)
        if (sk == "FUNC_DECL") {
            registerFuncDeclNode(sid)
        }
        if (sk == "INTERFACE_DECL") {
            registerInterface(sid)
        }
        if (sk == "EXPR_STMT") {
            // Process compile-time annotationMapping() directives
            const amExpr = nGetI1(sid)
            if (amExpr > 0 && nGetKind(amExpr) == "CALL" && nGetS1(amExpr) == "annotationMapping") {
                const amArgs = nGetList(amExpr)
                if (amArgs != "") {
                    const amParts = amArgs.split(",")
                    if (amParts.length() >= 2) {
                        const amNameId = parseInt(amParts[0])
                        const amHandlerId = parseInt(amParts[1])
                        if (amNameId > 0 && nGetKind(amNameId) == "STRING_LIT" && amHandlerId > 0 && nGetKind(amHandlerId) == "IDENT") {
                            registerAnnotation(nGetS1(amNameId), nGetS1(amHandlerId))
                        }
                    }
                }
            }
        }
        if (sk == "CLASS_DECL") {
            registerClass(sid)
            // Track generic classes for monomorphization
            if (classTypeParams(sid) != "") {
                genericClassNodes.set(nGetS1(sid), `${sid}`)
            }
            collectClassAnnotations(sid)
        }
        if (sk == "ENUM_DECL") {
            registerEnum(sid)
        }
    }
    // Resolve inheritance after all classes are registered
    resolveInheritance()
    // Build vtable for classes in inheritance hierarchies
    buildClassVtables()
    // Emit struct types for generic parents deferred during registration
    emitDeferredStructDefs()
    registrationPhase = 0
    // Assign dtor tags to classes with ptr fields
    assignClassDtorTags()
    // Detect cyclic ownership and mark non-owning container fields
    detectCyclicOwnership()
    // Generate interface dispatch functions (switch on class_id)
    generateInterfaceDispatchers()
}

function isTopLevelDecl(id: int): int {
    const k = nGetKind(id)
    if (k == "VAR_DECL") { return 1 }
    if (k == "FUNC_DECL") { return 1 }
    if (k == "CLASS_DECL") { return 1 }
    if (k == "ENUM_DECL") { return 1 }
    if (k == "INTERFACE_DECL") { return 1 }
    if (k == "ANNOTATION") { return 1 }
    return 0
}

function emitGlobalsAndCode(rootId: int) {
    const sl = nGetList(rootId)
    if (sl == "") { return }
    const parts = sl.split(",")
    // 预扫描 const X = comptime { class ... } 模式(含函数体内),提前注册元数据 +
    // 登记 W→Wrap alias,让 emitGlobalVars / 函数体 genVarDecl 跑到 COMPTIME_EXPR 时
    // genClassDecl 的 dedup 命中,不会重复 push,flushPendingCtClasses 只发射一次 IR。
    preScanCodegenCtClassesInStmts(sl)
    emitGlobalVars(sl)
    emitIR("")
    // Comptime blocks in global inits may declare classes; register & emit them
    // before downstream genStmt uses classFields for `new X(...)` lookup.
    flushPendingCtClasses()

    let hasMain = 0
    let bareStmts = ""
    for (x in parts) {
        const s = parseInt(x)
        if (s <= 0) { continue }
        if (nGetKind(s) == "FUNC_DECL" && nGetS1(s) == "main") { hasMain = 1 }
        if (isTopLevelDecl(s) == 0) { bareStmts = listAppend(bareStmts, s) }
    }

    for (x2 in parts) {
        const s2 = parseInt(x2)
        if (s2 <= 0) { continue }
        if (nGetKind(s2) == "VAR_DECL") { continue }
        if (nGetKind(s2) == "FUNC_DECL" && nGetS3(s2) != "") { continue }
        if (nGetKind(s2) == "CLASS_DECL" && genericClassNodes.has(nGetS1(s2)) == 1) { continue }
        if (hasMain == 0 && isTopLevelDecl(s2) == 0) { continue }
        genStmt(s2)
    }

    if (hasMain == 0 && bareStmts != "") {
        currentFunc = "main"
        emitMainProlog()
        const bareParts = bareStmts.split(",")
        for (bs in bareParts) {
            const bsId = parseInt(bs)
            if (bsId > 0) { genStmt(bsId) }
        }
        emitReleaseFnLocals()
        emitReleaseLocals()
        emitIR("  ret i32 0")
        emitIR("}")
        emitIR("")
        flushArrowDefs()
        currentFunc = ""
    }
}

function resetCodegen() {
    // Reset guard flags so init functions re-create fresh Maps
    varTypesReady = 0
    varAliasReady = 0
    classStateReady = 0
    initCodegen()
    initClassState()
    initFuncRegistry()
    initVarAliases()
    // Comptime buffers
    interpClearComptimeIR()
    interpClearComptimeSS()
    comptimeConsts = new Map()
    // IR output
    irBuf = ""
    strConsts = ""
    strCount = 0
    strOutFile = ""
    // SSA counters
    regCount = 0
    regTable = []
    ctVars = new Map()
    ctFuncNodes = new Map()
    ctScopeStack = []
    ctCallCounter = 0
    comptimeDepth = 0
    labelCount = 0
    varCounter = 0
    // Function context
    currentFunc = ""
    terminated = 0
    breakLabel = ""
    continueLabel = ""
    // RC state (gen_rc.ss)
    initRcState()
    // PIR state (gen_pir.ss)
    initPir()
    // Enum / routes
    enumValues = ""
    enumTypes = ""
    enumDeclNodes = ""
    enumReady = 0
    annClassNodeIds = []
    annClassAnnNames = []
    // Arrow functions (gen_exprs.ss)
    arrowCount = 0
    arrowDefs = ""
    // Generic function monomorphization
    genericFuncNodes = Map()
    specializedFuncs = Map()
    genericTypeSubs = Map()
    genericSpecDefs = ""
    specFuncName = ""
    // Generic class monomorphization
    genericClassNodes = Map()
    specializedClasses = Map()
    specClassName = ""
    // Generic class inheritance deferred state
    registrationPhase = 0
    deferredStructDefs = ""
    specClassNodeId = Map()
    specClassTypeArgs = Map()
    specClassGenerated = Map()
    // Global var init tracking (gen_stmts.ss)
    globalInitIds = ""
}

function ctPopScope() {
    let ns: Array<string> = []
    let i = 0
    while (i < ctScopeStack.length() - 1) {
        ns = ns.push(ctScopeStack[i])
        i = i + 1
    }
    ctScopeStack = ns
}

let runtimeCacheObj = "/tmp/ss_rt_cache.o"
let runtimeCacheDecls = "/tmp/ss_rt_cache.decls"
let useRuntimeCache = 0

function buildRuntimeCache() {
    const rtLL = "/tmp/ss_rt_cache.ll"
    resetCodegen()
    irOutFile = rtLL
    writeFile(rtLL, "")
    writeFile(`${rtLL}.str`, "")
    emitRuntimeDefs()
    irOutFile = ""
    const rtBody = readFile(rtLL)
    writeFile(rtLL, `; ModuleID = 'ss_runtime'\nsource_filename = "ss_runtime"\n\n${rtBody}`)
    if (system(`llc-18 -filetype=obj ${rtLL} -o ${runtimeCacheObj}`) != 0) {
        system(`rm -f ${runtimeCacheObj} ${runtimeCacheDecls} ${rtLL}`)
        return
    }
    // Generate declarations from runtime IR
    // 1. Function declares
    system(`grep '^define ' ${rtLL} | grep -v '^define internal ' | sed 's/define /declare /;s/ {$//' > ${runtimeCacheDecls}`)
    // 2. Libc declares
    system(`grep '^declare ' ${rtLL} >> ${runtimeCacheDecls}`)
    // 3. Runtime string constants as external
    system(`grep '^@\.rt\.' ${rtLL} | sed 's/ = constant \(\[[^]]*\]\).*/= external constant \1/' >> ${runtimeCacheDecls}`)
    // 4. @stdin/@stdout and type definitions
    system(`grep '^@stdin\|^@stdout' ${rtLL} >> ${runtimeCacheDecls}`)
    system(`grep '^%TypeInfo\|^%ObjHeader' ${rtLL} >> ${runtimeCacheDecls}`)
    // 5. Runtime globals as external (auto-extracted from .ll)
    system(`grep '^@ss_' ${rtLL} | sed 's/ = global / = external global /;s/ zeroinitializer.*//;s/ null.*//;s/ 0, align [0-9]*//;s/ 0$//' >> ${runtimeCacheDecls}`)
    system(`rm -f ${rtLL} ${rtLL}.str`)
}

function generateToFile(rootId: int, outFile: string) {
    resetCodegen()
    irOutFile = outFile
    writeFile(outFile, "")
    writeFile(`${outFile}.str`, "")
    if (useRuntimeCache == 1 && fileExists(runtimeCacheDecls) == 1 && fileExists(runtimeCacheObj) == 1) {
        appendFile(outFile, readFile(runtimeCacheDecls))
    } else {
        emitRuntimeDefs()
        useRuntimeCache = 0
    }
    registerAllDecls(rootId)
    emitGlobalsAndCode(rootId)
    flushPendingCtClasses()
    generateDeferredSpecializations()
    irOutFile = ""
    const body = readFile(outFile)
    writeFile(outFile, `; ModuleID = 'simplescript'\nsource_filename = "simplescript"\n\n${readFile(`${outFile}.str`)}\n${body}`)
}

// Builtin function name mapping moved to gen_registry.ss (builtinMap, runtimeName)

