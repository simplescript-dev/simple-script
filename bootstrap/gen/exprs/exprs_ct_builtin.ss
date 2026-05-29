// gen/exprs_ct_builtin.ss — Comptime 内置类型方法分发:string / array / map 以及 lambda 调用 (ctCallValue)。
// ctBuiltinMethod 为 ctMethodCallDispatch 对 string/array/map 的委托入口。

function ctCallValue(fnValId: int, argVals: Array<string>, id: int): int {
    if (interpType(fnValId) != "fn") {
        // D171 Phase 5 loud-gate (D088 §Phase 8):非函数值被当回调调用(probe PL `[..].map(5)`
        // 旧路径每元素静默返 null exit 0 误编译),改 loud comptimeError exit(1)。
        return comptimeError(`comptime callback value is not a function`, id)
    }
    // D171 Phase 5 根因修复:fn-value 的 ARROW_FUNC astId 存 tvI1(interp_obj.ss:106
    // `tvI1[id]=parseInt(payload)`),须 interpAsInt 读 int 槽 —— 旧 `parseInt(interpAsStr(...))`
    // 读空的 string 槽恒返 0 → funcNodeId=0 → genBlock 不跑 → 高阶数组方法(map/filter/
    // reduce/forEach)回调静默返 null/0(probe X11 实测)。sibling ctResolveFnNodeId
    // (exprs_ct_call.ss:30)早已 interpAsInt,此处对齐。
    const funcNodeId = interpAsInt(fnValId)
    const paramList = nGetList(funcNodeId)
    const bodyId = nGetI1(funcNodeId)

    const savedFunc = currentFunc
    const savedBreak = interpBreakFlag
    const savedContinue = interpContinueFlag
    const savedTerm = terminated
    interpBreakFlag = 0
    interpContinueFlag = 0
    terminated = 0

    ctCallCounter = ctCallCounter + 1
    currentFunc = `__ct_lambda_${ctCallCounter}`
    ctScopeStack = ctScopeStack.push(currentFunc)

    let paramNames: Array<string> = []
    if (paramList != "") {
        const params = paramList.split(",")
        let pi = 0
        while (pi < params.length() && pi < argVals.length()) {
            const pname = nGetS1(parseInt(params[pi]))
            ctVars.set(`${currentFunc}:${pname}`, `${ctVal(parseInt(argVals[pi]))}`)
            paramNames = paramNames.push(pname)
            pi = pi + 1
        }
    }

    if (bodyId > 0) { genBlock(bodyId) }

    let result = interpNewNull()
    if (interpReturnFlag == 1) {
        result = interpReturnVal
        interpReturnFlag = 0
        interpReturnVal = 0
    }

    let di = 0
    while (di < paramNames.length()) {
        ctVars.delete(`${currentFunc}:${paramNames[di]}`)
        di = di + 1
    }
    ctPopScope()
    currentFunc = savedFunc
    interpBreakFlag = savedBreak
    interpContinueFlag = savedContinue
    terminated = savedTerm
    return result
}

