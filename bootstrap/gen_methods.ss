// gen_methods.ss — Method call codegen: dispatcher, class methods, helpers
// Used by gen_exprs.ss via textual import.

import { genStringMethod, genHigherOrderMethod, genArrayMethod, genMapMethod, genSetMethod } from "./gen_builtins"

// ── Enum methods ────────────────────────────────────────────────

function genEnumValues(eName: string): string {
    const enumId = parseInt(enumDeclNodes.getString(eName))
    const vl = nGetList(enumId)
    const parts = vl.split(",")
    const count = parts.length()
    const isString = enumTypes.has(eName) == 1
    let arrCtor = "@ss_newArray"
    if (isString) { arrCtor = "@ss_newArrayPtr" }
    const arrReg = nextReg()
    emitIR(`  ${arrReg} = call ptr ${arrCtor}(i32 ${count})`)
    let idx = 0
    for (p in parts) {
        const vid = parseInt(p)
        if (vid > 0 && nGetKind(vid) == "ENUM_VARIANT") {
            const val = enumValues.getString(`${eName}.${nGetS1(vid)}`)
            if (isString) {
                const sR = addStringConst(val)
                const s64 = nextReg()
                emitIR(`  ${s64} = ptrtoint ptr ${sR} to i64`)
                emitIR(`  call void @ss_arraySet(ptr ${arrReg}, i32 ${idx}, i64 ${s64})`)
            } else {
                const i64R = nextReg()
                emitIR(`  ${i64R} = sext i32 ${val} to i64`)
                emitIR(`  call void @ss_arraySet(ptr ${arrReg}, i32 ${idx}, i64 ${i64R})`)
            }
            idx = idx + 1
        }
    }
    return arrReg
}

function genEnumNames(eName: string): string {
    const enumId = parseInt(enumDeclNodes.getString(eName))
    const vl = nGetList(enumId)
    const parts = vl.split(",")
    const count = parts.length()
    const arrReg = nextReg()
    emitIR(`  ${arrReg} = call ptr @ss_newArrayPtr(i32 ${count})`)
    let idx = 0
    for (p in parts) {
        const vid = parseInt(p)
        if (vid > 0 && nGetKind(vid) == "ENUM_VARIANT") {
            const sR = addStringConst(nGetS1(vid))
            const s64 = nextReg()
            emitIR(`  ${s64} = ptrtoint ptr ${sR} to i64`)
            emitIR(`  call void @ss_arraySet(ptr ${arrReg}, i32 ${idx}, i64 ${s64})`)
            idx = idx + 1
        }
    }
    return arrReg
}

// ── Optional method call ────────────────────────────────────────

// obj?.method() — if obj is "", return default; otherwise call normally
function genOptionalMethodCall(id: int): string {
    const objId = nGetI1(id)
    const objVal = genExpr(objId)
    const retType = inferType(id)
    const llRetType = ssTypeToLLVM(retType)

    // Alloca for result
    const resultAlloca = nextReg()
    emitIR(`  ${resultAlloca} = alloca ${llRetType}, align 8`)
    // Store default
    if (llRetType == "ptr") {
        const emptyStr = addStringConst("")
        emitIR(`  store ptr ${emptyStr}, ptr ${resultAlloca}, align 8`)
    } else {
        emitIR(`  store ${llRetType} 0, ptr ${resultAlloca}, align 8`)
    }

    // Check if obj is null
    const cmpR = nextReg()
    emitIR(`  ${cmpR} = icmp eq ptr ${objVal}, null`)
    const callLabel = nextLabel("opt.call")
    const endLabel = nextLabel("opt.end")
    emitIR(`  br i1 ${cmpR}, label %${endLabel}, label %${callLabel}`)

    // Call method normally (clear the optional flag so genMethodCall doesn't loop)
    // Pass pre-evaluated objVal to avoid double evaluation of object expression
    emitIR(`${callLabel}:`)
    nSetI3(id, 0)
    const callResult = genMethodCall(id, objVal)
    emitIR(`  store ${llRetType} ${callResult}, ptr ${resultAlloca}, align 8`)
    emitIR(`  br label %${endLabel}`)

    emitIR(`${endLabel}:`)
    const finalR = nextReg()
    emitIR(`  ${finalR} = load ${llRetType}, ptr ${resultAlloca}, align 8`)
    return finalR
}

