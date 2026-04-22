// D108 §步骤 1: METHOD_CALL 迁子目录(原迁出 D107)
// 对称三段式:ctEnumNodes/runtime enum + Thread/super 短路 + args(NAMED_ARG/普通)+ comptime/runtime 分派

function evalMethodCall(astId: int): int {
    pendingSuperParent = resolveSuperParent(nGetI1(astId), astId)
    const mcMethod = nGetS1(astId)
    const mcObjNode = nGetI1(astId)
    if (nGetKind(mcObjNode) == "IDENT") {
        const mcObjName = nGetS1(mcObjNode)
        if (comptimeDepth > 0 && interpEnumNodes.has(mcObjName) == 1) {
            if (mcMethod == "values") { return ctVal(ctEnumListMethod(mcObjName, 0)) }
            if (mcMethod == "names") { return ctVal(ctEnumListMethod(mcObjName, 1)) }
            if (mcMethod == "valueOf") { return ctVal(ctEnumValueOfMethod(mcObjName, astId)) }
        }
        if (comptimeDepth > 0 && mcObjName == "reflect") {
            return ctReflectMethodDispatch(astId, mcMethod)
        }
        if (comptimeDepth == 0 && enumReady == 1 && enumDeclNodes.has(mcObjName) == 1) {
            if (mcMethod == "values") { return 0 - constVal(genEnumValues(mcObjName)) - 1 }
            if (mcMethod == "names") { return 0 - constVal(genEnumNames(mcObjName)) - 1 }
            if (mcMethod == "valueOf") { return 0 - constVal(genEnumValueOf(mcObjName, nGetList(astId))) - 1 }
        }
        if (comptimeDepth == 0) {
            if (mcObjName == "Thread" && mcMethod == "start") { return 0 - constVal(genMethodCall(astId)) - 1 }
            if (getVarType(mcObjName) == "" && classFields.has(mcObjName) == 1) { return 0 - constVal(genMethodCall(astId)) - 1 }
        }
    }
    if (comptimeDepth == 0 && pendingSuperParent != "") { return 0 - constVal(genMethodCall(astId)) - 1 }
    const mcObj = genVal(mcObjNode)
    let mcObjReg = ""
    if (isCt(mcObj) == 0) { mcObjReg = reg(mcObj) }
    const mcArgList = nGetList(astId)
    const mcSavedCPR = callPreRegs
    callPreRegs = new Map()
    let mcCtArgs: Array<string> = []
    let mcCtNamed = new Map()
    let mcHasNamed = 0
    if (mcArgList != "") {
        const mcArgParts = mcArgList.split(",")
        for (mcap in mcArgParts) {
            const mcArgId = parseInt(mcap)
            if (mcArgId > 0) {
                if (nGetKind(mcArgId) == "NAMED_ARG") {
                    mcHasNamed = 1
                    const mcnv = genVal(nGetI1(mcArgId))
                    if (isCt(mcnv) == 1) {
                        mcCtNamed.set(nGetS1(mcArgId), `${payload(mcnv)}`)
                    } else {
                        mcCtNamed.set(nGetS1(mcArgId), `${interpNewNull()}`)
                        callPreRegs.set(`${mcArgId}`, reg(mcnv))
                    }
                } else {
                    const mcav = genVal(mcArgId)
                    if (isCt(mcav) == 1) {
                        mcCtArgs = mcCtArgs.push(`${payload(mcav)}`)
                    } else {
                        mcCtArgs = mcCtArgs.push(`${interpNewNull()}`)
                        callPreRegs.set(`${mcArgId}`, reg(mcav))
                    }
                }
            }
        }
    }
    if (comptimeDepth > 0) {
        callPreRegs = mcSavedCPR
        if (isCt(mcObj) == 0) {
            return comptimeError(`cannot call method '${mcMethod}' on runtime value`, astId)
        }
        return ctMethodCallDispatch(astId, mcMethod, payload(mcObj), mcCtArgs, mcCtNamed, mcHasNamed)
    }
    // ctVal array/map 接收者无法 materialize 成寄存器(interp_value.ss:41 返 "0"),
    // 必须走 ctMethodCallDispatch 否则运行时 genMethodCall 发 `ss_mapKeysArray(ptr 0)`。
    // @methodOf handler 体常触发(comptimeDepth==0 + for-in 绑 ctVal)。
    if (isCt(mcObj) == 1) {
        const mcObjKind = interpType(payload(mcObj))
        if (mcObjKind == "array" || mcObjKind == "map") {
            callPreRegs = mcSavedCPR
            return ctMethodCallDispatch(astId, mcMethod, payload(mcObj), mcCtArgs, mcCtNamed, mcHasNamed)
        }
    }
    if (nGetI3(astId) > 0) {
        callPreRegs.set(`${mcObjNode}`, mcObjReg)
        const mcOptResult = genOptionalMethodCall(astId)
        callPreRegs = mcSavedCPR
        return 0 - constVal(mcOptResult) - 1
    }
    const mcResult = genMethodCall(astId, mcObjReg)
    callPreRegs = mcSavedCPR
    return 0 - constVal(mcResult) - 1
}
