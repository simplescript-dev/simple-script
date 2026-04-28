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

// Generate switch-based dispatch functions for all interface methods
function generateInterfaceDispatchers() {
    const ifaceList = ifaceMethodsCG.keys()
    for (iface in ifaceList) {
        if (iface == "") { continue }
        const methods = ifaceMethodsCG.getString(iface)
        if (methods == "") { continue }
        const impls = ifaceImplementors.has(iface) == 1 ? ifaceImplementors.getString(iface) : ""
        if (impls == "") { continue }
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