// ── Class method call ───────────────────────────────────────────

function emitClassMethodCall(className: string, method: string, objVal: string, argList: string, isStatic: int): string {
    // Walk parent chain to find the class that has this method
    let methodClass = className
    while (methodClass != "") {
        if (funcRetTypes.has(`${methodClass}_${method}`) == 1) { break }
        if (classParents.has(methodClass) == 1) {
            methodClass = classParents.getString(methodClass)
        } else {
            methodClass = className
            break
        }
    }
    // Build args: static calls skip this, instance calls include this as first arg
    let callArgs = ""
    if (isStatic == 0) { callArgs = `ptr ${objVal}` }
    if (argList != "") {
        const argParts = argList.split(",")
        for (ap in argParts) {
            const argId = parseInt(ap)
            if (argId > 0) {
                let aVal = genExpr(argId)
                let aType = inferType(argId)
                if (callArgs != "") { callArgs = `${callArgs}, ` }
                callArgs = `${callArgs}${ssTypeToLLVM(aType)} ${aVal}`
            }
        }
    }
    // Resolve overloaded method name
    let resolved = `${methodClass}_${method}`
    if (isOverloaded(resolved) == 1) {
        const sig = argsSig(argList)
        if (sig != "" && funcRetTypes.has(`${resolved}_${sig}`) == 1) {
            resolved = `${resolved}_${sig}`
        }
    }
    let retType = "ptr"
    if (funcRetTypes.has(resolved) == 1) {
        retType = ssTypeToLLVM(funcRetTypes.getString(resolved))
    }
    // Vtable indirect dispatch for instance calls on vtable classes
    if (isStatic == 0 && classNeedsVtable.has(className) == 1 && classVtableSlots.has(className) == 1) {
        const vtSlots = classVtableSlots.getString(className)
        const slotParts = vtSlots.split(",")
        let slotIdx = -1
        let si = 0
        for (sp in slotParts) {
            if (sp == method) { slotIdx = si }
            si = si + 1
        }
        if (slotIdx >= 0) {
            // Load vtable ptr from object (offset 2: after rc and TypeInfo)
            const vtGepR = nextReg()
            emitIR(`  ${vtGepR} = getelementptr %${className}, ptr ${objVal}, i32 0, i32 2`)
            const vtPtrR = nextReg()
            emitIR(`  ${vtPtrR} = load ptr, ptr ${vtGepR}, align 8`)
            // Load function ptr from vtable slot
            const fnGep = nextReg()
            emitIR(`  ${fnGep} = getelementptr ptr, ptr ${vtPtrR}, i32 ${slotIdx}`)
            const fnPtr = nextReg()
            emitIR(`  ${fnPtr} = load ptr, ptr ${fnGep}, align 8`)
            // Indirect call through vtable
            if (retType == "void") {
                emitIR(`  call void ${fnPtr}(${callArgs})`)
                return "0"
            }
            const r = nextReg()
            emitIR(`  ${r} = call ${retType} ${fnPtr}(${callArgs})`)
            return r
        }
    }
    // Static dispatch fallback
    if (retType == "void") {
        emitIR(`  call void @${resolved}(${callArgs})`)
        return "0"
    }
    const r = nextReg()
    emitIR(`  ${r} = call ${retType} @${resolved}(${callArgs})`)
    return r
}

// ── Super method call (direct static dispatch to parent) ───────

