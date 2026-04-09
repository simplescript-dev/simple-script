// gen_assigns.ss — Assignment code generation (member assign + variable assign)
// Used by gen_decls.ss via textual import. No own imports needed.

// ── Shared helpers ──────────────────────────────────────────

// Convert a value to i64 for storage (Ref<T>, array elements)
function emitValueToI64(val: string, ssType: string): string {
    const llType = ssTypeToLLVM(ssType)
    if (llType == "ptr") {
        const r = nextReg()
        emitIR(`  ${r} = ptrtoint ptr ${val} to i64`)
        return r
    }
    if (ssType == "double") {
        const r = nextReg()
        emitIR(`  ${r} = bitcast double ${val} to i64`)
        return r
    }
    if (llType == "i32") {
        const r = nextReg()
        emitIR(`  ${r} = sext i32 ${val} to i64`)
        return r
    }
    return val
}

// Convert i64 back to typed value (reverse of emitValueToI64)
function emitI64ToValue(val: string, ssType: string): string {
    if (ssType == "" || ssType == "auto") { return val }
    const llType = ssTypeToLLVM(ssType)
    if (llType == "ptr") {
        const r = nextReg()
        emitIR(`  ${r} = inttoptr i64 ${val} to ptr`)
        return r
    }
    if (ssType == "double") {
        const r = nextReg()
        emitIR(`  ${r} = bitcast i64 ${val} to double`)
        return r
    }
    if (llType == "i32") {
        const r = nextReg()
        emitIR(`  ${r} = trunc i64 ${val} to i32`)
        return r
    }
    return val
}

// Emit compound arithmetic (+=, -=, *=, /=, %=), returns result register
function emitCompoundArith(op: string, r1: string, r2: string, elemType: string, llType: string): string {
    const r3 = nextReg()
    if (op == "PLUS_ASSIGN") {
        if (elemType == "string") {
            emitIR(`  ${r3} = call ptr @ss_string_concat(ptr ${r1}, ptr ${r2})`)
        } else if (elemType == "double") {
            emitIR(`  ${r3} = fadd double ${r1}, ${r2}`)
        } else {
            emitIR(`  ${r3} = add ${llType} ${r1}, ${r2}`)
        }
    } else if (op == "MINUS_ASSIGN") {
        if (elemType == "double") {
            emitIR(`  ${r3} = fsub double ${r1}, ${r2}`)
        } else {
            emitIR(`  ${r3} = sub ${llType} ${r1}, ${r2}`)
        }
    } else if (op == "STAR_ASSIGN") {
        if (elemType == "double") {
            emitIR(`  ${r3} = fmul double ${r1}, ${r2}`)
        } else {
            emitIR(`  ${r3} = mul ${llType} ${r1}, ${r2}`)
        }
    } else if (op == "SLASH_ASSIGN") {
        if (elemType == "double") {
            emitIR(`  ${r3} = fdiv double ${r1}, ${r2}`)
        } else {
            emitIR(`  ${r3} = sdiv ${llType} ${r1}, ${r2}`)
        }
    } else {
        emitIR(`  ${r3} = srem ${llType} ${r1}, ${r2}`)
    }
    return r3
}

// ── Assignments ─────────────────────────────────────────────

