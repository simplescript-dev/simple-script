// SimpleScript Bootstrap Code Generator
// Walks the Map-based AST and produces LLVM IR text (.ll format).
// Uses SSA registers (%1, %2, ...) and named allocas for variables.

import { nGetKind, nGetS1, nGetS2, nGetS3, nGetI1, nGetI2, nGetI3, nGetI4, nGetList, classTypeParams } from "./parser"
import { interpClearComptimeIR, interpClearComptimeSS } from "./interp"

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

// ── IR Builder Helpers ───────────────────────────────────────

function irLabel(name: string) {
    emitIR(`${name}:`)
}

function irAlloca(dst: string, ty: string, align: int) {
    emitIR(`  %${dst} = alloca ${ty}, align ${align}`)
}

function irLoad(dst: string, ty: string, ptr: string) {
    emitIR(`  %${dst} = load ${ty}, ptr ${ptr}`)
}

function irStore(ty: string, val: string, ptr: string) {
    emitIR(`  store ${ty} ${val}, ptr ${ptr}`)
}

function irGEP(dst: string, baseTy: string, base: string, idx: string) {
    emitIR(`  %${dst} = getelementptr ${baseTy}, ptr ${base}, i64 ${idx}`)
}

function irICmp(dst: string, op: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = icmp ${op} ${ty} ${a}, ${b}`)
}

function irBr(label: string) {
    emitIR(`  br label %${label}`)
}

function irBrCond(cond: string, thenL: string, elseL: string) {
    emitIR(`  br i1 %${cond}, label %${thenL}, label %${elseL}`)
}

function irRet(ty: string, val: string) {
    emitIR(`  ret ${ty} ${val}`)
}

function irRetVoid() {
    emitIR("  ret void")
}

function irAdd(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = add ${ty} ${a}, ${b}`)
}

function irSub(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = sub ${ty} ${a}, ${b}`)
}

function irMul(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = mul ${ty} ${a}, ${b}`)
}

function irCall(dst: string, retTy: string, func: string, args: string) {
    emitIR(`  %${dst} = call ${retTy} @${func}(${args})`)
}

function irCallVoid(func: string, args: string) {
    emitIR(`  call void @${func}(${args})`)
}

function irSext(dst: string, fromTy: string, val: string, toTy: string) {
    emitIR(`  %${dst} = sext ${fromTy} ${val} to ${toTy}`)
}

function irZext(dst: string, fromTy: string, val: string, toTy: string) {
    emitIR(`  %${dst} = zext ${fromTy} ${val} to ${toTy}`)
}

function irSelect(dst: string, cond: string, ty: string, thenVal: string, elseVal: string) {
    emitIR(`  %${dst} = select i1 %${cond}, ${ty} ${thenVal}, ${ty} ${elseVal}`)
}

