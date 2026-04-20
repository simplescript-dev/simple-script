// gen/exprs_ct_obj.ss — Comptime 对象构造 + 方法调用分发。
// ctNewExprDispatch 构造 user-class 实例、ctMethodCallDispatch 分发到 class / type / string-array-map。

function ctNewExprDispatch(className: string, ctArgVals: Array<string>, ctNamedArgs: Map): int {
    const realName = resolveCtTypeAlias(className)
    if (interpClasses.has(realName) != 1) {
        println(`[comptime] unknown class: ${realName}`)
        return ctVal(interpNewNull())
    }
    const objId = interpNewVal("object", realName)
    const allFields = interpCollectFields(realName)
    let ctFieldNames: Array<string> = []
    if (allFields != "") {
        const fieldParts = allFields.split(",")
        let fi = 0
        while (fi < fieldParts.length()) {
            const fId = parseInt(fieldParts[fi])
            const fName = nGetS1(fId)
            ctFieldNames = ctFieldNames.push(fName)
            const defaultId = nGetI1(fId)
            if (defaultId > 0) {
                const dv = genVal(defaultId)
                interpSetField(objId, fName, isCt(dv) == 1 ? payload(dv) : interpNewNull())
            } else {
                interpSetField(objId, fName, interpNewNull())
            }
            fi = fi + 1
        }
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
        return ctVal(ctBuiltinMethod(objPayload, methodName, ctArgVals))
    }
    // TypeValue: T.fields()/T.name — read off the underlying class name
    if (objType == "type") {
        const typeName = interpAsStr(objPayload)
        if (methodName == "fields") { return ctVal(interpCtFieldsArray(typeName)) }
        if (methodName == "name") { return ctVal(interpNewString(typeName)) }
        return comptimeError(`method '${methodName}' not supported on type value`, id)
    }
    if (objType != "object") {
        println(`[comptime] cannot call method '${methodName}' on ${objType}`)
        return ctVal(interpNewNull())
    }
    const className = interpAsStr(objPayload)
    if (methodName == "fields") {
        return ctVal(interpCtFieldsArray(className))
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
