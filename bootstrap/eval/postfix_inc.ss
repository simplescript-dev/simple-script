// POSTFIX_INC 子目录文件(原 eval_expr.ss 迁出)
// 对称三段式:comptime ctScopeStack/ctVars 自增 + return old;runtime genPostfixExpr

function evalPostfixInc(astId: int): int {
    if (comptimeMustBeKnown == 1) {
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
        // D171 Phase 5 loud-gate (D088 §Phase 8):未绑定/非 ct 变量上的 `x++` 不静默返 null
        // (probe PG2 `undefinedVarX++` 旧路径静默吞 exit 0),改 loud comptimeError exit(1)。
        return comptimeError(`postfix '++' on '${piName}' not compile-time known`, astId)
    }
    return 0 - constVal(genPostfixExpr(astId)) - 1
}