function genSuperMethodCall(method: string, argList: string): string {
    const parentClass = classParents.getString(currentClassName)
    // Walk from parent to find method definition
    let methodClass = parentClass
    while (methodClass != "") {
        if (funcRetTypes.has(`${methodClass}_${method}`) == 1) { break }
        if (classParents.has(methodClass) == 1) {
            methodClass = classParents.getString(methodClass)
        } else {
            methodClass = parentClass
            break
        }
    }
    // Build args: this as first arg
    const thisVal = genThisExpr()
    let callArgs = `ptr ${thisVal}`
    if (argList != "") {
        const argParts = argList.split(",")
        for (ap in argParts) {
            const argId = parseInt(ap)
            if (argId > 0) {
                const aVal = genExpr(argId)
                const aType = inferType(argId)
                callArgs = `${callArgs}, ${ssTypeToLLVM(aType)} ${aVal}`
            }
        }
    }
    // Resolve overloaded method name
    let resolved = `${methodClass}_${method}`
    if (isOverloaded(resolved) == 1) {
        const sig = argsSig(argList)
        if (sig != "" && funcRetTypes.has(`${resolved}_${sig}`) == 1) {
            resolved = `${resolved}_${sig}`
        }
    }
    let retType = "ptr"
    if (funcRetTypes.has(resolved) == 1) {
        retType = ssTypeToLLVM(funcRetTypes.getString(resolved))
    }
    // Always static dispatch (bypass vtable)
    if (retType == "void") {
        emitIR(`  call void @${resolved}(${callArgs})`)
        return "0"
    }
    const r = nextReg()
    emitIR(`  ${r} = call ${retType} @${resolved}(${callArgs})`)
    return r
}

// ── Class method lookup helpers ─────────────────────────────────

// Check if a class (or its parents) has a user-defined method in classMethods
function classMethodHasName(cls: string, method: string): int {
    let c = cls
    while (c != "") {
        if (classMethods.has(c) == 1) {
            const mList = classMethods.getString(c)
            if (mList != "") {
                const parts = mList.split(",")
                for (p in parts) {
                    if (p == method) { return 1 }
                }
            }
        }
        if (classParents.has(c) == 1) { c = classParents.getString(c) } else { return 0 }
    }
    return 0
}

// Check if a class (or its parents) has a given method
function classHasMethod(cls: string, method: string): int {
    let c = cls
    while (c != "") {
        if (funcRetTypes.has(`${c}_${method}`) == 1) { return 1 }
        if (classParents.has(c) == 1) { c = classParents.getString(c) } else { return 0 }
    }
    return 0
}

// ── Method call helpers ─────────────────────────────────────────

function genStaticMethodCall(method: string, objId: int, argList: string): string {
    const className = nGetS1(objId)
    let methodClass = className
    while (methodClass != "") {
        if (funcRetTypes.has(`${methodClass}_${method}`) == 1) { break }
        if (classParents.has(methodClass) == 1) { methodClass = classParents.getString(methodClass) }
        else { methodClass = className; break }
    }
    const isMathClass = className == "Math" ? 1 : 0
    let args = ""
    if (argList != "") {
        const argParts = argList.split(",")
        let first = 1
        for (ap in argParts) {
            const argId = parseInt(ap)
            if (argId > 0) {
                let aVal = genExpr(argId)
                let aType = inferType(argId)
                if (isMathClass == 1 && method != "randomInt" && (aType == "int" || aType == "auto")) {
                    const cvR = nextReg()
                    emitIR(`  ${cvR} = sitofp i32 ${aVal} to double`)
                    aVal = cvR
                    aType = "double"
                }
                if (first == 1) { first = 0 } else { args = `${args}, ` }
                args = `${args}${ssTypeToLLVM(aType)} ${aVal}`
            }
        }
    }
    let resolved = `${methodClass}_${method}`
    if (isOverloaded(resolved) == 1) {
        const sig = argsSig(argList)
        if (sig != "" && funcRetTypes.has(`${resolved}_${sig}`) == 1) {
            resolved = `${resolved}_${sig}`
        }
    }
    const rtName = runtimeName(resolved)
    let retType = "ptr"
    if (funcRetTypes.has(resolved) == 1) {
        retType = ssTypeToLLVM(funcRetTypes.getString(resolved))
    }
    if (retType == "void") {
        emitIR(`  call void @${rtName}(${args})`)
        return "0"
    }
    const r = nextReg()
    emitIR(`  ${r} = call ${retType} @${rtName}(${args})`)
    return r
}