function genMemberAssign(id: int) {
    const objExpr = nGetI1(id)
    const fieldName = nGetS1(id)
    const op = nGetS2(id)
    const valExpr = nGetI2(id)

    // D082: Ref<T>.value assignment
    if (fieldName == "value" && nGetKind(objExpr) == "IDENT") {
        const rvt = getVarType(nGetS1(objExpr))
        if (rvt.startsWith("Ref<") == 1) {
            genRefValueAssign(objExpr, op, valExpr, refElemType(rvt))
            return
        }
    }

    // D078: Static field assignment: ClassName.field = value
    const sfKey = nGetKind(objExpr) == "IDENT" ? `${nGetS1(objExpr)}.${fieldName}` : ""
    if (sfKey != "" && staticFieldGlobals.has(sfKey) == 1) {
        genStaticFieldAssign(sfKey, op, valExpr)
        return
    }

    // Resolve object class and generate object pointer
    const objClass = resolveObjClass(objExpr)
    if (objClass == "") {
        println(`codegen error: cannot resolve class for member assignment to field '${fieldName}'`)
        exit(1)
    }
    const objReg = genExpr(objExpr)
    const idx = getFieldIndex(objClass, fieldName)
    if (idx < 0) {
        println(`codegen error: class '${objClass}' has no field '${fieldName}'`)
        exit(1)
    }
    const fType = classFieldTypes.getString(`${objClass}.${fieldName}`)
    const llType = ssTypeToLLVM(fType)
    const gepReg = nextReg()
    emitIR(`  ${gepReg} = getelementptr %${objClass}, ptr ${objReg}, i32 0, i32 ${idx}`)

    if (op == "ASSIGN") {
        let val = genExpr(valExpr)
        // RC: for ref-type fields, release old and retain new
        if (llType == "ptr") {
            const oldVal = nextReg()
            emitIR(`  ${oldVal} = load ptr, ptr ${gepReg}, align 8`)
            if (isOwnedExpr(valExpr) == 0) {
                emitRetainForType(val, fType)
            }
            emitIR(`  store ptr ${val}, ptr ${gepReg}, align 8`)
            emitReleaseForType(oldVal, fType)
        } else {
            emitIR(`  store ${llType} ${val}, ptr ${gepReg}, align 8`)
        }
    } else if (op == "POWER_ASSIGN") {
        const r1 = nextReg()
        emitIR(`  ${r1} = load ${llType}, ptr ${gepReg}, align 8`)
        let r2 = genExpr(valExpr)
        const r2Type = inferType(valExpr)
        if (r2Type == "i64" && fType != "i64") {
            const trR = nextReg()
            emitIR(`  ${trR} = trunc i64 ${r2} to i32`)
            r2 = trR
        }
        let pd1 = r1
        let pd2 = r2
        if (fType != "double") {
            const cv1 = nextReg()
            emitIR(`  ${cv1} = sitofp i32 ${r1} to double`)
            pd1 = cv1
            const cv2 = nextReg()
            emitIR(`  ${cv2} = sitofp i32 ${r2} to double`)
            pd2 = cv2
        }
        const powRes = nextReg()
        emitIR(`  ${powRes} = call double @ss_pow(double ${pd1}, double ${pd2})`)
        if (fType != "double") {
            const intRes = nextReg()
            emitIR(`  ${intRes} = fptosi double ${powRes} to i32`)
            emitIR(`  store ${llType} ${intRes}, ptr ${gepReg}, align 8`)
        } else {
            emitIR(`  store double ${powRes}, ptr ${gepReg}, align 8`)
        }
    } else {
        // Compound: +=, -=, *=, /=, %=
        const r1 = nextReg()
        emitIR(`  ${r1} = load ${llType}, ptr ${gepReg}, align 8`)
        let r2 = genExpr(valExpr)
        // Trunc i64 to i32 if needed
        const r2Type = inferType(valExpr)
        if (r2Type == "i64" && fType != "i64") {
            const trR = nextReg()
            emitIR(`  ${trR} = trunc i64 ${r2} to i32`)
            r2 = trR
        }
        const r3 = emitCompoundArith(op, r1, r2, fType, llType)
        emitIR(`  store ${llType} ${r3}, ptr ${gepReg}, align 8`)
        // RC: for string +=, release old value
        if (op == "PLUS_ASSIGN" && fType == "string") {
            emitIR(`  call void @ss_rc_release(ptr ${r1})`)
        }
    }
}

