// gen/class_member.ss — 成员访问:字段 load + accessor 调度 + obj?.field + Ref<T>.value 读

function emitFieldLoad(className: string, objReg: string, field: string): string {
    const idx = getFieldIndex(className, field)
    if (idx < 0) {
        println(`codegen error: class '${className}' has no field '${field}'`)
        exit(1)
    }
    const fType = classFieldTypes.getString(`${className}.${field}`)
    const gepReg = nextReg()
    emitIR(`  ${gepReg} = getelementptr %${className}, ptr ${objReg}, i32 0, i32 ${idx}`)
    const loadReg = nextReg()
    emitIR(`  ${loadReg} = load ${ssTypeToLLVM(fType)}, ptr ${gepReg}, align 8`)
    return loadReg
}

// Byte-offset variant — emits `getelementptr i8, ptr X, i64 idx*8` instead of
// the `%${className}` typed GEP. Bypasses cross-module forward-ref of the
// named struct type (LLVM `base element of getelementptr must be sized` when
// className is decl'd in a sibling lib module that emits IR after this call
// site — D139 §A.2 H1 fallback). All SS class fields occupy 8-byte slots
// (i32/i64/f64/ptr) so byte stride is constant.
function emitByteOffsetFieldLoad(className: string, objReg: string, field: string): string {
    const idx = getFieldIndex(className, field)
    if (idx < 0) {
        println(`codegen error: class '${className}' has no field '${field}'`)
        exit(1)
    }
    const fType = classFieldTypes.getString(`${className}.${field}`)
    const gepReg = nextReg()
    emitIR(`  ${gepReg} = getelementptr i8, ptr ${objReg}, i64 ${idx * 8}`)
    const loadReg = nextReg()
    emitIR(`  ${loadReg} = load ${ssTypeToLLVM(fType)}, ptr ${gepReg}, align 8`)
    return loadReg
}

// D096: accessor getter retType lookup. Returns "" if no accessor or funcRetTypes
// missing; distinguishes "no accessor" from "accessor exists" via paired
// classAccessorGetters.has() check when the caller needs both signals.
function getAccessorRetType(className: string, member: string): string {
    const accKey = `${className}.${member}`
    if (classAccessorGetters.has(accKey) == 0) { return "" }
    const mangled = classAccessorGetters.getString(accKey)
    if (funcRetTypes.has(mangled) == 1) { return funcRetTypes.getString(mangled) }
    return ""
}

// D096: accessor getter dispatch. Returns reg from @ClassName_get_FIELD(ptr) call,
// "" when no accessor is registered (caller falls through to emitFieldLoad),
// or exits with a write-only-accessor error when only the setter exists.
function tryEmitAccessorGet(className: string, objReg: string, member: string): string {
    const accKey = `${className}.${member}`
    if (classAccessorGetters.has(accKey) == 1) {
        const getMangled = classAccessorGetters.getString(accKey)
        const retType = funcRetTypes.has(getMangled) == 1 ? funcRetTypes.getString(getMangled) : "int"
        const llRet = ssTypeToLLVM(retType)
        const resR = nextReg()
        emitIR(`  ${resR} = call ${llRet} @${getMangled}(ptr ${objReg})`)
        return resR
    }
    if (classAccessorSetters.has(accKey) == 1) {
        println(`error: cannot read from write-only accessor '${className}.${member}'`)
        exit(1)
    }
    return ""
}

// D096: MEMBER_ACCESS dispatch — accessor getter wins, else plain field load.
function emitFieldOrAccessorGet(className: string, objReg: string, member: string): string {
    const acc = tryEmitAccessorGet(className, objReg, member)
    if (acc != "") { return acc }
    return emitFieldLoad(className, objReg, member)
}

