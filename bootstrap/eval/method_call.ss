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
        // I014 §路径 A — ctVar class instance w/ (className, methodName) 字段对组合 + invoke
        // sentinel → emit `call @<cn>_<mn>(ptr null)` 静态 IR(instance method 带 null this;
        // Phase 2 controller body 不访问 this,Phase 3 DI 容器接 singleton 后填实)。消除 comptime
        // 三元组 (path, cn, mn) 与 runtime method call 之间的 symbolic gap(D088 §反模式 禁
        // @comptimeEmit/runtime 反射)。funcRetTypes lookup 决定 LLVM 返回 LL type(string→ptr /
        // int→i32 / void→void);未注册时默认 ptr(按 Spring Boot @GetMapping 返 string body 惯例)。
        if (mcObjKind == "object" && mcMethod == "invoke") {
            const ctObjId = payload(mcObj)
            const cnTv = interpGetField(ctObjId, "className")
            const mnTv = interpGetField(ctObjId, "methodName")
            if (interpType(cnTv) == "string" && interpType(mnTv) == "string") {
                const cnStr = interpAsStr(cnTv)
                const mnStr = interpAsStr(mnTv)
                if (cnStr != "" && mnStr != "") {
                    callPreRegs = mcSavedCPR
                    const mangled = `${cnStr}_${mnStr}`
                    const retTy = funcRetTypes.has(mangled) == 1 ? funcRetTypes.getString(mangled) : "string"
                    const llRet = retTy == "void" ? "void" : (retTy == "int" ? "i32" : "ptr")
                    if (llRet == "void") {
                        emitIR(`  call void @${mangled}(ptr null)`)
                        return 0 - constVal("null") - 1
                    }
                    const resReg = nextReg()
                    emitIR(`  ${resReg} = call ${llRet} @${mangled}(ptr null)`)
                    return 0 - constVal(resReg) - 1
                }
            }
            return comptimeError(`static dispatch 'invoke' requires className+methodName fields on ctVar class instance`, astId)
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
