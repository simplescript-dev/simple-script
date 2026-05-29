// gen/exprs_ct_obj.ss — Comptime 对象构造 + 方法调用分发。
// ctNewExprDispatch 构造 user-class 实例、ctMethodCallDispatch 分发到 class / type / string-array-map。

function ctNewExprDispatch(className: string, ctArgVals: Array<string>, ctNamedArgs: Map, id: int): int {
    const realName = resolveCtTypeAlias(className)
    // I014 §路径 A — runtime class(RouteMeta 等在顶级 `class X {}` 声明,走 classNodeIds 注册,
    // 不入 interpClasses)也必须能在 comptime 块里 `new X(...)`。原只查 interpClasses 拒绝 runtime
    // class ctNew → Array<RouteMeta> 无法构造。classNodeIds 是 codegen 层对所有 class(含 runtime)
    // 的 AST node id 映射,与 interpBuildTypeInfo 的双注册源合集判定同构。
    if (interpClasses.has(realName) != 1 && classNodeIds.has(realName) != 1) {
        // D171 Phase 5 loud-gate (D088 §Phase 8):comptime `new X()` 中 X 未知不静默返 null
        // (probe PA 实测旧路径 exit 0 误编译),改 loud comptimeError exit(1)。
        return comptimeError(`unknown class: ${realName}`, id)
    }
    const objId = interpNewVal("object", realName)
    // parent chain walk,父类字段 prepend 在前 — 与 interpBuildTypeInfo 同构但这里消费 fId 取 defaultId。
    // D171 Phase 3 — node 解析 + parent 上溯走权威对称 helper(interpResolveClassNode /
    // interpResolveParent),与 interpFindMethod 同契约;顶层继承类的父类字段在 comptime 构造时
    // 才会被 prepend(此前 parent walk 只查 interpClassParents,顶层类恒断在第一层漏父字段)。
    let allFields = ""
    let cur = realName
    while (cur != "") {
        const nId = interpResolveClassNode(cur)
        if (nId == 0) { break }
        const paramList = nGetList(nId)
        if (paramList != "") { allFields = allFields == "" ? paramList : `${paramList},${allFields}` }
        cur = interpResolveParent(cur)
    }
    let ctFieldNames: Array<string> = []
    for (fp in allFields.split(",")) {
        if (fp == "") { continue }
        const fId = parseInt(fp)
        const fName = nGetS1(fId)
        ctFieldNames = ctFieldNames.push(fName)
        const defaultId = nGetI1(fId)
        const dv = defaultId > 0 ? genVal(defaultId) : 0
        interpSetField(objId, fName, defaultId > 0 && isCt(dv) == 1 ? payload(dv) : interpNewNull())
    }
    let posIdx = 0
    while (posIdx < ctArgVals.length()) {
        if (posIdx < ctFieldNames.length()) {
            interpSetField(objId, ctFieldNames[posIdx], parseInt(ctArgVals[posIdx]))
        }
        posIdx = posIdx + 1
    }
    const namedKeys = ctNamedArgs.keys()
    for (nk in namedKeys) {
        if (nk != "") {
            interpSetField(objId, nk, parseInt(ctNamedArgs.getString(nk)))
        }
    }
    return ctVal(objId)
}

function ctMethodCallDispatch(id: int, methodName: string, objPayload: int, ctArgVals: Array<string>, ctNamedArgs: Map, ctHasNamed: int): int {
    const objType = interpType(objPayload)
    if (objType == "string" || objType == "array" || objType == "map") {
        return ctVal(ctBuiltinMethod(objPayload, methodName, ctArgVals, id))
    }
    // TypeValue: T.fields()/T.name — read off the underlying class name
    if (objType == "type") {
        const typeName = interpAsStr(objPayload)
        if (methodName == "fields") { return ctVal(interpGetField(interpBuildTypeInfo(typeName), "fields")) }
        if (methodName == "name") { return ctVal(interpNewString(typeName)) }
        return comptimeError(`method '${methodName}' not supported on type value`, id)
    }
    if (objType != "object") {
        // D171 Phase 5 loud-gate (D088 §Phase 8):在非对象值上调方法不静默返 null
        // (probe PB `(5).bogusMethod()` 旧路径 exit 0 误编译),改 loud comptimeError exit(1)。
        return comptimeError(`cannot call method '${methodName}' on ${objType}`, id)
    }
    const className = interpAsStr(objPayload)
    if (methodName == "fields") {
        return ctVal(interpGetField(interpBuildTypeInfo(className), "fields"))
    }
    let lookupStart = className
    if (pendingSuperParent != "") {
        lookupStart = pendingSuperParent
    }
    const methodNode = interpFindMethod(lookupStart, methodName)
    if (methodNode == 0) {
        return comptimeError(`no method '${methodName}' on class ${lookupStart}`, id)
    }
    const ownerClass = interpLastFoundMethodClass
    const savedThis = interpThisVal
    const savedFunc = currentFunc
    const savedBreak = interpBreakFlag
    const savedContinue = interpContinueFlag
    const savedTerm = terminated
    const savedMethodClass = interpCurrentMethodClass
    interpBreakFlag = 0
    interpContinueFlag = 0
    terminated = 0
    interpThisVal = objPayload
    interpCurrentMethodClass = ownerClass
    ctCallCounter = ctCallCounter + 1
    currentFunc = `__ct_${ownerClass}_${methodName}_${ctCallCounter}`
    ctScopeStack = ctScopeStack.push(currentFunc)
    const mParamList = nGetList(methodNode)
    if (mParamList != "") {
        const mParams = mParamList.split(",")
        let mPosIdx = 0
        let mPi = 0
        while (mPi < mParams.length()) {
            const mPid = parseInt(mParams[mPi])
            const mPname = nGetS1(mPid)
            if (ctHasNamed == 1 && ctNamedArgs.has(mPname) == 1) {
                ctVars.set(`${currentFunc}:${mPname}`, `${ctVal(parseInt(ctNamedArgs.getString(mPname)))}`)
            } else if (mPosIdx < ctArgVals.length()) {
                ctVars.set(`${currentFunc}:${mPname}`, `${ctVal(parseInt(ctArgVals[mPosIdx]))}`)
                mPosIdx = mPosIdx + 1
            } else {
                const mDefId = nGetI1(mPid)
                if (mDefId > 0) {
                    const mDefVal = genVal(mDefId)
                    ctVars.set(`${currentFunc}:${mPname}`, `${isCt(mDefVal) == 1 ? mDefVal : ctVal(interpNewNull())}`)
                } else {
                    ctVars.set(`${currentFunc}:${mPname}`, `${ctVal(interpNewNull())}`)
                }
            }
            mPi = mPi + 1
        }
    }
    const mBodyId = nGetI1(methodNode)
    if (mBodyId > 0) { genBlock(mBodyId) }
    let mResult = interpNewNull()
    if (interpReturnFlag == 1) {
        mResult = interpReturnVal
        interpReturnFlag = 0
        interpReturnVal = 0
    }
    ctPopScope()
    currentFunc = savedFunc
    interpThisVal = savedThis
    interpCurrentMethodClass = savedMethodClass
    interpBreakFlag = savedBreak
    interpContinueFlag = savedContinue
    terminated = savedTerm
    return ctVal(mResult)
}
