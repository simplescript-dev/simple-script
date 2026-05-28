// gen/class_comptime.ss — Comptime AST fold 工具:IDENT 绑定查找 / 节点克隆 / string 求值 / ct:type 解析

// Look up an IDENT name in the outer comptime scope (ctScopeStack → ctVars
// → interpVars), mirroring genVal's IDENT path but without IR side effects.
// Returns tagged ctVal if bound to a comptime value, -1 otherwise.
function lookupComptimeBinding(name: string): int {
    if (comptimeMustBeKnown == 1 && ctScopeStack.length() > 0) {
        let si = ctScopeStack.length() - 1
        while (si >= 0) {
            const k = `${ctScopeStack[si]}:${name}`
            if (ctVars.has(k) == 1) { return parseInt(ctVars.getString(k)) }
            si = si - 1
        }
    }
    const fk = `${currentFunc}:${name}`
    if (ctVars.has(fk) == 1 && ctInvalidated.has(fk) == 0) {
        const v = parseInt(ctVars.getString(fk))
        if (isCt(v) == 1) { return v }
    }
    if (comptimeMustBeKnown == 1) {
        const ik = interpFindScopeKey(name)
        if (ik != "") { return ctVal(parseInt(interpVars.getString(ik))) }
    }
    return -1
}

// Replace an IDENT node in-place with the corresponding LIT for its comptime
// value. Returns 1 if replaced, 0 otherwise.
function rewriteIdentToLit(nodeId: int, tagged: int): int {
    if (isCt(tagged) == 0) { return 0 }
    const pl = payload(tagged)
    const identName = nGetS1(nodeId)
    const vType = getVarType(identName)
    const tkOrig = tvKindByPool(pl)
    const tk = (vType == "string" || vType == "int" || vType == "double" || vType == "bool") ? vType : tkOrig
    if (tk == "string") {
        nKind.set(nodeId + "", "STRING_LIT")
        nSetS1(nodeId, tvStringOf(pl))
        return 1
    }
    if (tk == "int") {
        nKind.set(nodeId + "", "INT_LIT")
        nSetS1(nodeId, `${tvIntOf(pl)}`)
        return 1
    }
    if (tk == "double") {
        nKind.set(nodeId + "", "DOUBLE_LIT")
        nSetS1(nodeId, tvD1.getString(pl + ""))
        return 1
    }
    if (tk == "bool") {
        nKind.set(nodeId + "", tvIntOf(pl) == 1 ? "TRUE_LIT" : "FALSE_LIT")
        return 1
    }
    return 0
}

// Deep-clone an AST subtree. Required because foldComptimeIdentsInTree rewrites
// nodes in place; when the same FUNC_DECL is visited across multiple iterations
// of a handler-level for-in loop (D095 @Getter / @Setter pattern), each iteration
// must operate on its own AST copy so prior folds don't poison later ones.
//
// Slot semantics follow foldComptimeIdentsInTree: I1..I4 may be child node IDs
// (detected via `nGetKind(val) != ""`) OR raw ints; list is CSV of child IDs.
// Strings and line/col metadata are copied verbatim.
function cloneAstNode(id: int): int {
    if (id <= 0) { return 0 }
    const k = nGetKind(id)
    if (k == "") { return 0 }
    const nid = newNode(k)
    nSetS1(nid, nGetS1(id))
    nSetS2(nid, nGetS2(id))
    nSetS3(nid, nGetS3(id))
    nSetLine(nid, nGetLine(id))
    nSetCol(nid, nGetCol(id))
    const i1 = nGetI1(id)
    nSetI1(nid, i1 > 0 && nGetKind(i1) != "" ? cloneAstNode(i1) : i1)
    const i2 = nGetI2(id)
    nSetI2(nid, i2 > 0 && nGetKind(i2) != "" ? cloneAstNode(i2) : i2)
    const i3 = nGetI3(id)
    nSetI3(nid, i3 > 0 && nGetKind(i3) != "" ? cloneAstNode(i3) : i3)
    const i4 = nGetI4(id)
    nSetI4(nid, i4 > 0 && nGetKind(i4) != "" ? cloneAstNode(i4) : i4)
    const list = nGetList(id)
    if (list != "") {
        const parts = list.split(",")
        let newList = ""
        for (p in parts) {
            const childId = parseInt(p)
            const cloned = childId > 0 && nGetKind(childId) != "" ? cloneAstNode(childId) : childId
            newList = newList == "" ? `${cloned}` : `${newList},${cloned}`
        }
        nSetList(nid, newList)
    }
    return nid
}

