// gen_stmts.ss — Statement codegen: dispatcher, control flow, block handling
// Declaration/assignment/function codegen in gen_decls.ss.

import { genFuncDeclStmt, genVarDecl, genDestructureArray, genAssign, genMemberAssign, isOwnedExpr, genReturn } from "./gen_decls"
import { interpExecComptime, interpGetComptimeIR, interpClearComptimeIR, interpGetComptimeSS, interpClearComptimeSS, interpTruthy, interpShouldStop, interpCheckLoopExit, interpAsInt, interpAsStr, interpNewInt, interpNewString, interpType, interpClasses, interpClassParents, interpEnumValues, interpEnumTypes, interpEnumNodes } from "./interp"

// ── Statement helpers ────────────────────────────────────────

// Emit condition→i1 conversion for any type (i32/i64/ptr/double)
function emitCondToI1(condId: int, condVal: string): string {
    const vType = inferType(condId)
    const llType = ssTypeToLLVM(vType)
    const r = nextReg()
    if (llType == "ptr") {
        emitIR(`  ${r} = icmp ne ptr ${condVal}, null`)
    } else if (llType == "i64") {
        emitIR(`  ${r} = icmp ne i64 ${condVal}, 0`)
    } else if (llType == "double") {
        emitIR(`  ${r} = fcmp one double ${condVal}, 0.0`)
    } else {
        emitIR(`  ${r} = icmp ne i32 ${condVal}, 0`)
    }
    return r
}

function emitExcDepthDec() {
    const d = nextReg()
    emitIR(`  ${d} = load i32, ptr @ss_exc_depth`)
    const d1 = nextReg()
    emitIR(`  ${d1} = sub i32 ${d}, 1`)
    emitIR(`  store i32 ${d1}, ptr @ss_exc_depth`)
}

function emitRethrow(finallyBody: int) {
    if (finallyBody > 0) {
        genNestedBlock(finallyBody)
    }
    const msg = nextReg()
    emitIR(`  ${msg} = load ptr, ptr @ss_exc_msg`)
    emitIR(`  call void @ss_throw(ptr ${msg})`)
    emitIR("  unreachable")
}

function genTryCatch(id: int) {
    const tryBody = nGetI1(id)
    const finallyBody = nGetI3(id)
    const catchList = nGetList(id)

    if (comptimeDepth > 0) {
        if (tryBody > 0) { genBlock(tryBody) }
        if (finallyBody > 0) { genBlock(finallyBody) }
        return
    }

    const tryLabel = nextLabel("try")
    const catchLabel = nextLabel("catch")
    const endLabel = nextLabel("try.end")

    let finallyLabel = ""
    let convergeLabel = endLabel
    if (finallyBody > 0) {
        finallyLabel = nextLabel("finally")
        convergeLabel = finallyLabel
    }

    // Push exception handler
    const depthR = nextReg()
    emitIR(`  ${depthR} = load i32, ptr @ss_exc_depth`)
    const newDepth = nextReg()
    emitIR(`  ${newDepth} = add i32 ${depthR}, 1`)
    emitIR(`  store i32 ${newDepth}, ptr @ss_exc_depth`)
    const offset = nextReg()
    emitIR(`  ${offset} = mul i32 ${depthR}, 200`)
    const off64 = nextReg()
    emitIR(`  ${off64} = sext i32 ${offset} to i64`)
    const bufPtr = nextReg()
    emitIR(`  ${bufPtr} = getelementptr i8, ptr @ss_jmpbuf, i64 ${off64}`)

    const sjRet = nextReg()
    emitIR(`  ${sjRet} = call i32 @setjmp(ptr ${bufPtr})`)
    const isExc = nextReg()
    emitIR(`  ${isExc} = icmp ne i32 ${sjRet}, 0`)
    emitIR(`  br i1 ${isExc}, label %${catchLabel}, label %${tryLabel}`)

    // ── Try block ──
    emitIR(`${tryLabel}:`)
    const savedTerm = terminated
    terminated = 0
    genNestedBlock(tryBody)
    if (terminated == 0) {
        emitExcDepthDec()
        emitIR(`  br label %${convergeLabel}`)
    }

    // ── Catch dispatch ──
    emitIR(`${catchLabel}:`)
    terminated = 0
    emitExcDepthDec()

    if (catchList == "") {
        emitRethrow(finallyBody)
    } else {
        genCatchClauses(catchList, convergeLabel, finallyBody)
    }

    // ── Finally block ──
    if (finallyBody > 0) {
        emitIR(`${finallyLabel}:`)
        terminated = 0
        genNestedBlock(finallyBody)
        if (terminated == 0) {
            emitIR(`  br label %${endLabel}`)
        }
    }

    emitIR(`${endLabel}:`)
    terminated = savedTerm
}