function genLengthMethod(objVal: string, objType: string): string {
    const r = nextReg()
    if (objType == "ptr" || objType == "i64" || objType.contains("Array") == 1) {
        emitIR(`  ${r} = call i32 @ss_arrayLen(ptr ${objVal})`)
    } else {
        emitIR(`  ${r} = call i32 @ss_stringLength(ptr ${objVal})`)
    }
    return r
}

function genIndexOfMethod(objVal: string, argList: string): string {
    const argId = parseInt(argList)
    const argType = inferType(argId)
    const sub = genExpr(argId)
    if (argType == "int" || argType == "i64" || argType == "double") {
        let val64 = sub
        if (argType == "int") {
            const sR = nextReg()
            emitIR(`  ${sR} = sext i32 ${sub} to i64`)
            val64 = sR
        }
        const r = nextReg(); emitIR(`  ${r} = call i32 @ss_arrayIndexOf(ptr ${objVal}, i64 ${val64})`); return r
    }
    const r = nextReg(); emitIR(`  ${r} = call i32 @ss_indexOf(ptr ${objVal}, ptr ${sub})`); return r
}

// ── Main method call dispatcher ─────────────────────────────────

function genMethodCall(id: int, preObj: string = ""): string {
    const method = nGetS1(id)
    const objId = nGetI1(id)
    const argList = nGetList(id)

    // Enum methods: EnumName.values(), EnumName.names()
    if (preObj == "" && enumReady == 1 && nGetKind(objId) == "IDENT" && enumDeclNodes.has(nGetS1(objId)) == 1) {
        if (method == "values") { return genEnumValues(nGetS1(objId)) }
        if (method == "names") { return genEnumNames(nGetS1(objId)) }
    }

    // D082 Phase 2: Thread.start(fn) → spawn virtual thread
    if (preObj == "" && nGetKind(objId) == "IDENT" && nGetS1(objId) == "Thread" && method == "start") {
        return genThreadStart(argList)
    }

    // Static method: ClassName.method()
    if (preObj == "" && nGetKind(objId) == "IDENT" && getVarType(nGetS1(objId)) == "" && classFields.has(nGetS1(objId)) == 1) {
        return genStaticMethodCall(method, objId, argList)
    }

    // Super method call: super.method() → direct static dispatch to parent method
    if (preObj == "" && nGetKind(objId) == "SUPER") {
        return genSuperMethodCall(method, argList)
    }

    let objVal = ""
    if (preObj != "") {
        objVal = preObj
    } else {
        objVal = genExpr(objId)
    }
    const objType = inferType(objId)
    if (objType == "i64") {
        const castR = nextReg()
        emitIR(`  ${castR} = inttoptr i64 ${objVal} to ptr`)
        objVal = castR
    }

    const objClass = resolveObjClass(objId)

    // Auto-generated clone methods for class instances (skip if user defined override)
    if (objClass != "" && objClass != "Map" && objClass != "Set" && classFields.has(objClass) == 1) {
        if (method == "deepClone" && classMethodHasName(objClass, "deepClone") == 0) {
            const dcR = nextReg()
            emitIR(`  ${dcR} = call ptr @ss_deep_clone_${objClass}(ptr ${objVal})`)
            return dcR
        }
        if (method == "shallowClone" && classMethodHasName(objClass, "shallowClone") == 0) {
            const scR = nextReg()
            emitIR(`  ${scR} = call ptr @ss_shallow_clone_${objClass}(ptr ${objVal})`)
            return scR
        }
    }

    // Interface dispatch: objClass is an interface name
    if (objClass != "" && ifaceMethodsCG.has(objClass) == 1) {
        return genInterfaceMethodCall(objClass, method, objVal, argList)
    }

    // D082 Phase 2: Thread<T>.join() → wait and return result
    if (objClass == "Thread" && method == "join") {
        return genThreadJoin(objVal, objId)
    }

    // User class method: walk parent chain
    if (objClass != "" && objClass != "Map" && objClass != "Set" && classHasMethod(objClass, method) == 1) {
        return emitClassMethodCall(objClass, method, objVal, argList, 0)
    }

    // Set<T> methods
    if (objClass == "Set") {
        const setResult = genSetMethod(method, objVal, argList)
        if (setResult != "") { return setResult }
    }

    // Type-dependent dispatch
    if (method == "length") { return genLengthMethod(objVal, objType) }
    if (method == "indexOf") { return genIndexOfMethod(objVal, argList) }

    // Non-owning push check
    if (method == "push" && nGetKind(objId) == "MEMBER_ACCESS") {
        const maField = nGetS1(objId)
        const maClass = resolveObjClass(nGetI1(objId))
        if (maClass != "" && nonOwningFields.has(`${maClass}.${maField}`) == 1) {
            pushNonOwning = 1
        }
    }

    // Dispatch to category handlers
    let result = genStringMethod(method, objVal, argList)
    if (result != "") { return result }
    result = genHigherOrderMethod(method, objVal, argList)
    if (result != "") { return result }
    result = genArrayMethod(method, objVal, argList)
    if (result != "") {
        // push returns the (possibly reallocated) array ptr — store it back
        if (method == "push" && preObj == "" && nGetKind(objId) == "IDENT") {
            const varName = nGetS1(objId)
            emitIR(`  store ptr ${result}, ptr ${varRef(varName)}, align 8`)
        }
        return result
    }
    result = genMapMethod(method, objVal, argList)
    if (result != "") { return result }

    // Fallback: class method
    if (objClass != "" && objClass != "Map") {
        return emitClassMethodCall(objClass, method, objVal, argList, 0)
    }

    emitIR(`  ; TODO: method call .${method}`)
    return "0"
}

