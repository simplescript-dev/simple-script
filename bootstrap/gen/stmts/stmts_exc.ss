// gen/stmts_exc.ss — 异常 codegen:try/catch/finally、throw、rethrow。

import { genBlock, genNestedBlock } from "./stmts_core"

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

function genThrow(id: int) {
    if (comptimeDepth > 0) {
        const throwVal = genVal(nGetI1(id))
        if (isCt(throwVal) == 1) {
            const throwMsg = interpToStr(payload(throwVal))
            println(`comptime error: ${throwMsg}`)
        } else {
            println(`comptime error: throw value is not compile-time constant at line ${nGetLine(nGetI1(id))}`)
        }
        exit(1)
    }
    const exprId = nGetI1(id)
    const exprVal = genExpr(exprId)
    const exprType = inferType(exprId)
    if (classFields.has(exprType) == 1 && classFieldTypes.has(`${exprType}.message`) == 1) {
        emitIR(`  store i32 1, ptr @ss_exc_is_obj`)
        emitIR(`  store ptr ${exprVal}, ptr @ss_exc_obj`)
        // Byte-offset GEP avoids cross-module forward-ref of `%${exprType}`
        // when exprType is decl'd in a sibling lib module (D139 §A.2 H1).
        const msgReg = emitByteOffsetFieldLoad(exprType, exprVal, "message")
        emitIR(`  call void @ss_throw(ptr ${msgReg})`)
    } else {
        emitIR(`  store i32 0, ptr @ss_exc_is_obj`)
        emitIR(`  store ptr null, ptr @ss_exc_obj`)
        emitIR(`  call void @ss_throw(ptr ${exprVal})`)
    }
    emitIR("  unreachable")
    terminated = 1
}