function genCatchClauses(catchList: string, convergeLabel: string, finallyBody: int) {
    const parts = catchList.split(",")
    const numClauses = parts.length()
    const rethrowLabel = nextLabel("catch.rethrow")

    // Load is-obj flag once (invariant across all catch clauses)
    const isObj = nextReg()
    emitIR(`  ${isObj} = load i32, ptr @ss_exc_is_obj`)
    const isObjBool = nextReg()
    emitIR(`  ${isObjBool} = icmp eq i32 ${isObj}, 1`)

    let clauseIdx = 0
    for (cp in parts) {
        const cid = parseInt(cp)
        const errType = nGetS2(cid)
        const errName = nGetS1(cid)
        const catchBody = nGetI1(cid)
        const bodyLabel = nextLabel("catch.body")

        let fallLabel = rethrowLabel
        if (clauseIdx + 1 < numClauses) {
            fallLabel = nextLabel("catch.next")
        }

        if (errType != "") {
            const typeCheckLabel = nextLabel("catch.tc")
            emitIR(`  br i1 ${isObjBool}, label %${typeCheckLabel}, label %${fallLabel}`)
            emitIR(`${typeCheckLabel}:`)
            const obj = nextReg()
            emitIR(`  ${obj} = load ptr, ptr @ss_exc_obj`)
            const nameStr = addStringConst(errType)
            const matchResult = nextReg()
            emitIR(`  ${matchResult} = call i32 @ss_isinstance(ptr ${obj}, ptr ${nameStr})`)
            const matched = nextReg()
            emitIR(`  ${matched} = icmp eq i32 ${matchResult}, 1`)
            emitIR(`  br i1 ${matched}, label %${bodyLabel}, label %${fallLabel}`)
        } else {
            emitIR(`  br label %${bodyLabel}`)
        }

        emitIR(`${bodyLabel}:`)
        terminated = 0
        const errLLName = allocVarName(errName)
        emitIR(`  %${errLLName} = alloca ptr, align 8`)
        if (errType != "") {
            const obj2 = nextReg()
            emitIR(`  ${obj2} = load ptr, ptr @ss_exc_obj`)
            emitIR(`  store ptr ${obj2}, ptr %${errLLName}, align 8`)
            setVarType(errName, errType)
            setObjClass(errName, errType)
        } else {
            const msg = nextReg()
            emitIR(`  ${msg} = load ptr, ptr @ss_exc_msg`)
            emitIR(`  store ptr ${msg}, ptr %${errLLName}, align 8`)
            setVarType(errName, "string")
        }
        genNestedBlock(catchBody)
        if (terminated == 0) {
            emitIR(`  br label %${convergeLabel}`)
        }

        if (clauseIdx + 1 < numClauses) {
            emitIR(`${fallLabel}:`)
            terminated = 0
        }

        clauseIdx = clauseIdx + 1
    }

    emitIR(`${rethrowLabel}:`)
    emitRethrow(finallyBody)
}

// Populate enum name→value, type marker, and node lookup from an ENUM_DECL AST node.
// Shared by runtime registerEnum and the comptime ENUM_DECL handler — kept in sync by passing
// the target maps explicitly rather than duplicating the ENUM_VARIANT decode.
function registerEnumInto(id: int, valuesMap: Map, typesMap: Map, nodesMap: Map) {
    const eName = nGetS1(id)
    const isStringEnum = nGetI1(id)
    if (isStringEnum == 1) { typesMap.set(eName, "1") }
    nodesMap.set(eName, `${id}`)
    const vl = nGetList(id)
    if (vl == "") { return }
    const parts = vl.split(",")
    for (p in parts) {
        const vid = parseInt(p)
        if (vid > 0 && nGetKind(vid) == "ENUM_VARIANT") {
            const vName = nGetS1(vid)
            if (isStringEnum == 1) {
                valuesMap.set(`${eName}.${vName}`, nGetS2(vid))
            } else {
                valuesMap.set(`${eName}.${vName}`, `${nGetI1(vid)}`)
            }
        }
    }
}

