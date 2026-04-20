// check_suggest.ss — Suggestion engine for checker error messages (I004 Phase 4)
// Used by check_stmts.ss via textual import. No own imports needed.

function editDistance(a: string, b: string): int {
    const aLen = a.length()
    const bLen = b.length()
    if (aLen == 0) { return bLen }
    if (bLen == 0) { return aLen }
    let d = Map()
    let i = 0
    while (i <= aLen) {
        d.set(`${i},0`, `${i}`)
        i = i + 1
    }
    let j = 0
    while (j <= bLen) {
        d.set(`0,${j}`, `${j}`)
        j = j + 1
    }
    i = 1
    while (i <= aLen) {
        j = 1
        while (j <= bLen) {
            let cost = 1
            if (charCodeAt(a, i - 1) == charCodeAt(b, j - 1)) {
                cost = 0
            }
            const del = parseInt(d.getString(`${i - 1},${j}`)) + 1
            const ins = parseInt(d.getString(`${i},${j - 1}`)) + 1
            const rep = parseInt(d.getString(`${i - 1},${j - 1}`)) + cost
            let minVal = del
            if (ins < minVal) { minVal = ins }
            if (rep < minVal) { minVal = rep }
            d.set(`${i},${j}`, `${minVal}`)
            j = j + 1
        }
        i = i + 1
    }
    return parseInt(d.getString(`${aLen},${bLen}`))
}

function collectVisibleNames(): string {
    let names = ""
    let s = currentScope
    while (s >= 0) {
        const scopeKey = `${s}`
        if (scopeVarNames.has(scopeKey) == 1) {
            const scopeNames = scopeVarNames.getString(scopeKey)
            names = listAppendStr(names, scopeNames)
        }
        if (s == 0) { break }
        s = parseInt(scopeParent.getString(`${s}`))
    }
    if (allFuncNameList != "") {
        names = listAppendStr(names, allFuncNameList)
    }
    return names
}

function findSuggestion(name: string): string {
    const candidates = collectVisibleNames()
    if (candidates == "") { return "" }
    const parts = candidates.split(",")
    let bestName = ""
    let bestDist = 999
    for (c in parts) {
        if (c == "" || c == name) { continue }
        let maxLen = name.length()
        if (c.length() > maxLen) { maxLen = c.length() }
        let threshold = maxLen / 3
        if (threshold < 1) { threshold = 1 }
        // Skip candidates where length difference alone exceeds threshold
        let lenDiff = name.length() - c.length()
        if (lenDiff < 0) { lenDiff = 0 - lenDiff }
        if (lenDiff > threshold) { continue }
        const dist = editDistance(name, c)
        if (dist <= threshold && dist < bestDist) {
            bestDist = dist
            bestName = c
        }
    }
    return bestName
}