function ctStringMethod(objVal: int, method: string, argVals: Array<string>, id: int): int {
    const s = interpAsStr(objVal)
    if (method == "length") { return interpNewInt(s.length()) }
    if (method == "trim") { return interpNewString(s.trim()) }
    if (method == "toUpperCase") { return interpNewString(s.toUpperCase()) }
    if (method == "toLowerCase") { return interpNewString(s.toLowerCase()) }
    if (method == "split") {
        const sep = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        const parts = s.split(sep)
        const arr = interpNewArray("")
        let i = 0
        while (i < parts.length()) {
            interpArrayPush(arr, interpNewString(parts[i]))
            i = i + 1
        }
        return arr
    }
    if (method == "indexOf") {
        const sub = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        return interpNewInt(s.indexOf(sub))
    }
    if (method == "substring") {
        const start = argVals.length() > 0 ? interpAsInt(parseInt(argVals[0])) : 0
        const len = argVals.length() > 1 ? interpAsInt(parseInt(argVals[1])) : s.length()
        return interpNewString(s.substring(start, len))
    }
    if (method == "replace") {
        const old = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        const rep = argVals.length() > 1 ? interpAsStr(parseInt(argVals[1])) : ""
        return interpNewString(s.replace(old, rep))
    }
    if (method == "startsWith") {
        const prefix = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        return interpNewInt(s.startsWith(prefix))
    }
    if (method == "endsWith") {
        const suffix = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        return interpNewInt(s.endsWith(suffix))
    }
    if (method == "charAt") {
        const idx = argVals.length() > 0 ? interpAsInt(parseInt(argVals[0])) : 0
        return interpNewString(s.charAt(idx))
    }
    if (method == "includes") {
        const sub = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ""
        return interpNewInt(s.indexOf(sub) >= 0 ? 1 : 0)
    }
    if (method == "repeat") {
        const n = argVals.length() > 0 ? interpAsInt(parseInt(argVals[0])) : 0
        let result = ""
        let i = 0
        while (i < n) {
            result = `${result}${s}`
            i = i + 1
        }
        return interpNewString(result)
    }
    // D171 Phase 5 loud-gate (D088 §Phase 8):未知字符串方法不静默返 null(probe PC 旧路径
    // exit 0 误编译),改 loud comptimeError exit(1)。
    return comptimeError(`unsupported string method: ${method}`, id)
}

function ctArrayMethod(objVal: int, method: string, argVals: Array<string>, id: int): int {
    if (method == "push") { return interpArrayPush(objVal, parseInt(argVals[0])) }
    const len = interpArrayLen(objVal)
    if (method == "length") { return interpNewInt(len) }
    if (method == "join") {
        const sep = argVals.length() > 0 ? interpAsStr(parseInt(argVals[0])) : ","
        let result = ""
        let i = 0
        while (i < len) {
            if (i > 0) { result = `${result}${sep}` }
            result = `${result}${interpToStr(interpArrayGet(objVal, i))}`
            i = i + 1
        }
        return interpNewString(result)
    }
    if (method == "indexOf") {
        const target = parseInt(argVals[0])
        let i = 0
        while (i < len) {
            if (interpValEquals(interpArrayGet(objVal, i), target) == 1) {
                return interpNewInt(i)
            }
            i = i + 1
        }
        return interpNewInt(-1)
    }
    if (method == "slice") {
        let start = argVals.length() > 0 ? interpAsInt(parseInt(argVals[0])) : 0
        let end = argVals.length() > 1 ? interpAsInt(parseInt(argVals[1])) : len
        if (start < 0) { start = len + start }
        if (end < 0) { end = len + end }
        if (start < 0) { start = 0 }
        if (end > len) { end = len }
        const newArr = interpNewArray("")
        let i = start
        while (i < end) {
            interpArrayPush(newArr, interpArrayGet(objVal, i))
            i = i + 1
        }
        return newArr
    }
    if (method == "map") {
        const fnVal = parseInt(argVals[0])
        const newArr = interpNewArray("")
        let i = 0
        while (i < len) {
            let callArgs: Array<string> = []
            callArgs = callArgs.push(`${interpArrayGet(objVal, i)}`)
            interpArrayPush(newArr, ctCallValue(fnVal, callArgs, id))
            i = i + 1
        }
        return newArr
    }
    if (method == "filter") {
        const fnVal = parseInt(argVals[0])
        const newArr = interpNewArray("")
        let i = 0
        while (i < len) {
            const elemId = interpArrayGet(objVal, i)
            let callArgs: Array<string> = []
            callArgs = callArgs.push(`${elemId}`)
            if (interpTruthy(ctCallValue(fnVal, callArgs, id)) == 1) {
                interpArrayPush(newArr, elemId)
            }
            i = i + 1
        }
        return newArr
    }
    if (method == "forEach") {
        const fnVal = parseInt(argVals[0])
        let i = 0
        while (i < len) {
            let callArgs: Array<string> = []
            callArgs = callArgs.push(`${interpArrayGet(objVal, i)}`)
            ctCallValue(fnVal, callArgs, id)
            i = i + 1
        }
        return interpNewNull()
    }
    if (method == "reduce") {
        const fnVal = parseInt(argVals[0])
        let acc = argVals.length() > 1 ? parseInt(argVals[1]) : interpNewNull()
        let i = 0
        while (i < len) {
            let callArgs: Array<string> = []
            callArgs = callArgs.push(`${acc}`)
            callArgs = callArgs.push(`${interpArrayGet(objVal, i)}`)
            acc = ctCallValue(fnVal, callArgs, id)
            i = i + 1
        }
        return acc
    }
    // D171 Phase 5 loud-gate (D088 §Phase 8 不变量):未知数组方法不静默返 null
    // (probe PD 实测旧路径 exit 0 误编译),改 loud comptimeError exit(1)。
    return comptimeError(`unsupported array method: ${method}`, id)
}