// ── D082 Phase 2: Thread.start / .join ───────────────────────

function genThreadStart(argList: string): string {
    const parts = argList.split(",")
    const fnId = parseInt(parts[0])
    const fnVal = genExpr(fnId)
    const result = nextReg()
    emitIR(`  ${result} = call ptr @ss_threadStart(i64 ${fnVal})`)
    return result
}

function genThreadJoin(objVal: string, objId: int): string {
    const raw = nextReg()
    emitIR(`  ${raw} = call i64 @ss_threadJoin(ptr ${objVal})`)
    // Convert i64 result to the Thread<T> element type
    const objType = inferType(objId)
    let elemType = "int"
    if (objType.startsWith("Thread<") == 1) {
        elemType = threadElemType(objType)
    }
    if (elemType == "void" || elemType == "") { return "0" }
    return emitI64ToValue(raw, elemType)
}

// ── Interface method dispatch ─────────────────────────────────

function genInterfaceMethodCall(ifaceName: string, method: string, objVal: string, argList: string): string {
    const dispName = `__iface_${ifaceName}_${method}`
    let callArgs = `ptr ${objVal}`
    if (argList != "") {
        const argParts = argList.split(",")
        for (ap in argParts) {
            const argId = parseInt(ap)
            if (argId > 0) {
                const aVal = genExpr(argId)
                const aType = inferType(argId)
                callArgs = `${callArgs}, ${ssTypeToLLVM(aType)} ${aVal}`
            }
        }
    }
    let retType = "ptr"
    if (funcRetTypes.has(dispName) == 1) {
        retType = ssTypeToLLVM(funcRetTypes.getString(dispName))
    }
    if (retType == "void") {
        emitIR(`  call void @${dispName}(${callArgs})`)
        return "0"
    }
    const r = nextReg()
    emitIR(`  ${r} = call ${retType} @${dispName}(${callArgs})`)
    return r
}