// D082: Ref<T>.value assignment — read-modify-write through ss_refGet/ss_refSet
function genRefValueAssign(objExpr: int, op: string, valExpr: int, elemType: string) {
    const refReg = genExpr(objExpr)
    const llType = ssTypeToLLVM(elemType)

    if (op == "ASSIGN") {
        const val = genExpr(valExpr)
        const val64 = emitValueToI64(val, elemType)
        emitIR(`  call void @ss_refSet(ptr ${refReg}, i64 ${val64})`)
    } else {
        // Compound assignment: +=, -=, *=, /=, %=
        const raw = nextReg()
        emitIR(`  ${raw} = call i64 @ss_refGet(ptr ${refReg})`)
        const r1 = emitI64ToValue(raw, elemType)
        let r2 = genExpr(valExpr)
        const r3 = emitCompoundArith(op, r1, r2, elemType, llType)
        const res64 = emitValueToI64(r3, elemType)
        emitIR(`  call void @ss_refSet(ptr ${refReg}, i64 ${res64})`)
    }
}

function genAssign(id: int) {
    const name = nGetS1(id)
    const op = nGetS2(id)
    const valId = nGetI1(id)

    const vType = getVarType(name)
    const llType = ssTypeToLLVM(vType)

    if (op == "ASSIGN") {
        let val = genExpr(valId)
        const valType = inferType(valId)
        const valLL = ssTypeToLLVM(valType)
        if (valLL == "i64" && llType == "i32") {
            const trR = nextReg()
            emitIR(`  ${trR} = trunc i64 ${val} to i32`)
            val = trR
        }
        if (valLL == "i64" && llType == "ptr") {
            const cvR = nextReg()
            emitIR(`  ${cvR} = inttoptr i64 ${val} to ptr`)
            val = cvR
        }
        // RC: release old value on reassignment of tracked ptr vars
        // Skip if RHS is a method call on the same variable (e.g., x = x.push(v))
        // because the method may realloc the pointer, invalidating the old value
        let skipRelease = 0
        if (nGetKind(valId) == "METHOD_CALL" && nGetKind(nGetI1(valId)) == "IDENT") {
            if (nGetS1(nGetI1(valId)) == name) { skipRelease = 1 }
        }
        const assignLLName = llVarName(name)
        const isGlobalPtr = assignLLName.startsWith("@") == 1
        if (llType == "ptr" && currentFunc != "" && (isTrackedPtrVar(assignLLName) == 1 || isGlobalPtr == 1) && skipRelease == 0) {
            const oldVal = nextReg()
            emitIR(`  ${oldVal} = load ptr, ptr ${varRef(name)}, align 8`)
            if (isOwnedExpr(valId) == 0) {
                emitIR(`  call void @ss_rc_retain(ptr ${val})`)
            }
            emitIR(`  store ptr ${val}, ptr ${varRef(name)}, align 8`)
            emitIR(`  call void @ss_rc_release(ptr ${oldVal})`)
        } else {
            emitIR(`  store ${llType} ${val}, ptr ${varRef(name)}, align 8`)
        }
    } else if (op == "POWER_ASSIGN") {
        const lnRef = varRef(name)
        const r1 = nextReg()
        emitIR(`  ${r1} = load ${llType}, ptr ${lnRef}, align 8`)
        let r2 = genExpr(valId)
        const r2Type = inferType(valId)
        if (r2Type == "i64" && vType != "i64") {
            const trR = nextReg()
            emitIR(`  ${trR} = trunc i64 ${r2} to i32`)
            r2 = trR
        }
        let pd1 = r1
        let pd2 = r2
        if (vType != "double") {
            const cv1 = nextReg()
            emitIR(`  ${cv1} = sitofp i32 ${r1} to double`)
            pd1 = cv1
            const cv2 = nextReg()
            emitIR(`  ${cv2} = sitofp i32 ${r2} to double`)
            pd2 = cv2
        }
        const powRes = nextReg()
        emitIR(`  ${powRes} = call double @ss_pow(double ${pd1}, double ${pd2})`)
        if (vType != "double") {
            const intRes = nextReg()
            emitIR(`  ${intRes} = fptosi double ${powRes} to i32`)
            emitIR(`  store ${llType} ${intRes}, ptr ${lnRef}, align 8`)
        } else {
            emitIR(`  store double ${powRes}, ptr ${lnRef}, align 8`)
        }
    } else {
        // Compound: +=, -=, *=, /=, %=
        const lnRef = varRef(name)
        const r1 = nextReg(); emitIR(`  ${r1} = load ${llType}, ptr ${lnRef}, align 8`)
        let r2 = genExpr(valId)
        // Trunc i64 to i32 if needed
        const r2Type = inferType(valId)
        if (r2Type == "i64" && vType != "i64") {
            const trR = nextReg(); emitIR(`  ${trR} = trunc i64 ${r2} to i32`)
            r2 = trR
        }
        const r3 = emitCompoundArith(op, r1, r2, vType, llType)
        emitIR(`  store ${llType} ${r3}, ptr ${lnRef}, align 8`)
        // RC: for string +=, release old value (concat result is new owned)
        if (op == "PLUS_ASSIGN" && vType == "string" && currentFunc != "" && isTrackedPtrVar(llVarName(name)) == 1) {
            emitIR(`  call void @ss_rc_release(ptr ${r1})`)
        }
    }
}

