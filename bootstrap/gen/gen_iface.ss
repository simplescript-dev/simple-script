// Interface dispatch codegen (extracted from gen_class.ss)
//
// D138 Phase 1.5: arity-aware overload mangle —
//   methodNames entry 用 mangled key:单 arity = plain `${mName}`,overload arity =
//   `${mName}_${paramSig}` (与 class method `${className}_${mName}_${paramSig}` 同公约)。
//   ifaceMethodSigs 反映射存 paramSig,emit 时按 isOverloaded 选 class method symbol。

// D138 Phase 1.5: paramSig 反映射 — key `${ifaceName}.${mangledKey}`,value paramSig (空表示 plain)
let ifaceMethodSigs = new Map()

// Register interface declaration: store method names, return types, param info.
// D138 Phase 1.5: 双 pass — Pass 1 统计 mName 出现次数,Pass 2 对 overload mName 加 paramSig
// suffix(`${mName}_${paramSig}`)落 mangled methodNames entry;单 arity 走 plain backward compat。
function registerInterface(id: int) {
    const name = nGetS1(id)
    const ml = nGetList(id)
    if (ml == "") { ifaceMethodsCG.set(name, ""); return }
    const parts = ml.split(",")
    let mNameCount = new Map()
    for (p in parts) {
        const mId = parseInt(p)
        if (mId <= 0) { continue }
        const mName = nGetS1(mId)
        const cur = mNameCount.has(mName) == 1 ? parseInt(mNameCount.getString(mName)) : 0
        mNameCount.set(mName, `${cur + 1}`)
    }
    let methodNames = ""
    for (p in parts) {
        const mId = parseInt(p)
        if (mId <= 0) { continue }
        const mName = nGetS1(mId)
        const isOverload = parseInt(mNameCount.getString(mName)) >= 2 ? 1 : 0
        const paramList = nGetList(mId)
        const pSig = isOverload == 1 ? paramSig(paramList) : ""
        const mangledKey = pSig != "" ? `${mName}_${pSig}` : mName
        methodNames = listAppendStr(methodNames, mangledKey)
        ifaceMethodSigs.set(`${name}.${mangledKey}`, pSig)
        const mRet = nGetS2(mId)
        ifaceMethodRets.set(`${name}.${mangledKey}`, mRet != "" ? mRet : "void")
        // Store param info as "name:type,name:type,..."
        let paramStr = ""
        if (paramList != "") {
            const pps = paramList.split(",")
            for (pp in pps) {
                const ppId = parseInt(pp)
                if (ppId > 0 && nGetKind(ppId) == "PARAM") {
                    const pn = nGetS1(ppId)
                    const pt = nGetS2(ppId)
                    paramStr = listAppendStr(paramStr, `${pn}:${pt != "" ? pt : "int"}`)
                }
            }
        }
        ifaceMethodPars.set(`${name}.${mangledKey}`, paramStr)
    }
    ifaceMethodsCG.set(name, methodNames)
}

// D138 Phase 1.5: argsSig 反查 mangled candidate;methods 列表里命中 → 取 mangled dispatcher
// key(`${method}_${paramSig}`),否则 plain method backward compat(单 arity / 类型不匹配兜底)。
function pickIfaceDispatcherKey(ifaceName: string, method: string, argList: string): string {
    const methods = ifaceMethodsCG.has(ifaceName) == 1 ? ifaceMethodsCG.getString(ifaceName) : ""
    if (methods == "") { return method }
    const aSig = argsSig(argList)
    if (aSig == "") { return method }
    const candidate = `${method}_${aSig}`
    const wrapped = `,${methods},`
    return wrapped.contains(`,${candidate},`) == 1 ? candidate : method
}