function ctMapMethod(objVal: int, method: string, argVals: Array<string>, id: int): int {
    if (method == "set") {
        const key = interpAsStr(parseInt(argVals[0]))
        interpMapSet(objVal, key, parseInt(argVals[1]))
        return interpNewNull()
    }
    if (method == "get") {
        const key = interpAsStr(parseInt(argVals[0]))
        return interpMapGet(objVal, key)
    }
    // getString 宽松(任何 kind coerce 到 string),getInt/getBool/getDouble/getArray 严格返
    // typed tv 供原生算术/比较/索引(`a+b`、`==true`、`arr[i]`);value 非 AstNodeId int
    // 时原样返(普通 Map 调 typed getter 的兼容 fallback,严格 annotation-only 分派待
    // I003b strict marker)。getArray 返 array tv,元素由 evalAnnotationArg 递归 eval(I005)。
    if (method == "getString" || method == "getInt" || method == "getBool" || method == "getDouble" || method == "getArray") {
        const key = interpAsStr(parseInt(argVals[0]))
        const rawTv = interpMapGet(objVal, key)
        let evaled = rawTv
        if (interpType(rawTv) == "int") { evaled = evalAnnotationArg(interpAsInt(rawTv)) }
        if (method == "getString") { return interpNewString(interpToStr(evaled)) }
        return evaled
    }
    if (method == "has") {
        const key = interpAsStr(parseInt(argVals[0]))
        return interpNewInt(interpMapHas(objVal, key))
    }
    if (method == "delete") {
        const key = interpAsStr(parseInt(argVals[0]))
        interpMapDelete(objVal, key)
        return interpNewNull()
    }
    if (method == "keys") { return interpMapGetKeys(objVal) }
    if (method == "size") { return interpNewInt(interpMapGetSize(objVal)) }
    // D171 Phase 5 loud-gate (D088 §Phase 8):未知 Map 方法不静默返 null(probe PE 旧路径
    // exit 0 误编译),改 loud comptimeError exit(1)。
    return comptimeError(`unsupported map method: ${method}`, id)
}

function ctBuiltinMethod(objPayload: int, methodName: string, argVals: Array<string>, id: int): int {
    const objType = interpType(objPayload)
    if (objType == "string") { return ctStringMethod(objPayload, methodName, argVals, id) }
    if (objType == "array") { return ctArrayMethod(objPayload, methodName, argVals, id) }
    if (objType == "map") { return ctMapMethod(objPayload, methodName, argVals, id) }
    // D171 Phase 5 loud-gate (D088 §Phase 8):caller (exprs_ct_obj.ss:57) 已守 string/array/map,
    // 此处防御 unreachable;补 loud 维持不变量完整性(代码演化若可达则 loud 而非静默)。
    return comptimeError(`no built-in method '${methodName}' on ${objType}`, id)
}
