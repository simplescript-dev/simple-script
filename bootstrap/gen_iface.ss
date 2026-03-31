// Interface dispatch codegen (extracted from gen_class.ss)

// Register interface declaration: store method names, return types, param info
function registerInterface(id: int) {
    const name = nGetS1(id)
    const ml = nGetList(id)
    if (ml == "") { ifaceMethodsCG.set(name, ""); return }
    let methodNames = ""
    const parts = ml.split(",")
    for (p in parts) {
        const mId = parseInt(p)
        if (mId <= 0) { continue }
        const mName = nGetS1(mId)
        methodNames = listAppendStr(methodNames, mName)
        const mRet = nGetS2(mId)
        ifaceMethodRets.set(`${name}.${mName}`, mRet != "" ? mRet : "void")
        // Store param info as "name:type,name:type,..."
        const paramList = nGetList(mId)
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
        ifaceMethodPars.set(`${name}.${mName}`, paramStr)
    }
    ifaceMethodsCG.set(name, methodNames)
}

// Generate switch-based dispatch functions for all interface methods
function generateInterfaceDispatchers() {
    const allIfaces = ifaceMethodsCG.keys()
    if (allIfaces == "") { return }
    const ifaceList = allIfaces.split("\n")
    for (iface in ifaceList) {
        if (iface == "") { continue }
        const methods = ifaceMethodsCG.getString(iface)
        if (methods == "") { continue }
        const impls = ifaceImplementors.has(iface) == 1 ? ifaceImplementors.getString(iface) : ""
        if (impls == "") { continue }
        const mList = methods.split(",")
        for (mName in mList) {
            if (mName == "") { continue }
            emitIfaceDispatchFn(iface, mName, impls)
        }
    }
}

// Emit one dispatch function: @__iface_Shape_area(ptr %self, params...) { switch on class_id }
function emitIfaceDispatchFn(iface: string, method: string, impls: string) {
    const dispName = `__iface_${iface}_${method}`
    const retStr = ifaceMethodRets.getString(`${iface}.${method}`) ?? "void"
    const retLLVM = ssTypeToLLVM(retStr)
    // Register return type for inferType
    funcRetTypes.set(dispName, retStr)
    // Build param signature from interface method declaration
    const parStr = ifaceMethodPars.has(`${iface}.${method}`) == 1 ? ifaceMethodPars.getString(`${iface}.${method}`) : ""
    let paramSig = "ptr %self"
    if (parStr != "") {
        const pParts = parStr.split(",")
        for (pp in pParts) {
            if (pp == "") { continue }
            const colonIdx = pp.indexOf(":")
            if (colonIdx < 0) { continue }
            const pName = pp.substring(0, colonIdx)
            const pType = pp.substring(colonIdx + 1, pp.length() - colonIdx - 1)
            paramSig = `${paramSig}, ${ssTypeToLLVM(pType)} %${pName}.arg`
        }
    }
    // Emit function header
    if (retLLVM == "void") {
        emitIR(`define void @${dispName}(${paramSig}) {`)
    } else {
        emitIR(`define ${retLLVM} @${dispName}(${paramSig}) {`)
    }
    emitIR("entry:")
    // Load class_id from TypeInfo (slot 5)
    emitIR("  %ti.ptr = getelementptr %ObjHeader, ptr %self, i32 0, i32 1")
    emitIR("  %ti = load ptr, ptr %ti.ptr")
    emitIR("  %cid = getelementptr %TypeInfo, ptr %ti, i32 0, i32 5")
    emitIR("  %id = load i32, ptr %cid")
    // Build switch cases
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
    // Emit case labels
    for (impl in implList) {
        if (impl == "") { continue }
        if (classIds.has(impl) == 0) { continue }
        // Find which class actually defines the method (walk parent chain)
        let defClass = impl
        while (defClass != "") {
            if (funcRetTypes.has(`${defClass}_${method}`) == 1) { break }
            if (classParents.has(defClass) == 1) {
                defClass = classParents.getString(defClass)
            } else {
                defClass = impl
                break
            }
        }
        emitIR(`impl.${impl}:`)
        if (retLLVM == "void") {
            emitIR(`  call void @${defClass}_${method}(${paramSig})`)
            emitIR("  ret void")
        } else {
            emitIR(`  %r.${impl} = call ${retLLVM} @${defClass}_${method}(${paramSig})`)
            emitIR(`  ret ${retLLVM} %r.${impl}`)
        }
    }
    // Default: return zero/null
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