// D138 Phase 3: class method overload 接口擦除 — paramSig 注册时用形参声明 class/接口名
// (`KeyHolder`),argsSig 用实参具体 class 名(`GeneratedKeyHolder`),`class A : Iface` 接口实现
// 路径下两者错位。precise sig miss 时沿 ifaceImplementors 反查每个 IDENT/NEW class 类型 arg
// 实现的接口替换试 mangled 候选。
function pickClassMethodKey(className: string, mName: string, argList: string): string {
    const resolved = `${className}_${mName}`
    if (isOverloaded(resolved) != 1) { return resolved }
    if (argList == "") { return resolved }
    const sig = argsSig(argList)
    if (sig != "" && funcRetTypes.has(`${resolved}_${sig}`) == 1) {
        return `${resolved}_${sig}`
    }
    return tryClassMethodErasureKey(resolved, argList)
}

function tryClassMethodErasureKey(resolved: string, argList: string): string {
    const parts = argList.split(",")
    let argSegs: Array<string> = []
    let argClasses: Array<string> = []
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0) {
            let cls = ""
            if (nGetKind(argId) == "IDENT") { cls = getObjClass(nGetS1(argId)) }
            else if (nGetKind(argId) == "NEW_EXPR") { cls = nGetS1(argId) }
            argClasses.push(cls)
            if (cls != "") {
                argSegs.push(cls)
            } else {
                argSegs.push(typeSig(inferType(argId)))
            }
        }
    }
    let i = 0
    while (i < argSegs.length()) {
        const cls = argClasses[i]
        if (cls != "") {
            const ifaceKeys = ifaceImplementors.keys()
            for (iface in ifaceKeys) {
                if (iface == "") { continue }
                const impls = ifaceImplementors.getString(iface)
                const wrapped = `,${impls},`
                if (wrapped.contains(`,${cls},`) == 1) {
                    let trySig = ""
                    let j = 0
                    while (j < argSegs.length()) {
                        if (trySig != "") { trySig = `${trySig}_` }
                        if (j == i) { trySig = `${trySig}${iface}` }
                        else { trySig = `${trySig}${argSegs[j]}` }
                        j = j + 1
                    }
                    if (funcRetTypes.has(`${resolved}_${trySig}`) == 1) {
                        return `${resolved}_${trySig}`
                    }
                }
            }
        }
        i = i + 1
    }
    return resolved
}

// Generate switch-based dispatch functions for all interface methods
function generateInterfaceDispatchers() {
    const ifaceList = ifaceMethodsCG.keys()
    for (iface in ifaceList) {
        if (iface == "") { continue }
        const methods = ifaceMethodsCG.getString(iface)
        if (methods == "") { continue }
        const impls = ifaceImplementors.has(iface) == 1 ? ifaceImplementors.getString(iface) : ""
        // D153 §F2: 空 impls 不 skip — emit dispatch fn body 走 unreachable 允许 link
        // (业界对标 C++ __cxa_pure_virtual / Rust unreachable!() / LLVM unreachable instruction trap)
        const mList = methods.split(",")
        for (mangledKey in mList) {
            if (mangledKey == "") { continue }
            emitIfaceDispatchFn(iface, mangledKey, impls)
        }
    }
}

// Track emitted dispatchers for idempotency (comptime may trigger re-generation)
let emittedDispatchers = new Map()

