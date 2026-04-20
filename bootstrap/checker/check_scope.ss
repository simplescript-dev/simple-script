// SimpleScript Bootstrap Checker — Lexical scope
// State globals live in checker.ss driver layer; visible here via SS global scope.

function pushScope() {
    scopeId = scopeId + 1
    scopeParent.set(`${scopeId}`, `${currentScope}`)
    currentScope = scopeId
}

function popScope() {
    currentScope = parseInt(scopeParent.getString(`${currentScope}`))
}

function defineVar(name: string, varType: string, isConst: int) {
    const key = `${currentScope}:${name}`
    varNames.set(key, varType)
    if (isConst == 1) {
        varConst.set(key, "const")
    }
    const scopeKey = `${currentScope}`
    if (scopeVarNames.has(scopeKey) == 1) {
        scopeVarNames.set(scopeKey, `${scopeVarNames.getString(scopeKey)},${name}`)
    } else {
        scopeVarNames.set(scopeKey, name)
    }
}

function lookupVar(name: string): string {
    let s = currentScope
    while (s >= 0) {
        const key = `${s}:${name}`
        if (varNames.has(key) == 1) {
            return varNames.getString(key)
        }
        if (s == 0) { break }
        s = parseInt(scopeParent.getString(`${s}`))
    }
    return ""
}

function isVarConst(name: string): int {
    let s = currentScope
    while (s >= 0) {
        const key = `${s}:${name}`
        if (varNames.has(key) == 1) {
            return varConst.has(key)
        }
        if (s == 0) { break }
        s = parseInt(scopeParent.getString(`${s}`))
    }
    return 0
}
