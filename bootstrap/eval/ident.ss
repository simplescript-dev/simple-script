// D108 §步骤 1: IDENT 迁出 eval_expr.ss 独立子目录文件
// 对称三段式:ctScopeStack lookup → ctVars(currentFunc) → comptime interpVars/class/泛型/alias → runtime genIdent

function evalIdent(astId: int): int {
    const ctIdName = nGetS1(astId)
    if (comptimeDepth > 0 && ctScopeStack.length() > 0) {
        let ctSi = ctScopeStack.length() - 1
        while (ctSi >= 0) {
            const ctScopeKey = `${ctScopeStack[ctSi]}:${ctIdName}`
            if (ctVars.has(ctScopeKey) == 1) {
                return parseInt(ctVars.getString(ctScopeKey))
            }
            ctSi = ctSi - 1
        }
    }
    const ctKey = `${currentFunc}:${ctIdName}`
    if (ctVars.has(ctKey) == 1 && ctInvalidated.has(ctKey) == 0) {
        const ctIdVal = parseInt(ctVars.getString(ctKey))
        if (isCt(ctIdVal) == 1) { return ctIdVal }
    }
    if (comptimeDepth > 0) {
        const ctInterpKey = interpFindScopeKey(ctIdName)
        if (ctInterpKey != "") {
            return ctVal(parseInt(interpVars.getString(ctInterpKey)))
        }
        // class 名 in comptime → TypeValue(已注册的 user/interp class,或 const T = comptime{...} alias)
        if (isKnownClass(ctIdName) == 1) {
            return ctVal(interpNewType(ctIdName))
        }
        // 泛型实参 T 绑定的类名 → TypeValue(monomorphize 时 genericTypeSubs[T]=Foo);
        // 支持 comptime 内 T.name / T.fields / `return T`。
        if (genericTypeSubs.has(ctIdName) == 1) {
            const ctSubName = genericTypeSubs.getString(ctIdName)
            if (isKnownClass(ctSubName) == 1) {
                return ctVal(interpNewType(ctSubName))
            }
        }
        const ctAliased = resolveCtTypeAlias(ctIdName)
        if (ctAliased != ctIdName) {
            return ctVal(interpNewType(ctAliased))
        }
    }
    return 0 - constVal(genIdent(astId)) - 1
}
