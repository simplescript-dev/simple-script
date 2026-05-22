// IDENT 子目录文件(原 eval_expr.ss 迁出)
// 对称三段式:ctScopeStack lookup → ctVars(currentFunc) → comptime interpVars/class/泛型/alias → runtime genIdent

function evalIdent(astId: int): int {
    const ctIdName = nGetS1(astId)
    if (comptimeMustBeKnown == 1 && ctScopeStack.length() > 0) {
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
    // D112: 全局 type alias fallback(`const T = comptime{...}` 仅 type ctVal 有效,防污染 int/string runtime)
    const ctGlobalVal = ctLookupTypeVal(ctIdName)
    if (ctGlobalVal != 0) { return ctGlobalVal }
    // D128 + I021-codegen-fix: ctVars `:${name}` fallback 接任意 isCt(防 const 字面量在
    // comptime 块内引用 fallback genIdent 喷 `load` 到顶层;type ct 由 ctLookupTypeVal 优先拦截)
    const ctGlobalKey = `:${ctIdName}`
    if (ctVars.has(ctGlobalKey) == 1) {
        const ctGlobalCt = parseInt(ctVars.getString(ctGlobalKey))
        if (isCt(ctGlobalCt) == 1) { return ctGlobalCt }
    }
    if (comptimeMustBeKnown == 1) {
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
    }
    return 0 - constVal(genIdent(astId)) - 1
}
