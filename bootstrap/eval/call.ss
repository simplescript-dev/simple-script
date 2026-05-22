// CALL 子目录文件(原 eval_expr.ss 迁出 — feedback_600_split_not_inline)
// (F1 GATE 600 守门:eval_expr.ss ≤ 600,evalCall 80 行无法 inline;见 memory feedback_f1_gate_semantic)
// 对称三段式:泛型 2 分支 + callPreRegs 三态 + args 3 分支(NAMED_ARG/SPREAD_ELEM/普通)
//   + comptime/runtime 分派 + 2 处 mv 编码 (genGenericCall / genCall)

function evalCall(astId: int): int {
    const callName = nGetS1(astId)
    const callArgList = nGetList(astId)
    if (genericFuncNodes.has(callName) == 1) {
        if (comptimeMustBeKnown == 1) {
            if (ctFuncNodes.has(callName) == 0) {
                ctFuncNodes.set(callName, genericFuncNodes.getString(callName))
            }
        } else {
            return 0 - constVal(genGenericCall(astId, callName, callArgList)) - 1
        }
    }
    // D148 Phase 5: outer pre-eval 4 helper 反推循环全删(含 mangled name resolution) — checker 已写
    // nSetS2(check_exprs.ss:91 CALL fn arg 反推 ★ + check_types.ss:42 checkerInferType 4 case)。
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
                            if (comptimeMustBeKnown == 1) {
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
                        if (comptimeMustBeKnown == 1) {
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
    if (comptimeMustBeKnown == 1) {
        callPreRegs = savedCallPreRegs
        return ctCallDispatch(astId, callName, callCtArgVals, callCtNamedArgs, callCtHasNamed)
    }
    const callResult = 0 - constVal(genCall(astId)) - 1
    callPreRegs = savedCallPreRegs
    return callResult
}