// Resolve an AST node (after fold) to its compile-time string literal.
// STRING_LIT → its text; TEMPLATE_LIT → concat of fragments where TMPL_FRAG_EXPR
// inner node is recursively resolved (folded IDENTs now appear as STRING_LIT).
// Precondition: foldComptimeIdentsInTree has run, so IDENT / MEMBER_ACCESS
// bindings have been rewritten to literals — no branch needed for them here.
function resolveComptimeString(id: int): string {
    if (id <= 0) { return "" }
    const k = nGetKind(id)
    if (k == "STRING_LIT") { return nGetS1(id) }
    if (k == "TEMPLATE_LIT") {
        const list = nGetList(id)
        if (list == "") { return "" }
        let s = ""
        const parts = list.split(",")
        for (p in parts) {
            const fragId = parseInt(p)
            const fk = nGetKind(fragId)
            if (fk == "TMPL_FRAG_LIT") {
                s = s + nGetS1(fragId)
            } else if (fk == "TMPL_FRAG_EXPR") {
                s = s + resolveComptimeString(nGetI1(fragId))
            }
        }
        return s
    }
    return ""
}

// In-place AST rewrite: walk tree, fold every IDENT whose name resolves to
// a comptime value in the outer handler's scope. Recurses through I1..I4 and
// the list slot. Non-node ints are filtered by nGetKind == "" check.
// D117 Execute 4 — IDENT 绑定 Meta object 时 rewriteIdentToLit 无法 fold
// (kind=object),需在 MEMBER_ACCESS 层 interpGetField 取 scalar field 重写。
// 失败(field 非 scalar,如 FieldMeta.annotations array)则 fall-through,交由
// ct-probe 路径处理。
function foldComptimeIdentsInTree(rootId: int) {
    if (rootId <= 0) { return }
    const k = nGetKind(rootId)
    if (k == "") { return }
    if (k == "IDENT") {
        const name = nGetS1(rootId)
        const tagged = lookupComptimeBinding(name)
        if (tagged > 0) { rewriteIdentToLit(rootId, tagged) }
        return
    }
    if (k == "MEMBER_ACCESS") {
        const mo = nGetI1(rootId)
        if (nGetKind(mo) == "IDENT") {
            const mt = lookupComptimeBinding(nGetS1(mo))
            if (interpType(payload(mt)) == "object" && rewriteIdentToLit(rootId, ctVal(interpGetField(payload(mt), nGetS1(rootId)))) == 1) { return }
        }
    }
    foldComptimeIdentsInTree(nGetI1(rootId))
    foldComptimeIdentsInTree(nGetI2(rootId))
    foldComptimeIdentsInTree(nGetI3(rootId))
    foldComptimeIdentsInTree(nGetI4(rootId))
    const list = nGetList(rootId)
    if (list != "") {
        const parts = list.split(",")
        for (p in parts) { foldComptimeIdentsInTree(parseInt(p)) }
    }
}

// Evaluate a `ct:<exprId>` encoded type to its string. Errors point at the
// expr's source node so users see line:col, not just the slot description.
function resolveCtType(encoded: string, slotDesc: string): string {
    const exprId = parseInt(encoded.substring(3, encoded.length() - 3))
    const tagged = genVal(exprId)
    if (isCt(tagged) == 0) {
        comptimeError(`type interpolation must resolve at comptime (${slotDesc})`, exprId)
    }
    const typeName = interpAsStr(payload(tagged))
    if (typeName == "") {
        comptimeError(`type interpolation yielded empty string (${slotDesc})`, exprId)
    }
    return typeName
}

// Resolve `ct:<exprId>` encoded types (from type-position `${expr}` syntax) on
// each PARAM's S2 and the FUNC_DECL's own retType (S2). Runs after the body
// fold so exprs can reference folded comptime consts (e.g. `v: ${f.type}`).
function foldCtTypesInFuncDecl(funcId: int) {
    const paramList = funcParams(funcId)
    if (paramList != "") {
        const parts = paramList.split(",")
        for (p in parts) {
            const pId = parseInt(p)
            if (pId <= 0 || nGetKind(pId) != "PARAM") { continue }
            const t = paramType(pId)
            if (t.startsWith("ct:") == 1) {
                nSetS2(pId, resolveCtType(t, `param '${paramName(pId)}'`))
            }
        }
    }
    const retT = funcRetType(funcId)
    if (retT.startsWith("ct:") == 1) {
        nSetS2(funcId, resolveCtType(retT, `func '${funcName(funcId)}' return type`))
    }
}