// obj?.field — if obj is null, return default; otherwise access normally
function genOptionalMemberAccess(id: int, preObj: string = ""): string {
    const objId = nGetI1(id)
    const member = nGetS1(id)
    const objVal = preObj != "" ? preObj : genExpr(objId)
    const retType = inferType(id)
    const llRetType = ssTypeToLLVM(retType)

    const resultAlloca = emitEntryAlloca(nextReg(), llRetType, 8)
    if (llRetType == "ptr") {
        const emptyStr = addStringConst("")
        emitIR(`  store ptr ${emptyStr}, ptr ${resultAlloca}, align 8`)
    } else {
        emitIR(`  store ${llRetType} 0, ptr ${resultAlloca}, align 8`)
    }

    const cmpR = nextReg()
    emitIR(`  ${cmpR} = icmp eq ptr ${objVal}, null`)
    const accessLabel = nextLabel("optf.access")
    const endLabel = nextLabel("optf.end")
    emitIR(`  br i1 ${cmpR}, label %${endLabel}, label %${accessLabel}`)

    emitIR(`${accessLabel}:`)
    // Resolve class and emit field load directly (avoid re-evaluating objId)
    let className = ""
    const objKind = nGetKind(objId)
    if (objKind == "IDENT") { className = getObjClass(nGetS1(objId)) }
    if (className == "") { className = resolveObjClass(objId) }
    let accessResult = objVal
    if (className != "") { accessResult = emitFieldLoad(className, objVal, member) }
    emitIR(`  store ${llRetType} ${accessResult}, ptr ${resultAlloca}, align 8`)
    emitIR(`  br label %${endLabel}`)

    emitIR(`${endLabel}:`)
    const finalR = nextReg()
    emitIR(`  ${finalR} = load ${llRetType}, ptr ${resultAlloca}, align 8`)
    return finalR
}

function genMemberAccess(id: int, preObj: string = ""): string {
    const member = nGetS1(id)
    const objId = nGetI1(id)
    const objKind = nGetKind(objId)
    // D095: STRING_LIT.name → string itself. Fires when cls was folded from
    // comptime IDENT to string literal in @methodOf body.
    if (objKind == "STRING_LIT" && member == "name") {
        return addStringConst(nGetS1(objId))
    }
    // Enum value access: EnumName.Variant
    if (objKind == "IDENT" && enumReady == 1) {
        const eName = nGetS1(objId)
        const enumKey = `${eName}.${member}`
        if (enumValues.has(enumKey) == 1) {
            if (enumTypes.has(eName) == 1) {
                return addStringConst(enumValues.getString(enumKey))
            }
            return enumValues.getString(enumKey)
        }
    }
    // D078: Static field access: ClassName.field
    if (objKind == "IDENT") {
        const sfKey = `${nGetS1(objId)}.${member}`
        if (staticFieldGlobals.has(sfKey) == 1) {
            const sfGlobal = staticFieldGlobals.getString(sfKey)
            const sfType = staticFieldTypes.getString(sfKey)
            const sfLLType = ssTypeToLLVM(sfType)
            const sfReg = nextReg()
            emitIR(`  ${sfReg} = load ${sfLLType}, ptr ${sfGlobal}, align 8`)
            return sfReg
        }
    }
    if (objKind == "THIS") {
        const thisReg = nextReg()
        emitIR(`  ${thisReg} = load ptr, ptr %this, align 8`)
        return emitFieldOrAccessorGet(currentClassName, thisReg, member)
    }
    // D082: Ref<T>.value read
    if (member == "value" && objKind == "IDENT") {
        const rvt = getVarType(nGetS1(objId))
        if (rvt.startsWith("Ref<") == 1) {
            const refObj = preObj != "" ? preObj : genExpr(objId)
            return emitRefValueRead(refObj, refElemType(rvt))
        }
    }
    const objVal = preObj != "" ? preObj : genExpr(objId)
    // D082: Ref<T>.value read (non-IDENT object, e.g., method call result)
    if (member == "value") {
        const roc = resolveObjClass(objId)
        if (roc == "Ref") {
            const rvt = inferType(objId)
            const rElem = rvt.startsWith("Ref<") == 1 ? refElemType(rvt) : "int"
            return emitRefValueRead(objVal, rElem)
        }
    }
    if (objKind == "IDENT") {
        const cn = getObjClass(nGetS1(objId))
        if (cn != "") { return emitFieldOrAccessorGet(cn, objVal, member) }
    }
    // Generic fallback: resolve class via resolveObjClass for nested access, calls, etc.
    const resolvedClass = resolveObjClass(objId)
    if (resolvedClass != "") { return emitFieldOrAccessorGet(resolvedClass, objVal, member) }
    return objVal
}

// D082: Read Ref<T>.value — call ss_refGet and convert i64 → element type
function emitRefValueRead(refReg: string, elemType: string): string {
    const raw = nextReg()
    emitIR(`  ${raw} = call i64 @ss_refGet(ptr ${refReg})`)
    return emitI64ToValue(raw, elemType)
}