function registerEnum(id: int) {
    if (enumReady == 0) { enumValues = Map(); enumTypes = Map(); enumDeclNodes = Map(); enumReady = 1 }
    registerEnumInto(id, enumValues, enumTypes, enumDeclNodes)
}

// ── Statement handlers ──────────────────────────────────────

function genBreak() {
    // D089 Phase 3: comptime break → set flag
    if (comptimeDepth > 0) { interpBreakFlag = 1; return }
    if (breakLabel != "") {
        emitReleaseBlockVarsSince(loopBlockStackSaved)
        emitIR(`  br label %${breakLabel}`)
        terminated = 1
    }
}

function genContinueStmt() {
    // D089 Phase 3: comptime continue → set flag
    if (comptimeDepth > 0) { interpContinueFlag = 1; return }
    if (continueLabel != "") {
        emitReleaseBlockVarsSince(loopBlockStackSaved)
        emitIR(`  br label %${continueLabel}`)
        terminated = 1
    }
}

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
            const pfOld = payload(parseInt(ctVars.getString(pfKey)))
            const pfDelta = nGetKind(id) == "POSTFIX_INC" ? 1 : -1
            ctVars.set(pfKey, `${ctVal(interpNewInt(interpAsInt(pfOld) + pfDelta))}`)
            return
        }
    }
    const kind = nGetKind(id)
    const pRef = varRef(nGetS1(id))
    const r1 = nextReg(); emitIR(`  ${r1} = load i32, ptr ${pRef}, align 4`)
    const r2 = nextReg()
    if (kind == "POSTFIX_INC") { emitIR(`  ${r2} = add i32 ${r1}, 1`) } else { emitIR(`  ${r2} = sub i32 ${r1}, 1`) }
    emitIR(`  store i32 ${r2}, ptr ${pRef}, align 4`)
}

