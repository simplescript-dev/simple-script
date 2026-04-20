// D108 §步骤 1: POSTFIX_INC 迁子目录(原迁出 D106)
// 对称三段式:comptime ctScopeStack/ctVars 自增 + return old;runtime genPostfixExpr

function evalPostfixInc(astId: int): int {
    if (comptimeDepth > 0) {
        const piName = nGetS1(astId)
        let piKey = ""
        if (ctScopeStack.length() > 0) {
            let piSi = ctScopeStack.length() - 1
            while (piSi >= 0) {
                const piSk = `${ctScopeStack[piSi]}:${piName}`
                if (ctVars.has(piSk) == 1) { piKey = piSk; break }
                piSi = piSi - 1
            }
        }
        if (piKey == "") {
            const piFk = `${currentFunc}:${piName}`
            if (ctVars.has(piFk) == 1) { piKey = piFk }
        }
        if (piKey != "") {
            const piTagged = parseInt(ctVars.getString(piKey))
            if (isCt(piTagged) == 1) {
                const piOld = payload(piTagged)
                ctVars.set(piKey, `${ctVal(interpNewInt(interpAsInt(piOld) + 1))}`)
                return ctVal(piOld)
            }
        }
        return ctVal(interpNewNull())
    }
    return 0 - constVal(genPostfixExpr(astId)) - 1
}
