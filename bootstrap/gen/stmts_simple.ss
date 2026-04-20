// gen/stmts_simple.ss — 简单语句:自增/自减、索引赋值。

function genPostfixStmt(id: int) {
    // D089 Phase 3+4: comptime postfix → update ctVars with scope chain lookup
    if (comptimeDepth > 0) {
        const pfName = nGetS1(id)
        let pfKey = ""
        if (ctScopeStack.length() > 0) {
            let pfSi = ctScopeStack.length() - 1
            while (pfSi >= 0) {
                const pfCk = `${ctScopeStack[pfSi]}:${pfName}`
                if (ctVars.has(pfCk) == 1) { pfKey = pfCk; break }
                pfSi = pfSi - 1
            }
        }
        if (pfKey == "") {
            const pfFk = `${currentFunc}:${pfName}`
            if (ctVars.has(pfFk) == 1) { pfKey = pfFk }
        }
        if (pfKey != "") {
            const pfTagged = parseInt(ctVars.getString(pfKey))
            if (isCt(pfTagged) == 1) {
                const pfOld = payload(pfTagged)
                const pfDelta = nGetKind(id) == "POSTFIX_INC" ? 1 : -1
                ctVars.set(pfKey, `${ctVal(interpNewInt(interpAsInt(pfOld) + pfDelta))}`)
            }
            return
        }
    }
    ctInvalidated.set(`${currentFunc}:${nGetS1(id)}`, "1")
    const kind = nGetKind(id)
    const pRef = varRef(nGetS1(id))
    const r1 = nextReg(); emitIR(`  ${r1} = load i32, ptr ${pRef}, align 4`)
    const r2 = nextReg()
    if (kind == "POSTFIX_INC") { emitIR(`  ${r2} = add i32 ${r1}, 1`) } else { emitIR(`  ${r2} = sub i32 ${r1}, 1`) }
    emitIR(`  store i32 ${r2}, ptr ${pRef}, align 4`)
}

function genIndexAssign(id: int) {
    if (comptimeDepth > 0) {
        const iaVarName = nGetS1(id)
        const iaIdxVal = genVal(nGetI1(id))
        const iaValVal = genVal(nGetI2(id))
        let iaObjTagged = -1
        if (ctScopeStack.length() > 0) {
            let iaSi = ctScopeStack.length() - 1
            while (iaSi >= 0) {
                const iaSk = `${ctScopeStack[iaSi]}:${iaVarName}`
                if (ctVars.has(iaSk) == 1) {
                    iaObjTagged = parseInt(ctVars.getString(iaSk))
                    break
                }
                iaSi = iaSi - 1
            }
        }
        if (iaObjTagged == -1) {
            const iaCk = `${currentFunc}:${iaVarName}`
            if (ctVars.has(iaCk) == 1) {
                iaObjTagged = parseInt(ctVars.getString(iaCk))
            }
        }
        if (isCt(iaObjTagged) == 1 && isCt(iaIdxVal) == 1 && isCt(iaValVal) == 1) {
            const iaObjP = payload(iaObjTagged)
            const iaObjType = interpType(iaObjP)
            if (iaObjType == "array") {
                interpArraySet(iaObjP, interpAsInt(payload(iaIdxVal)), payload(iaValVal))
                return
            }
            if (iaObjType == "object" || iaObjType == "map") {
                interpSetField(iaObjP, interpAsStr(payload(iaIdxVal)), payload(iaValVal))
                return
            }
        }
        return
    }
    // D088: compile-time field name → direct GEP+store; otherwise fall through to ss_arraySet
    // D095: idx can also be f.name where f is comptimeConsts-bound
    const iaIdxNode = nGetI1(id)
    if (isCtStringIdx(iaIdxNode) == 1) {
        let iaObjClass = getObjClass(nGetS1(id))
        if (iaObjClass == "") {
            const vt = getVarType(nGetS1(id))
            if (vt != "" && classFields.has(vt) == 1) { iaObjClass = vt }
        }
        if (iaObjClass != "" && classFields.has(iaObjClass) == 1) {
            const iaFieldName = resolveCtString(iaIdxNode)
            const iaObjReg = nextReg()
            emitIR(`  ${iaObjReg} = load ptr, ptr ${varRef(nGetS1(id))}, align 8`)
            const iaIdx = getFieldIndex(iaObjClass, iaFieldName)
            if (iaIdx < 0) {
                println(`codegen error: class '${iaObjClass}' has no field '${iaFieldName}'`)
                exit(1)
            }
            const iaFType = classFieldTypes.getString(`${iaObjClass}.${iaFieldName}`)
            const iaLLType = ssTypeToLLVM(iaFType)
            const iaGep = nextReg()
            emitIR(`  ${iaGep} = getelementptr %${iaObjClass}, ptr ${iaObjReg}, i32 0, i32 ${iaIdx}`)
            const iaVal = genExpr(nGetI2(id))
            if (iaLLType == "ptr") {
                const iaOld = nextReg()
                emitIR(`  ${iaOld} = load ptr, ptr ${iaGep}, align 8`)
                if (isOwnedExpr(nGetI2(id)) == 0) {
                    emitRetainForType(iaVal, iaFType)
                }
                emitIR(`  store ptr ${iaVal}, ptr ${iaGep}, align 8`)
                emitReleaseForType(iaOld, iaFType)
            } else {
                emitIR(`  store ${iaLLType} ${iaVal}, ptr ${iaGep}, align 8`)
            }
            return
        }
    }

    const arrPtr = nextReg(); emitIR(`  ${arrPtr} = load ptr, ptr ${varRef(nGetS1(id))}, align 8`)
    const idxVal = genExpr(nGetI1(id))
    const valVal = genExpr(nGetI2(id))
    const vt = inferType(nGetI2(id))
    let v64 = valVal
    if (vt == "int" || vt == "auto" || vt == "") { const s = nextReg(); emitIR(`  ${s} = sext i32 ${valVal} to i64`); v64 = s }
    if (vt == "string" || vt == "ptr") {
        // RC: retain new, load+release old (null-safe)
        const oldVal = nextReg()
        emitIR(`  ${oldVal} = call i64 @ss_arrayGet(ptr ${arrPtr}, i32 ${idxVal})`)
        const oldPtr = nextReg()
        emitIR(`  ${oldPtr} = inttoptr i64 ${oldVal} to ptr`)
        emitIR(`  call void @ss_rc_retain(ptr ${valVal})`)
        const c = nextReg(); emitIR(`  ${c} = ptrtoint ptr ${valVal} to i64`); v64 = c
        emitIR(`  call void @ss_arraySet(ptr ${arrPtr}, i32 ${idxVal}, i64 ${v64})`)
        emitIR(`  call void @ss_rc_release(ptr ${oldPtr})`)
    } else {
        emitIR(`  call void @ss_arraySet(ptr ${arrPtr}, i32 ${idxVal}, i64 ${v64})`)
    }
}