function genIndexAssign(id: int) {
    // D088: compile-time field name → direct GEP+store; otherwise fall through to ss_arraySet
    const iaIdxNode = nGetI1(id)
    const iaIdxKind = nGetKind(iaIdxNode)
    if (iaIdxKind == "STRING_LIT" || (iaIdxKind == "IDENT" && comptimeConsts.has(nGetS1(iaIdxNode)) == 1)) {
        let iaObjClass = getObjClass(nGetS1(id))
        if (iaObjClass == "") {
            const vt = getVarType(nGetS1(id))
            if (vt != "" && classFields.has(vt) == 1) { iaObjClass = vt }
        }
        if (iaObjClass != "" && classFields.has(iaObjClass) == 1) {
            const iaFieldName = iaIdxKind == "STRING_LIT" ? nGetS1(iaIdxNode) : comptimeConsts.getString(nGetS1(iaIdxNode))
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

function genThrow(id: int) {
    const exprId = nGetI1(id)
    const exprVal = genExpr(exprId)
    const exprType = inferType(exprId)
    if (classFields.has(exprType) == 1 && classFieldTypes.has(`${exprType}.message`) == 1) {
        emitIR(`  store i32 1, ptr @ss_exc_is_obj`)
        emitIR(`  store ptr ${exprVal}, ptr @ss_exc_obj`)
        const msgReg = emitFieldLoad(exprType, exprVal, "message")
        emitIR(`  call void @ss_throw(ptr ${msgReg})`)
    } else {
        emitIR(`  store i32 0, ptr @ss_exc_is_obj`)
        emitIR(`  store ptr null, ptr @ss_exc_obj`)
        emitIR(`  call void @ss_throw(ptr ${exprVal})`)
    }
    emitIR("  unreachable")
    terminated = 1
}

// ── Statement dispatcher ────────────────────────────────────

function genStmt(id: int) {
    const kind = nGetKind(id)
    if (kind == "FUNC_DECL") {
        if (comptimeDepth > 0) {
            ctFuncNodes.set(nGetS1(id), `${id}`)
            return
        }
        genFuncDeclStmt(id)
        return
    }
    if (kind == "VAR_DECL") { genVarDecl(id); return }
    if (kind == "DESTRUCTURE_ARRAY") { genDestructureArray(id); return }
    if (kind == "DESTRUCTURE_OBJECT") { genDestructureObject(id); return }
    if (kind == "ASSIGN") { genAssign(id); return }
    if (kind == "EXPR_STMT") {
        const esExpr = nGetI1(id)
        if (esExpr > 0 && nGetKind(esExpr) == "CALL" && nGetS1(esExpr) == "annotationMapping") { return }
        if (comptimeDepth > 0) {
            genVal(esExpr)
            return
        }
        genExpr(esExpr)
        return
    }
    if (kind == "RETURN") { genReturn(id); return }
    if (kind == "IF") { genIf(id); return }
    if (kind == "FOR") { genFor(id); return }
    if (kind == "FOR_IN" || kind == "FOR_OF") { genForIn(id); return }
    if (kind == "WHILE") { genWhile(id); return }
    if (kind == "BREAK") { genBreak(); return }
    if (kind == "CONTINUE") { genContinueStmt(); return }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { genPostfixStmt(id); return }
    if (kind == "DO_WHILE") { genDoWhile(id); return }
    if (kind == "SWITCH") { genSwitch(id); return }
    if (kind == "INDEX_ASSIGN") { genIndexAssign(id); return }
    if (kind == "MEMBER_ASSIGN") { genMemberAssign(id); return }
    if (kind == "CLASS_DECL") {
        if (comptimeDepth > 0) {
            const ctClassName = nGetS1(id)
            interpClasses.set(ctClassName, `${id}`)
            const ctParent = nGetS2(id)
            if (ctParent != "") { interpClassParents.set(ctClassName, ctParent) }
            return
        }
        genClassDecl(id)
        return
    }
    if (kind == "ENUM_DECL") {
        if (comptimeDepth > 0) {
            registerEnumInto(id, interpEnumValues, interpEnumTypes, interpEnumNodes)
            return
        }
        registerEnum(id)
        return
    }
    if (kind == "INTERFACE_DECL") { return }
    if (kind == "TRY") { genTryCatch(id); return }
    if (kind == "THROW") { genThrow(id); return }
    if (kind == "COMPTIME_BLOCK") {
        runComptimeBlockBody(nGetI1(id))
        flushComptimeIR()
        flushComptimeSS()
        return
    }
}

// Run a comptime block body via genBlock without flushing comptimeSS (caller decides).
function runComptimeBlockBody(bodyId: int) {
    const savedFunc = currentFunc
    const savedTerminated = terminated
    currentFunc = "__comptime__"
    ctScopeStack = ctScopeStack.push("__comptime__")
    interpReturnFlag = 0
    interpReturnVal = 0
    interpBreakFlag = 0
    interpContinueFlag = 0
    interpThrowFlag = 0
    interpThrowVal = 0
    terminated = 0
    interpEnsureComptimeRoot()
    comptimeDepth = comptimeDepth + 1
    genBlock(bodyId)
    comptimeDepth = comptimeDepth - 1
    terminated = savedTerminated
    ctPopScope()
    currentFunc = savedFunc
}

function genBlock(blockId: int) {
    if (blockId <= 0) { return }
    const stmtList = nGetList(blockId)
    if (stmtList == "") { return }
    const parts = stmtList.split(",")
    for (p in parts) {
        const stmtId = parseInt(p)
        if (stmtId > 0) {
            genStmt(stmtId)
            if (terminated == 1) { return }
            if (comptimeDepth > 0 && interpShouldStop() == 1) { return }
            pirEmitScheduled(stmtId)
        }
    }
}

// RC: nested block wrapper — tracks block-level ptr vars and releases them on exit
function genNestedBlock(blockId: int) {
    pushBlockScope()
    rcBlockDepth = rcBlockDepth + 1
    genBlock(blockId)
    // Release block vars on normal exit (skip if terminated by return/break/continue)
    if (terminated == 0) {
        emitReleaseCurrentBlockVars()
    }
    popBlockScope()
    rcBlockDepth = rcBlockDepth - 1
}

// ── Control flow ────────────────────────────────────────────

function genIf(id: int) {
    const condId = nGetI1(id)
    const thenId = nGetI2(id)
    const elseId = nGetI3(id)

    // D089 Phase 3: comptime condition in comptime block → only codegen hit branch
    if (comptimeDepth > 0) {
        const condTagged = genVal(condId)
        if (isCt(condTagged) == 1) {
            if (interpTruthy(payload(condTagged)) == 1) {
                genBlock(thenId)
            } else if (elseId > 0) {
                genBlock(elseId)
            }
        }
        return
    }

    const condVal = genExpr(condId)
    const thenLabel = nextLabel("if.then")
    const elseLabel = nextLabel("if.else")
    const mergeLabel = nextLabel("if.merge")

    const r = emitCondToI1(condId, condVal)

    if (elseId > 0) {
        emitIR(`  br i1 ${r}, label %${thenLabel}, label %${elseLabel}`)
    } else {
        emitIR(`  br i1 ${r}, label %${thenLabel}, label %${mergeLabel}`)
    }

    emitIR(`${thenLabel}:`)
    terminated = 0
    genNestedBlock(thenId)
    if (terminated == 0) {
        emitIR(`  br label %${mergeLabel}`)
    }

    if (elseId > 0) {
        emitIR(`${elseLabel}:`)
        terminated = 0
        genNestedBlock(elseId)
        if (terminated == 0) {
            emitIR(`  br label %${mergeLabel}`)
        }
    }

    terminated = 0
    emitIR(`${mergeLabel}:`)
}

function genFor(id: int) {
    const initId = nGetI1(id)
    const condId = nGetI2(id)
    const updateId = nGetI3(id)
    const bodyId = nGetI4(id)

    // D089 Phase 3: comptime for in comptime block
    if (comptimeDepth > 0) {
        genStmt(initId)
        let ctForLimit = 10000
        while (ctForLimit > 0) {
            const fCondTagged = genVal(condId)
            if (isCt(fCondTagged) == 0 || interpTruthy(payload(fCondTagged)) == 0) { break }
            genBlock(bodyId)
            if (interpCheckLoopExit() == 1) { break }
            genStmt(updateId)
            ctForLimit = ctForLimit - 1
        }
        if (ctForLimit == 0) { println("[comptime] for loop exceeded 10000 iterations") }
        return
    }

    const condLabel = nextLabel("for.cond")
    const bodyLabel = nextLabel("for.body")
    const updateLabel = nextLabel("for.update")
    const afterLabel = nextLabel("for.after")

    const savedBreak = breakLabel
    const savedContinue = continueLabel
    const savedLoopStack = loopBlockStackSaved
    breakLabel = afterLabel
    continueLabel = updateLabel
    loopBlockStackSaved = blockPtrVarStack

    genStmt(initId)
    emitIR(`  br label %${condLabel}`)

    emitIR(`${condLabel}:`)
    const condVal = genExpr(condId)
    const r = emitCondToI1(condId, condVal)
    emitIR(`  br i1 ${r}, label %${bodyLabel}, label %${afterLabel}`)

    emitIR(`${bodyLabel}:`)
    terminated = 0
    genNestedBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${updateLabel}`) }

    emitIR(`${updateLabel}:`)
    terminated = 0
    genStmt(updateId)
    emitIR(`  br label %${condLabel}`)

    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak
    continueLabel = savedContinue
    loopBlockStackSaved = savedLoopStack
}

// D088 Phase 5: compile-time for-in unrolling for obj.fields()
function genForInUnrolled(id: int, className: string) {
    const itemName = nGetS1(id)
    const bodyId = nGetI2(id)
    const fieldStr = classFields.getString(className)

    const itemLLName = allocVarName(itemName)
    emitIR(`  %${itemLLName} = alloca ptr, align 8`)
    setVarType(itemName, "string")

    // No fields → skip entirely
    if (fieldStr == "") { return }

    const fields = fieldStr.split(",")
    const fieldCount = fields.length()
    const afterLabel = nextLabel("forin.unroll.after")

    // Save/set break/continue
    const savedBreak = breakLabel
    const savedContinue = continueLabel
    const savedLoopStack = loopBlockStackSaved
    breakLabel = afterLabel
    loopBlockStackSaved = blockPtrVarStack

    let i = 0
    for (fieldName in fields) {
        comptimeConsts.set(itemName, fieldName)

        const strConst = addStringConst(fieldName)
        emitIR(`  store ptr ${strConst}, ptr %${itemLLName}, align 8`)

        let nextIterLabel = afterLabel
        if (i < fieldCount - 1) {
            nextIterLabel = nextLabel("forin.unroll.next")
        }
        continueLabel = nextIterLabel

        genNestedBlock(bodyId)

        if (terminated == 0) {
            emitIR(`  br label %${nextIterLabel}`)
        }
        if (i < fieldCount - 1) {
            emitIR(`${nextIterLabel}:`)
        }
        terminated = 0

        i = i + 1
    }

    comptimeConsts.delete(itemName)

    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak
    continueLabel = savedContinue
    loopBlockStackSaved = savedLoopStack
}

function genForIn(id: int) {
    const itemName = nGetS1(id)
    const iterableId = nGetI1(id)
    const bodyId = nGetI2(id)

    // D089 Phase 4: comptime for-in over array
    if (comptimeDepth > 0) {
        const ctIterVal = genVal(iterableId)
        if (isCt(ctIterVal) == 1 && interpType(payload(ctIterVal)) == "array") {
            const ctItems = interpAsStr(payload(ctIterVal))
            if (ctItems != "") {
                const ctParts = ctItems.split(",")
                let ctFi = 0
                while (ctFi < ctParts.length()) {
                    ctVars.set(`${currentFunc}:${itemName}`, `${ctVal(parseInt(ctParts[ctFi]))}`)
                    genBlock(bodyId)
                    if (interpCheckLoopExit() == 1) { break }
                    ctFi = ctFi + 1
                }
            }
        }
        return
    }

    // D088: detect obj.fields() → compile-time unroll
    if (nGetKind(iterableId) == "METHOD_CALL" && nGetS1(iterableId) == "fields") {
        const fieldsObjId = nGetI1(iterableId)
        const fieldsClass = resolveObjClass(fieldsObjId)
        if (fieldsClass != "" && classFields.has(fieldsClass) == 1) {
            genForInUnrolled(id, fieldsClass)
            return
        }
    }

    const arr = genExpr(iterableId)
    const lenReg = nextReg(); emitIR(`  ${lenReg} = call i32 @ss_arrayLen(ptr ${arr})`)

    // Index variable
    const idxAlloca = nextReg(); emitIR(`  ${idxAlloca} = alloca i32, align 4`)
    emitIR(`  store i32 0, ptr ${idxAlloca}, align 4`)

    let itemType = inferArrayElemType(iterableId)
    if (itemType == "") { itemType = "i64" }
    const itemLLName = allocVarName(itemName)
    const itemLLType = ssTypeToLLVM(itemType)
    emitIR(`  %${itemLLName} = alloca ${itemLLType}, align 8`)
    setVarType(itemName, itemType)

    const condLabel = nextLabel("forin.cond")
    const bodyLabel = nextLabel("forin.body")
    const afterLabel = nextLabel("forin.after")

    const savedBreak2 = breakLabel
    const savedContinue2 = continueLabel
    const savedLoopStack2 = loopBlockStackSaved
    const updateLabel2 = nextLabel("forin.update")
    breakLabel = afterLabel
    continueLabel = updateLabel2
    loopBlockStackSaved = blockPtrVarStack

    emitIR(`  br label %${condLabel}`)

    emitIR(`${condLabel}:`)
    const curIdx = nextReg(); emitIR(`  ${curIdx} = load i32, ptr ${idxAlloca}, align 4`)
    const cmp = nextReg(); emitIR(`  ${cmp} = icmp slt i32 ${curIdx}, ${lenReg}`)
    emitIR(`  br i1 ${cmp}, label %${bodyLabel}, label %${afterLabel}`)

    emitIR(`${bodyLabel}:`)
    terminated = 0
    const elemVal = nextReg(); emitIR(`  ${elemVal} = call i64 @ss_arrayGet(ptr ${arr}, i32 ${curIdx})`)
    // Convert i64 element to item type
    if (itemType == "" || itemType == "auto" || itemType == "i64") {
        emitIR(`  store i64 ${elemVal}, ptr %${itemLLName}, align 8`)
    } else {
        const converted = emitI64ToValue(elemVal, itemType)
        emitIR(`  store ${itemLLType} ${converted}, ptr %${itemLLName}, align 8`)
    }

    genNestedBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${updateLabel2}`) }

    emitIR(`${updateLabel2}:`)
    terminated = 0
    const nextIdx = nextReg(); emitIR(`  ${nextIdx} = load i32, ptr ${idxAlloca}, align 4`)
    const incIdx = nextReg(); emitIR(`  ${incIdx} = add i32 ${nextIdx}, 1`)
    emitIR(`  store i32 ${incIdx}, ptr ${idxAlloca}, align 4`)
    emitIR(`  br label %${condLabel}`)

    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak2
    continueLabel = savedContinue2
    loopBlockStackSaved = savedLoopStack2
}

function genWhile(id: int) {
    const condId = nGetI1(id)
    const bodyId = nGetI2(id)

    // D089 Phase 3: comptime while in comptime block
    if (comptimeDepth > 0) {
        let ctWhileLimit = 10000
        while (ctWhileLimit > 0) {
            const wCondTagged = genVal(condId)
            if (isCt(wCondTagged) == 0 || interpTruthy(payload(wCondTagged)) == 0) { break }
            genBlock(bodyId)
            if (interpCheckLoopExit() == 1) { break }
            ctWhileLimit = ctWhileLimit - 1
        }
        if (ctWhileLimit == 0) { println("[comptime] while loop exceeded 10000 iterations") }
        return
    }

    const condLabel = nextLabel("while.cond")
    const bodyLabel = nextLabel("while.body")
    const afterLabel = nextLabel("while.after")

    const savedBreak3 = breakLabel
    const savedContinue3 = continueLabel
    const savedLoopStack3 = loopBlockStackSaved
    breakLabel = afterLabel
    continueLabel = condLabel
    loopBlockStackSaved = blockPtrVarStack

    emitIR(`  br label %${condLabel}`)

    emitIR(`${condLabel}:`)
    const condVal = genExpr(condId)
    const r = emitCondToI1(condId, condVal)
    emitIR(`  br i1 ${r}, label %${bodyLabel}, label %${afterLabel}`)

    emitIR(`${bodyLabel}:`)
    terminated = 0
    genNestedBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${condLabel}`) }

    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak3
    continueLabel = savedContinue3
    loopBlockStackSaved = savedLoopStack3
}

function genDoWhile(id: int) {
    const bodyId = nGetI1(id)
    const condId = nGetI2(id)

    if (comptimeDepth > 0) {
        let ctDoLimit = 10000
        while (ctDoLimit > 0) {
            genBlock(bodyId)
            if (interpCheckLoopExit() == 1) { break }
            const dwCondTagged = genVal(condId)
            if (isCt(dwCondTagged) == 0 || interpTruthy(payload(dwCondTagged)) == 0) { break }
            ctDoLimit = ctDoLimit - 1
        }
        if (ctDoLimit == 0) { println("[comptime] do-while loop exceeded 10000 iterations") }
        return
    }

    const bodyLabel = nextLabel("dowhile.body")
    const condLabel = nextLabel("dowhile.cond")
    const afterLabel = nextLabel("dowhile.after")
    const savedBreak = breakLabel
    const savedContinue = continueLabel
    const savedLoopStack4 = loopBlockStackSaved
    breakLabel = afterLabel
    continueLabel = condLabel
    loopBlockStackSaved = blockPtrVarStack
    emitIR(`  br label %${bodyLabel}`)
    emitIR(`${bodyLabel}:`)
    terminated = 0
    genNestedBlock(bodyId)
    if (terminated == 0) { emitIR(`  br label %${condLabel}`) }
    emitIR(`${condLabel}:`)
    const condVal = genExpr(condId)
    const r = emitCondToI1(condId, condVal)
    emitIR(`  br i1 ${r}, label %${bodyLabel}, label %${afterLabel}`)
    emitIR(`${afterLabel}:`)
    terminated = 0
    breakLabel = savedBreak
    continueLabel = savedContinue
    loopBlockStackSaved = savedLoopStack4
}

function genSwitch(id: int) {
    const subjectId = nGetI1(id)
    const defaultId = nGetI2(id)
    const caseList = nGetList(id)

    if (comptimeDepth > 0) {
        const subjTagged = genVal(subjectId)
        if (isCt(subjTagged) == 1) {
            const subjPayload = payload(subjTagged)
            const subjKind = interpType(subjPayload)
            const subjStr = interpAsStr(subjPayload)
            const subjInt = subjKind == "int" ? interpAsInt(subjPayload) : 0
            let matched = 0
            if (caseList != "") {
                const ctCases = caseList.split(",")
                for (cc in ctCases) {
                    const ctCaseId = parseInt(cc)
                    if (ctCaseId <= 0) { continue }
                    const ctPatId = nGetI1(ctCaseId)
                    const ctBodyId = nGetI2(ctCaseId)
                    const ctPatType = nGetS1(ctPatId)
                    const ctPatVal = nGetS2(ctPatId)
                    let hit = 0
                    if (ctPatType == "STRING") {
                        if (subjStr == ctPatVal) { hit = 1 }
                    } else if (ctPatType == "INT") {
                        if (subjInt == parseInt(ctPatVal)) { hit = 1 }
                    } else if (ctPatType == "BOOL") {
                        if (interpTruthy(subjPayload) == parseInt(ctPatVal)) { hit = 1 }
                    } else if (ctPatType == "ENUM") {
                        if (interpEnumValues.has(ctPatVal) == 1) {
                            const ctResolved = interpEnumValues.getString(ctPatVal)
                            if (subjKind == "string") {
                                if (subjStr == ctResolved) { hit = 1 }
                            } else {
                                if (subjInt == parseInt(ctResolved)) { hit = 1 }
                            }
                        }
                    }
                    if (hit == 1) {
                        genBlock(ctBodyId)
                        matched = 1
                        break
                    }
                }
            }
            if (matched == 0 && defaultId > 0) { genBlock(defaultId) }
            if (interpBreakFlag == 1) { interpBreakFlag = 0 }
        }
        return
    }

    const subjectVal = genExpr(subjectId)
    const subjectType = inferType(subjectId)
    const afterLabel = nextLabel("switch.end")

    if (caseList != "") {
        const cases = caseList.split(",")
        for (c in cases) {
            const caseId = parseInt(c)
            if (caseId <= 0) { continue }
            const patId = nGetI1(caseId)
            const bodyId = nGetI2(caseId)
            const patType = nGetS1(patId)
            const patVal = nGetS2(patId)
            const thenLabel = nextLabel("switch.case")
            const nextLabel2 = nextLabel("switch.next")
            // Compare subject with pattern
            let cmpResult = ""
            let resolvedVal = patVal
            let useStringCmp = 0
            if (patType == "STRING" || subjectType == "string") { useStringCmp = 1 }
            if (patType == "ENUM") {
                if (enumValues.has(patVal) == 0) {
                    println(`error: unknown enum value '${patVal}' in switch case`)
                    exit(1)
                }
                resolvedVal = enumValues.getString(patVal)
                const dotIdx = patVal.indexOf(".")
                if (dotIdx > 0 && enumTypes.has(patVal.substring(0, dotIdx)) == 1) { useStringCmp = 1 }
            }
            if (useStringCmp == 1) {
                const patStr = addStringConst(resolvedVal)
                const cmp = nextReg(); emitIR(`  ${cmp} = call i32 @ss_string_eq(ptr ${subjectVal}, ptr ${patStr})`)
                const br = nextReg(); emitIR(`  ${br} = icmp ne i32 ${cmp}, 0`)
                cmpResult = br
            } else {
                const cmp = nextReg(); emitIR(`  ${cmp} = icmp eq i32 ${subjectVal}, ${resolvedVal}`)
                cmpResult = cmp
            }
            emitIR(`  br i1 ${cmpResult}, label %${thenLabel}, label %${nextLabel2}`)
            emitIR(`${thenLabel}:`)
            terminated = 0
            genNestedBlock(bodyId)
            if (terminated == 0) { emitIR(`  br label %${afterLabel}`) }
            emitIR(`${nextLabel2}:`)
        }
    }
    // Last switch.next block is the no-match fallthrough — needs a terminator
    terminated = 0
    // Default case
    if (defaultId > 0) {
        genNestedBlock(defaultId)
    }
    if (terminated == 0) { emitIR(`  br label %${afterLabel}`) }
    emitIR(`${afterLabel}:`)
    terminated = 0
}
