// gen_assigns.ss — Assignment code generation (member assign + variable assign)
// Used by gen_decls.ss via textual import. No own imports needed.

// ── Assignments ─────────────────────────────────────────────

function genMemberAssign(id: int) {
    const objExpr = nGetI1(id)
    const fieldName = nGetS1(id)
    const op = nGetS2(id)
    const valExpr = nGetI2(id)

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
        const r3 = nextReg()
        if (op == "PLUS_ASSIGN") {
            if (fType == "string") {
                emitIR(`  ${r3} = call ptr @ss_string_concat(ptr ${r1}, ptr ${r2})`)
            } else if (fType == "double") {
                emitIR(`  ${r3} = fadd double ${r1}, ${r2}`)
            } else {
                emitIR(`  ${r3} = add ${llType} ${r1}, ${r2}`)
            }
        } else if (op == "MINUS_ASSIGN") {
            if (fType == "double") {
                emitIR(`  ${r3} = fsub double ${r1}, ${r2}`)
            } else {
                emitIR(`  ${r3} = sub ${llType} ${r1}, ${r2}`)
            }
        } else if (op == "STAR_ASSIGN") {
            if (fType == "double") {
                emitIR(`  ${r3} = fmul double ${r1}, ${r2}`)
            } else {
                emitIR(`  ${r3} = mul ${llType} ${r1}, ${r2}`)
            }
        } else if (op == "SLASH_ASSIGN") {
            if (fType == "double") {
                emitIR(`  ${r3} = fdiv double ${r1}, ${r2}`)
            } else {
                emitIR(`  ${r3} = sdiv ${llType} ${r1}, ${r2}`)
            }
        } else {
            emitIR(`  ${r3} = srem ${llType} ${r1}, ${r2}`)
        }
        emitIR(`  store ${llType} ${r3}, ptr ${gepReg}, align 8`)
        // RC: for string +=, release old value
        if (op == "PLUS_ASSIGN" && fType == "string") {
            emitIR(`  call void @ss_rc_release(ptr ${r1})`)
        }
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
        if (llType == "ptr" && currentFunc != "" && isTrackedPtrVar(assignLLName) == 1 && skipRelease == 0) {
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
        const r3 = nextReg()
        if (op == "PLUS_ASSIGN") {
            if (vType == "string") {
                emitIR(`  ${r3} = call ptr @ss_string_concat(ptr ${r1}, ptr ${r2})`)
            } else {
                emitIR(`  ${r3} = add i32 ${r1}, ${r2}`)
            }
        } else if (op == "MINUS_ASSIGN") {
            emitIR(`  ${r3} = sub i32 ${r1}, ${r2}`)
        } else if (op == "STAR_ASSIGN") {
            emitIR(`  ${r3} = mul i32 ${r1}, ${r2}`)
        } else if (op == "SLASH_ASSIGN") {
            emitIR(`  ${r3} = sdiv i32 ${r1}, ${r2}`)
        } else {
            emitIR(`  ${r3} = srem i32 ${r1}, ${r2}`)
        }
        emitIR(`  store ${llType} ${r3}, ptr ${lnRef}, align 8`)
        // RC: for string +=, release old value (concat result is new owned)
        if (op == "PLUS_ASSIGN" && vType == "string" && currentFunc != "" && isTrackedPtrVar(llVarName(name)) == 1) {
            emitIR(`  call void @ss_rc_release(ptr ${r1})`)
        }
    }
}
