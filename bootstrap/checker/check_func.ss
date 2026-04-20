// SimpleScript Bootstrap Checker — Function signatures
// Func name → return type registry + param count range + call-site arg count check.

// ── Function registry ─────────────────────────────────────────

function defineFunc(name: string, retType: string) {
    if (funcNames.has(name) == 0) {
        allFuncNameList = listAppendStr(allFuncNameList, name)
    }
    funcNames.set(name, retType)
}

function lookupFunc(name: string): int {
    return funcNames.has(name)
}

function defineFuncParams(name: string, minArgs: int, maxArgs: int) {
    if (funcParamMin.has(name) == 1) {
        const existMin = parseInt(funcParamMin.getString(name))
        const existMax = parseInt(funcParamMax.getString(name))
        if (minArgs < existMin) { funcParamMin.set(name, `${minArgs}`) }
        if (maxArgs > existMax) { funcParamMax.set(name, `${maxArgs}`) }
    } else {
        funcParamMin.set(name, `${minArgs}`)
        funcParamMax.set(name, `${maxArgs}`)
    }
}

// ── Call-site argument count checks ───────────────────────────

function countParamRange(paramListStr: string): string {
    let pMin = 0
    let pMax = 0
    if (paramListStr != "") {
        const parts = paramListStr.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId > 0 && nGetKind(pId) == "PARAM") {
                pMax = pMax + 1
                if (nGetI1(pId) <= 0 && nGetI2(pId) <= 0) {
                    pMin = pMin + 1
                }
            }
        }
    }
    return `${pMin},${pMax}`
}

function checkArgCount(label: string, name: string, argCount: int, minArgs: int, maxArgs: int, line: int, col: int) {
    if (argCount < minArgs || argCount > maxArgs) {
        if (minArgs == maxArgs) {
            checkerError(`${label} '${name}' expects ${minArgs} arguments, got ${argCount}`, line, col)
        } else {
            checkerError(`${label} '${name}' expects ${minArgs}-${maxArgs} arguments, got ${argCount}`, line, col)
        }
    }
}

function countArgs(listStr: string): int {
    if (listStr == "") { return 0 }
    let count = 0
    const parts = listStr.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0) { count = count + 1 }
    }
    return count
}

function hasSpreadArg(listStr: string): int {
    if (listStr == "") { return 0 }
    const parts = listStr.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0 && nGetKind(argId) == "SPREAD_ELEM") { return 1 }
    }
    return 0
}
