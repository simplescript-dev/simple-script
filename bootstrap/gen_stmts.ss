// gen_stmts.ss — Statement codegen: dispatcher, control flow, block handling
// Declaration/assignment/function codegen in gen_decls.ss.

import { genFuncDeclStmt, genVarDecl, genDestructureArray, genAssign, genMemberAssign, isOwnedExpr, genReturn } from "./gen_decls"

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

function registerEnum(id: int) {
    if (enumReady == 0) { enumValues = Map(); enumTypes = Map(); enumVariantNames = Map(); enumReady = 1 }
    const eName = nGetS1(id)
    const isStringEnum = nGetI1(id)
    if (isStringEnum == 1) { enumTypes.set(eName, "1") }
    const vl = nGetList(id)
    if (vl == "") { return }
    const parts = vl.split(",")
    let nameList = ""
    for (p in parts) {
        const vid = parseInt(p)
        if (vid > 0 && nGetKind(vid) == "ENUM_VARIANT") {
            const vName = nGetS1(vid)
            if (nameList == "") { nameList = vName } else { nameList = `${nameList}|${vName}` }
            if (isStringEnum == 1) {
                enumValues.set(`${eName}.${vName}`, nGetS2(vid))
            } else {
                const vVal = nGetI1(vid)
                enumValues.set(`${eName}.${vName}`, `${vVal}`)
            }
        }
    }
    enumVariantNames.set(eName, nameList)
}

// ── Statement handlers ──────────────────────────────────────

function genBreak() {
    if (breakLabel != "") {
        emitReleaseBlockVarsSince(loopBlockStackSaved)
        emitIR(`  br label %${breakLabel}`)
        terminated = 1
    }
}

function genContinueStmt() {
    if (continueLabel != "") {
        emitReleaseBlockVarsSince(loopBlockStackSaved)
        emitIR(`  br label %${continueLabel}`)
        terminated = 1
    }
}

function genPostfixStmt(id: int) {
    const kind = nGetKind(id)
    const pRef = varRef(nGetS1(id))
    const r1 = nextReg(); emitIR(`  ${r1} = load i32, ptr ${pRef}, align 4`)
    const r2 = nextReg()
    if (kind == "POSTFIX_INC") { emitIR(`  ${r2} = add i32 ${r1}, 1`) } else { emitIR(`  ${r2} = sub i32 ${r1}, 1`) }
    emitIR(`  store i32 ${r2}, ptr ${pRef}, align 4`)
}

function genIndexAssign(id: int) {
    const arrPtr = nextReg(); emitIR(`  ${arrPtr} = load ptr, ptr ${varRef(nGetS1(id))}, align 8`)
    const idxVal = genExpr(nGetI1(id))
    const valVal = genExpr(nGetI2(id))
    const vt = inferType(nGetI2(id))
    let v64 = valVal
    if (vt == "int" || vt == "auto" || vt == "") { const s = nextReg(); emitIR(`  ${s} = sext i32 ${valVal} to i64`); v64 = s }
    if (vt == "string" || vt == "ptr") { const c = nextReg(); emitIR(`  ${c} = ptrtoint ptr ${valVal} to i64`); v64 = c }
    emitIR(`  call void @ss_arraySet(ptr ${arrPtr}, i32 ${idxVal}, i64 ${v64})`)
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
    if (kind == "FUNC_DECL") { genFuncDeclStmt(id); return }
    if (kind == "VAR_DECL") { genVarDecl(id); return }
    if (kind == "DESTRUCTURE_ARRAY") { genDestructureArray(id); return }
    if (kind == "DESTRUCTURE_OBJECT") { genDestructureObject(id); return }
    if (kind == "ASSIGN") { genAssign(id); return }
    if (kind == "EXPR_STMT") { genExpr(nGetI1(id)); return }
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
    if (kind == "CLASS_DECL") { genClassDecl(id); return }
    if (kind == "ENUM_DECL") { registerEnum(id); return }
    if (kind == "INTERFACE_DECL") { return }
    if (kind == "TRY") { genTryCatch(id); return }
    if (kind == "THROW") { genThrow(id); return }
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

function genForIn(id: int) {
    const itemName = nGetS1(id)
    const iterableId = nGetI1(id)
    const bodyId = nGetI2(id)

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
    if (itemType == "string") {
        const elemPtr = nextReg(); emitIR(`  ${elemPtr} = inttoptr i64 ${elemVal} to ptr`)
        emitIR(`  store ptr ${elemPtr}, ptr %${itemLLName}, align 8`)
    } else if (itemType == "int") {
        const elemI32 = nextReg(); emitIR(`  ${elemI32} = trunc i64 ${elemVal} to i32`)
        emitIR(`  store i32 ${elemI32}, ptr %${itemLLName}, align 8`)
    } else if (itemType == "double") {
        const elemDb = nextReg(); emitIR(`  ${elemDb} = bitcast i64 ${elemVal} to double`)
        emitIR(`  store double ${elemDb}, ptr %${itemLLName}, align 8`)
    } else if (itemLLType == "ptr") {
        const elemPtr = nextReg(); emitIR(`  ${elemPtr} = inttoptr i64 ${elemVal} to ptr`)
        emitIR(`  store ptr ${elemPtr}, ptr %${itemLLName}, align 8`)
    } else {
        emitIR(`  store i64 ${elemVal}, ptr %${itemLLName}, align 8`)
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
