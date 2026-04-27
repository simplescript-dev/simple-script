// NEW_EXPR 子目录文件(原 eval_expr.ss 迁出)
// 对称:泛型类 + Map/Set 短路 + callPreRegs 三态 + args(NAMED_ARG/普通)+ comptime/runtime 分派

function evalNewExpr(astId: int): int {
    const newClassName = nGetS1(astId)
    if (genericClassNodes.has(newClassName) == 1) {
        if (comptimeDepth > 0) {
            if (interpClasses.has(newClassName) == 0) {
                interpClasses.set(newClassName, genericClassNodes.getString(newClassName))
            }
        } else {
            return 0 - constVal(genGenericNewExpr(astId, newClassName)) - 1
        }
    }
    if (newClassName == "Map" || newClassName == "Set") {
        if (comptimeDepth > 0) { return ctVal(interpNewMap()) }
        return 0 - constVal(genNewExpr(astId)) - 1
    }
    const savedNewPreRegs = callPreRegs
    callPreRegs = new Map()
    let newCtArgVals: Array<string> = []
    let newCtNamedArgs = new Map()
    const newArgList = nGetList(astId)
    // D143 Phase 2: NAMED_ARG OBJ_LITERAL 嵌套反推前移 — D141/D142 H10 同模式
    // (eval/new_expr.ss line 38 pre-eval `genVal(nGetI1(newArgId))` 之前 inner OBJ_LITERAL
    // 必须 rewrite,否则 genVal unknown kind fallback "ptr 0" silent miscompile;H3 嵌套链路)
    // D144 Phase 2: 同点扩 TERNARY — NAMED_ARG inner TERNARY 也需 branchType 反推(field 类型),
    //   否则 outer call site `genVal(napValId)` 路过 TERNARY 走默认 phi llType silent miscompile;
    //   D141/D142/D143 H10 cross-D 反思继承 — feedback_h10_cross_d_verify.md
    if (comptimeDepth == 0 && newArgList != "") {
        const newArgPartsR = newArgList.split(",")
        for (napR in newArgPartsR) {
            const newArgIdR = parseInt(napR)
            if (newArgIdR > 0 && nGetKind(newArgIdR) == "NAMED_ARG") {
                const napValId = nGetI1(newArgIdR)
                if (napValId > 0) {
                    const napFieldKey = `${newClassName}.${nGetS1(newArgIdR)}`
                    if (classFieldTypes.has(napFieldKey) == 1) {
                        const napFieldType = classFieldTypes.getString(napFieldKey)
                        if (nGetKind(napValId) == "OBJ_LITERAL") {
                            inferObjLiteralFromType(napValId, napFieldType)
                        } else if (nGetKind(napValId) == "TERNARY" && nGetS2(napValId) == "" && napFieldType != "" && napFieldType != "auto") {
                            nSetS2(napValId, napFieldType)
                        }
                    }
                }
            }
        }
    }
    if (newArgList != "") {
        const newArgParts = newArgList.split(",")
        for (nap in newArgParts) {
            const newArgId = parseInt(nap)
            if (newArgId > 0) {
                if (nGetKind(newArgId) == "NAMED_ARG") {
                    const nav = genVal(nGetI1(newArgId))
                    if (isCt(nav) == 1) {
                        newCtNamedArgs.set(nGetS1(newArgId), `${payload(nav)}`)
                    } else {
                        newCtNamedArgs.set(nGetS1(newArgId), `${interpNewNull()}`)
                        callPreRegs.set(`${nGetI1(newArgId)}`, reg(nav))
                    }
                } else {
                    const av = genVal(newArgId)
                    if (isCt(av) == 1) {
                        newCtArgVals = newCtArgVals.push(`${payload(av)}`)
                    } else {
                        newCtArgVals = newCtArgVals.push(`${interpNewNull()}`)
                        callPreRegs.set(`${newArgId}`, reg(av))
                    }
                }
            }
        }
    }
    if (comptimeDepth > 0) {
        callPreRegs = savedNewPreRegs
        return ctNewExprDispatch(newClassName, newCtArgVals, newCtNamedArgs)
    }
    const newResult = 0 - constVal(genNewExpr(astId)) - 1
    callPreRegs = savedNewPreRegs
    return newResult
}