// D078: Static field assignment
function genStaticFieldAssign(sfKey: string, op: string, valExpr: int) {
    const globalName = staticFieldGlobals.getString(sfKey)
    const fType = staticFieldTypes.getString(sfKey)
    const llType = ssTypeToLLVM(fType)
    if (op == "ASSIGN") {
        let val = genExpr(valExpr)
        if (llType == "ptr") {
            const oldVal = nextReg()
            emitIR(`  ${oldVal} = load ptr, ptr ${globalName}, align 8`)
            if (isOwnedExpr(valExpr) == 0) {
                emitRetainForType(val, fType)
            }
            emitIR(`  store ptr ${val}, ptr ${globalName}, align 8`)
            emitReleaseForType(oldVal, fType)
        } else {
            emitIR(`  store ${llType} ${val}, ptr ${globalName}, align 8`)
        }
    } else if (op == "POWER_ASSIGN") {
        const r1 = nextReg()
        emitIR(`  ${r1} = load ${llType}, ptr ${globalName}, align 8`)
        let r2 = genExpr(valExpr)
        const r2Type = inferType(valExpr)
        if (r2Type == "i64" && fType != "i64") {
            const trR = nextReg()
            emitIR(`  ${trR} = trunc i64 ${r2} to i32`)
            r2 = trR
        }
        let pd1 = r1
        let pd2 = r2
        if (fType != "double") {
            const cv1 = nextReg()
            emitIR(`  ${cv1} = sitofp i32 ${r1} to double`)
            pd1 = cv1
            const cv2 = nextReg()
            emitIR(`  ${cv2} = sitofp i32 ${r2} to double`)
            pd2 = cv2
        }
        const powRes = nextReg()
        emitIR(`  ${powRes} = call double @ss_pow(double ${pd1}, double ${pd2})`)
        if (fType != "double") {
            const intRes = nextReg()
            emitIR(`  ${intRes} = fptosi double ${powRes} to i32`)
            emitIR(`  store ${llType} ${intRes}, ptr ${globalName}, align 8`)
        } else {
            emitIR(`  store double ${powRes}, ptr ${globalName}, align 8`)
        }
    } else {
        const r1 = nextReg()
        emitIR(`  ${r1} = load ${llType}, ptr ${globalName}, align 8`)
        let r2 = genExpr(valExpr)
        const r2Type = inferType(valExpr)
        if (r2Type == "i64" && fType != "i64") {
            const trR = nextReg()
            emitIR(`  ${trR} = trunc i64 ${r2} to i32`)
            r2 = trR
        }
        const r3 = emitCompoundArith(op, r1, r2, fType, llType)
        emitIR(`  store ${llType} ${r3}, ptr ${globalName}, align 8`)
        if (op == "PLUS_ASSIGN" && fType == "string") {
            emitIR(`  call void @ss_rc_release(ptr ${r1})`)
        }
    }
}