function irSDiv(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = sdiv ${ty} ${a}, ${b}`)
}

function irOr(dst: string, ty: string, a: string, b: string) {
    emitIR(`  %${dst} = or ${ty} ${a}, ${b}`)
}

function irTrunc(dst: string, fromTy: string, val: string, toTy: string) {
    emitIR(`  %${dst} = trunc ${fromTy} ${val} to ${toTy}`)
}

function irPtrToInt(dst: string, val: string, toTy: string) {
    emitIR(`  %${dst} = ptrtoint ptr ${val} to ${toTy}`)
}

function irIntToPtr(dst: string, fromTy: string, val: string) {
    emitIR(`  %${dst} = inttoptr ${fromTy} ${val} to ptr`)
}

// Load array data buffer pointer from header slot 2
function irLoadArrayData(dst: string, arr: string) {
    irGEP(`${dst}p`, "i64", arr, "2")
    irLoad(`${dst}_i`, "i64", `%${dst}p`)
    irIntToPtr(dst, "i64", `%${dst}_i`)
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

// Flush @comptimeEmit SS source: tokenize → parse → multi-pass codegen.
// Shared by COMPTIME_BLOCK (gen_stmts) and COMPTIME_EXPR (gen_types).
function flushComptimeSS() {
    const fss = interpGetComptimeSS()
    if (fss == "") { return }
    const fssTokens = tokenize(fss)
    const fssRoot = parse(fssTokens)
    const fssList = nGetList(fssRoot)
    if (fssList != "") {
        const fssParts = fssList.split(",")
        // Pass 0: VAR_DECL → global vars
        const fssSavedFunc = currentFunc
        currentFunc = ""
        for (fp in fssParts) {
            const fsSid = parseInt(fp)
            if (fsSid > 0 && nGetKind(fsSid) == "VAR_DECL") { genGlobalVar(fsSid) }
        }
        currentFunc = fssSavedFunc
        // Pass 1: CLASS_DECL/ENUM_DECL/INTERFACE_DECL → register before codegen
        for (fp in fssParts) {
            const fsSid = parseInt(fp)
            if (fsSid <= 0) { continue }
            const fsKind = nGetKind(fsSid)
            if (fsKind == "CLASS_DECL") {
                registerClass(fsSid)
                collectClassAnnotations(fsSid)
                resolveInheritanceForClass(nGetS1(fsSid))
                assignDtorTagForClass(nGetS1(fsSid))
            }
            if (fsKind == "ENUM_DECL") { registerEnum(fsSid) }
            if (fsKind == "INTERFACE_DECL") { registerInterface(fsSid) }
        }
        // Pass 2: FUNC_DECL → register
        for (fp in fssParts) {
            const fsSid = parseInt(fp)
            if (fsSid > 0 && nGetKind(fsSid) == "FUNC_DECL") { registerFuncDeclNode(fsSid) }
        }
        // Pass 3: codegen (skip VAR_DECL, already emitted)
        for (fp in fssParts) {
            const fsSid = parseInt(fp)
            if (fsSid > 0 && nGetKind(fsSid) != "VAR_DECL") { genStmt(fsSid) }
        }
        // Pass 4: generate interface dispatchers (idempotent — skips already emitted)
        generateInterfaceDispatchers()
    }
    interpClearComptimeSS()
}

// Flush comptime IR buffer emitted by emit() calls.
function flushComptimeIR() {
    const fir = interpGetComptimeIR()
    if (fir != "") { emitIR(fir); interpClearComptimeIR() }
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

function emitGlobalsAndCode(rootId: int) {
    const sl = nGetList(rootId)
    if (sl == "") { return }
    const parts = sl.split(",")
    for (x1 in parts) { const s1 = parseInt(x1); if (s1 > 0 && nGetKind(s1) == "VAR_DECL") { genGlobalVar(s1) } }
    emitIR("")
    for (x2 in parts) {
        const s2 = parseInt(x2)
        if (s2 <= 0) { continue }
        if (nGetKind(s2) == "VAR_DECL") { continue }
        // Skip generic functions — emitted on-demand at call sites
        if (nGetKind(s2) == "FUNC_DECL" && nGetS3(s2) != "") { continue }
        // Skip generic classes — emitted on-demand at new expressions
        if (nGetKind(s2) == "CLASS_DECL" && genericClassNodes.has(nGetS1(s2)) == 1) { continue }
        genStmt(s2)
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
    resetAnnotationState()
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

function generate(rootId: int): string {
    resetCodegen()
    emitRuntimeDefs()
    registerAllDecls(rootId)
    emitGlobalsAndCode(rootId)
    generateDeferredSpecializations()
    return `; ModuleID = 'simplescript'\nsource_filename = "simplescript"\n\n${strConsts}\n${irBuf}`
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
    generateDeferredSpecializations()
    irOutFile = ""
    const body = readFile(outFile)
    writeFile(outFile, `; ModuleID = 'simplescript'\nsource_filename = "simplescript"\n\n${readFile(`${outFile}.str`)}\n${body}`)
}

// Builtin function name mapping moved to gen_registry.ss (builtinMap, runtimeName)

