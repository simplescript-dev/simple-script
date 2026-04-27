// CALL 子目录文件(原 eval_expr.ss 迁出 — feedback_600_split_not_inline)
// (F1 GATE 600 守门:eval_expr.ss ≤ 600,evalCall 80 行无法 inline;见 memory feedback_f1_gate_semantic)
// 对称三段式:泛型 2 分支 + callPreRegs 三态 + args 3 分支(NAMED_ARG/SPREAD_ELEM/普通)
//   + comptime/runtime 分派 + 2 处 mv 编码 (genGenericCall / genCall)

function evalCall(astId: int): int {
    const callName = nGetS1(astId)
    const callArgList = nGetList(astId)
    if (genericFuncNodes.has(callName) == 1) {
        if (comptimeDepth > 0) {
            if (ctFuncNodes.has(callName) == 0) {
                ctFuncNodes.set(callName, genericFuncNodes.getString(callName))
            }
        } else {
            return 0 - constVal(genGenericCall(astId, callName, callArgList)) - 1
        }
    }
    // D141 Phase 2.2: 在 pre-eval 之前 resolve mangled name + 反推 ARROW_FUNC PARAM s2
    // (eval/call.ss pre-eval `genVal(callArgId)` 触发 genArrowFunc 必须先看到回填的 PARAM s2)
    if (comptimeDepth == 0 && callArgList != "") {
        let callResolvedR = callName
        if (overloadCount.has(callName) == 1 && parseInt(overloadCount.getString(callName)) > 1) {
            const callSigR = argsSig(callArgList)
            if (callSigR != "" && funcRetTypes.has(`${callName}_${callSigR}`) == 1) {
                callResolvedR = `${callName}_${callSigR}`
            }
        }
        const callArgPartsR = callArgList.split(",")
        let callArgIdxR = 0
        for (capR in callArgPartsR) {
            const callArgIdR = parseInt(capR)
            if (callArgIdR > 0) {
                inferArrowFuncParams(callArgIdR, callResolvedR, callArgIdxR)
                // D142 Phase 2: ARRAY_LIT 反推前移 — D141 H10 同模式
                inferArrayLitElems(callArgIdR, callResolvedR, callArgIdxR)
                callArgIdxR = callArgIdxR + 1
            }
        }
    }
    const savedCallPreRegs = callPreRegs
    callPreRegs = new Map()
    let callCtArgVals: Array<string> = []
    let callCtNamedArgs = new Map()
    let callCtHasNamed = 0
    if (callArgList != "") {
        const callArgParts = callArgList.split(",")
        for (cap in callArgParts) {
            const callArgId = parseInt(cap)
            if (callArgId > 0) {
                if (nGetKind(callArgId) == "NAMED_ARG") {
                    callCtHasNamed = 1
                    const nav = genVal(nGetI1(callArgId))
                    if (isCt(nav) == 1) {
                        callCtNamedArgs.set(nGetS1(callArgId), `${payload(nav)}`)
                    } else {
                        callCtNamedArgs.set(nGetS1(callArgId), `${interpNewNull()}`)
                        callPreRegs.set(`${callArgId}`, reg(nav))
                    }
                } else if (nGetKind(callArgId) == "SPREAD_ELEM") {
                    const srcVal = genVal(nGetI1(callArgId))
                    if (isCt(srcVal) == 1) {
                        const srcPayload = payload(srcVal)
                        if (interpType(srcPayload) != "array") {
                            if (comptimeDepth > 0) {
                                println(`error: [comptime] cannot spread non-array value at line ${nGetLine(callArgId)}:${nGetCol(callArgId)}`)
                                exit(1)
                            }
                            callPreRegs.set(`${nGetI1(callArgId)}`, reg(srcVal))
                        } else {
                            const srcLen = interpArrayLen(srcPayload)
                            let srcI = 0
                            while (srcI < srcLen) {
                                const srcElemId = interpArrayGet(srcPayload, srcI)
                                if (srcElemId > 0) { callCtArgVals = callCtArgVals.push(`${srcElemId}`) }
                                srcI = srcI + 1
                            }
                        }
                    } else {
                        if (comptimeDepth > 0) {
                            println(`error: [comptime] cannot spread runtime value at line ${nGetLine(callArgId)}:${nGetCol(callArgId)}`)
                            exit(1)
                        }
                        callPreRegs.set(`${nGetI1(callArgId)}`, reg(srcVal))
                    }
                } else {
                    const av = genVal(callArgId)
                    if (isCt(av) == 1) {
                        callCtArgVals = callCtArgVals.push(`${payload(av)}`)
                    } else {
                        callCtArgVals = callCtArgVals.push(`${interpNewNull()}`)
                        callPreRegs.set(`${callArgId}`, reg(av))
                    }
                }
            }
        }
    }
    if (comptimeDepth > 0) {
        callPreRegs = savedCallPreRegs
        return ctCallDispatch(astId, callName, callCtArgVals, callCtNamedArgs, callCtHasNamed)
    }
    const callResult = 0 - constVal(genCall(astId)) - 1
    callPreRegs = savedCallPreRegs
    return callResult
}