// Emit one dispatch function: @__iface_Shape_area(ptr %self, params...) { switch on class_id }
// D138 Phase 1.5: methodKey 是 mangled key(单 arity = plain mName / overload = `${mName}_${paramSig}`);
// 调 class method 时按 isOverloaded 选 plain 或 mangled symbol,与 class_method.ss:60-65 同公约。
function emitIfaceDispatchFn(iface: string, methodKey: string, impls: string) {
    const dispName = `__iface_${iface}_${methodKey}`
    if (emittedDispatchers.has(dispName) == 1) { return }
    emittedDispatchers.set(dispName, "1")
    const retStr = ifaceMethodRets.getString(`${iface}.${methodKey}`) ?? "void"
    const retLLVM = ssTypeToLLVM(retStr)
    funcRetTypes.set(dispName, retStr)
    // Recover plainMName + paramSig from methodKey (空 pSig → plain mName)
    const pSig = ifaceMethodSigs.has(`${iface}.${methodKey}`) == 1 ? ifaceMethodSigs.getString(`${iface}.${methodKey}`) : ""
    let plainMName = methodKey
    if (pSig != "") {
        const suffixLen = pSig.length() + 1
        plainMName = methodKey.substring(0, methodKey.length() - suffixLen)
    }
    // Build param signature from interface method declaration
    const parStr = ifaceMethodPars.has(`${iface}.${methodKey}`) == 1 ? ifaceMethodPars.getString(`${iface}.${methodKey}`) : ""
    let paramStrIR = "ptr %self"
    if (parStr != "") {
        const pParts = parStr.split(",")
        for (pp in pParts) {
            if (pp == "") { continue }
            const colonIdx = pp.indexOf(":")
            if (colonIdx < 0) { continue }
            const pName = pp.substring(0, colonIdx)
            const pType = pp.substring(colonIdx + 1, pp.length() - colonIdx - 1)
            paramStrIR = `${paramStrIR}, ${ssTypeToLLVM(pType)} %${pName}.arg`
        }
    }
    // Emit function header
    if (retLLVM == "void") {
        emitIR(`define void @${dispName}(${paramStrIR}) {`)
    } else {
        emitIR(`define ${retLLVM} @${dispName}(${paramStrIR}) {`)
    }
    emitIR("entry:")
    // D153 §F2: 空 impls → emit unreachable allow link(无 implementor 不可达,运行时 trap)
    if (impls == "") {
        emitIR("  unreachable")
        emitIR("}")
        emitIR("")
        return
    }
    // Load class_id from TypeInfo (slot 5)
    emitIR("  %ti.ptr = getelementptr %ObjHeader, ptr %self, i32 0, i32 1")
    emitIR("  %ti = load ptr, ptr %ti.ptr")
    emitIR("  %cid = getelementptr %TypeInfo, ptr %ti, i32 0, i32 5")
    emitIR("  %id = load i32, ptr %cid")
    let switchCases = ""
    const implList = impls.split(",")
    for (impl in implList) {
        if (impl == "") { continue }
        if (classIds.has(impl) == 0) { continue }
        const cid = classIds.getString(impl)
        switchCases = `${switchCases}\n    i32 ${cid}, label %impl.${impl}`
    }
    emitIR(`  switch i32 %id, label %__default [${switchCases}`)
    emitIR("  ]")
    for (impl in implList) {
        if (impl == "") { continue }
        if (classIds.has(impl) == 0) { continue }
        // Walk parent chain to find which class actually defines the method.
        // funcRetTypes 用 plain `${defClass}_${plainMName}` 反查(class method 注册时 plain key 必落地)。
        let defClass = impl
        while (defClass != "") {
            if (funcRetTypes.has(`${defClass}_${plainMName}`) == 1) { break }
            if (classParents.has(defClass) == 1) {
                defClass = classParents.getString(defClass)
            } else {
                defClass = impl
                break
            }
        }
        // 选 class method symbol — overload 时取 mangled `${defClass}_${plainMName}_${pSig}`,
        // 与 class_method.ss:60-65 同公约;否则 plain `${defClass}_${plainMName}` backward compat。
        let callTarget = `${defClass}_${plainMName}`
        if (pSig != "" && isOverloaded(`${defClass}_${plainMName}`) == 1) {
            callTarget = `${defClass}_${plainMName}_${pSig}`
        }
        emitIR(`impl.${impl}:`)
        if (retLLVM == "void") {
            emitIR(`  call void @${callTarget}(${paramStrIR})`)
            emitIR("  ret void")
        } else {
            emitIR(`  %r.${impl} = call ${retLLVM} @${callTarget}(${paramStrIR})`)
            emitIR(`  ret ${retLLVM} %r.${impl}`)
        }
    }
    emitIR("__default:")
    if (retLLVM == "void") {
        emitIR("  ret void")
    } else if (retLLVM == "ptr") {
        emitIR("  ret ptr null")
    } else if (retLLVM == "double") {
        emitIR("  ret double 0.0")
    } else {
        emitIR(`  ret ${retLLVM} 0`)
    }
    emitIR("}")
    emitIR("")
}
