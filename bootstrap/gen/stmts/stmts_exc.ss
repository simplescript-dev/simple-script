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

    if (comptimeMustBeKnown == 1) {
        // D171 Phase 4: comptime try/catch/finally 走 flag 模拟(无 runtime 栈/landingpad)。
        // try body 跑完若 interpThrowFlag set → 派发 catch(消费 flag);finally 始终跑。
        if (tryBody > 0) { genBlock(tryBody) }
        if (interpThrowFlag == 1) {
            const thrownVal = interpThrowVal
            interpThrowFlag = 0
            interpThrowVal = 0
            ctDispatchComptimeCatch(catchList, thrownVal)
        }
        if (finallyBody > 0) { ctRunComptimeFinally(finallyBody) }
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
        emitEntryAlloca(`%${errLLName}`, "ptr", 8)
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
    if (comptimeMustBeKnown == 1) {
        // D171 Phase 4: comptime throw 不再直接 exit(1),改 raise 异常 flag(镜像
        // interpReturnFlag),由 enclosing genTryCatch 捕获;未捕获在 runComptimeBlockBody
        // 升 loud comptimeError(D088 §Phase 8 不变量)。
        const throwVal = genVal(nGetI1(id))
        if (isCt(throwVal) == 1) {
            interpThrowFlag = 1
            interpThrowVal = payload(throwVal)
            return
        }
        // 非编译期常量 throw 值 = 真 runtime-only,loud(D088 §Phase 8)
        comptimeError(`throw value is not compile-time constant`, nGetI1(id))
        return
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

// ── comptime 异常派发(D171 Phase 4)──────────────────────────
// 走 D093 统一 evalExpr/genBlock + 现有 ctVars / interpResolveParent,不新开 ct* 异常注册表
// (D171 §拒绝准则 / D088 §反模式)。

// catch 派发:多 clause 顺序匹配(untyped 全捕 / typed 走继承链),bind 异常值入 ctVars
// (与 VAR_DECL 同 `${currentFunc}:${name}` key 协议)后跑 catch body;无匹配 clause →
// re-raise(重置 flag 交外层 try 或 runComptimeBlockBody loud gate)。
function ctDispatchComptimeCatch(catchList: string, thrownVal: int) {
    if (catchList == "") {
        interpThrowFlag = 1
        interpThrowVal = thrownVal
        return
    }
    let handled = 0
    for (cp in catchList.split(",")) {
        const cid = parseInt(cp)
        const errType = nGetS2(cid)
        const errName = nGetS1(cid)
        const catchBody = nGetI1(cid)
        if (errType == "" || ctThrownMatchesType(thrownVal, errType) == 1) {
            ctVars.set(`${currentFunc}:${errName}`, `${ctVal(thrownVal)}`)
            if (catchBody > 0) { genBlock(catchBody) }
            handled = 1
            break
        }
    }
    if (handled == 0) {
        interpThrowFlag = 1
        interpThrowVal = thrownVal
    }
}

// thrown 值是否匹配 catch 类型注解:仅对象走继承链(interpResolveParent — Phase 3 权威
// consult-both,与 interpFindMethod / super 解析同协议);非对象(string/int 等)不匹配 typed catch。
function ctThrownMatchesType(thrownVal: int, errType: string): int {
    if (interpType(thrownVal) != "object") { return 0 }
    let cur = tvStringOf(thrownVal)
    while (cur != "") {
        if (cur == errType) { return 1 }
        cur = interpResolveParent(cur)
    }
    return 0
}

// finally 始终执行:save+clear try/catch 留下的 pending throw/return,跑 finally body,
// 若 finally 自身未抛/未返则恢复 pending(标准语义:正常 finally 不吞控制流;finally 自身
// throw/return 覆盖 pending)。
function ctRunComptimeFinally(finallyBody: int) {
    const savedThrow = interpThrowFlag
    const savedThrowVal = interpThrowVal
    const savedReturn = interpReturnFlag
    const savedReturnVal = interpReturnVal
    interpThrowFlag = 0
    interpThrowVal = 0
    interpReturnFlag = 0
    interpReturnVal = 0
    genBlock(finallyBody)
    if (interpThrowFlag == 0 && interpReturnFlag == 0) {
        interpThrowFlag = savedThrow
        interpThrowVal = savedThrowVal
        interpReturnFlag = savedReturn
        interpReturnVal = savedReturnVal
    }
}
