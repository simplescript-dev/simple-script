// Perceus IR — AST → PIR lowering + expression scanning
// Translates AST statements into PIR instruction sequences for RC analysis.
// No own imports — relies on textual inlining to access gen_pir.ss globals
// and AST accessor functions.

// ── PIR lowering: AST → PIR instruction list ─────────────────────

function pirRegisterParams(paramList: string) {
    if (paramList == "") { return }
    const parts = paramList.split(",")
    for (p in parts) {
        const pid = parseInt(p)
        if (pid <= 0 || nGetKind(pid) != "PARAM") { continue }
        pirSetType(nGetS1(pid), nGetS2(pid))
    }
}

function pirLowerBlock(blockId: int, buf: string): string {
    if (blockId <= 0) { return buf }
    const sl = nGetList(blockId)
    if (sl == "") { return buf }
    const parts = sl.split(",")
    for (p in parts) {
        const sid = parseInt(p)
        if (sid > 0) { buf = pirLowerStmt(sid, buf) }
    }
    return buf
}

function pirLowerStmt(id: int, buf: string): string {
    const kind = nGetKind(id)
    if (kind == "VAR_DECL") { return pirLowerVarDecl(id, buf) }
    if (kind == "ASSIGN") { return pirLowerAssign(id, buf) }
    if (kind == "MEMBER_ASSIGN") { return pirLowerFieldSet(id, buf) }
    if (kind == "RETURN") { return pirLowerReturn(id, buf) }
    if (kind == "EXPR_STMT") { return pirLowerExprStmt(id, buf) }
    if (kind == "IF") {
        buf = pirEmitExprUses(nGetI1(id), id, buf)
        buf = pirLowerBlock(nGetI2(id), buf)
        if (nGetI3(id) > 0) { buf = pirLowerBlock(nGetI3(id), buf) }
        return buf
    }
    if (kind == "FOR") {
        buf = pirEmitExprUses(nGetI2(id), id, buf)
        return pirLowerBlock(nGetI4(id), buf)
    }
    if (kind == "FOR_IN" || kind == "FOR_OF") {
        buf = pirEmitExprUses(nGetI1(id), id, buf)
        return pirLowerBlock(nGetI2(id), buf)
    }
    if (kind == "WHILE") {
        buf = pirEmitExprUses(nGetI1(id), id, buf)
        return pirLowerBlock(nGetI2(id), buf)
    }
    if (kind == "DO_WHILE") {
        buf = pirLowerBlock(nGetI1(id), buf)
        buf = pirEmitExprUses(nGetI2(id), id, buf)
        return buf
    }
    if (kind == "DESTRUCTURE_ARRAY" || kind == "DESTRUCTURE_OBJECT") {
        buf = pirEmitExprUses(nGetI1(id), id, buf)
        return buf
    }
    return buf
}

function pirEmitExprUses(exprId: int, stmtId: int, buf: string): string {
    if (exprId <= 0) { return buf }
    const uses = pirCollectUses(exprId)
    if (uses == "") { return buf }
    const useParts = uses.split(",")
    for (u in useParts) {
        if (u == "") { continue }
        const pir = newPir("USE")
        pirSetS1(pir, u)
        pirSetI1(pir, stmtId)
        buf = pirAppend(buf, pir)
    }
    return buf
}

function pirLowerVarDecl(id: int, buf: string): string {
    const name = nGetS1(id)
    const initId = nGetI1(id)
    const typeAnn = nGetS3(id)

    let ssType = typeAnn
    if (ssType == "" && initId > 0) {
        ssType = inferType(initId)
        // inferType returns "int" default for IDENT when varTypes not populated;
        // fall back to PIR-local type tracking
        if (nGetKind(initId) == "IDENT" && (ssType == "int" || ssType == "")) {
            const src = pirGetType(nGetS1(initId))
            if (src != "") { ssType = src }
        }
    }
    pirSetType(name, ssType)

    if (initId <= 0) { return buf }

    // Class-typed variable: emit PIR class instructions
    if (pirIsClass(ssType) == 1) {
        pirFuncClassVars = listAppendStr(pirFuncClassVars, name)
        const initKind = nGetKind(initId)
        if (initKind == "NEW_EXPR") {
            const pir = newPir("ALLOC")
            pirSetS1(pir, name)
            pirSetS2(pir, ssType)
            pirSetI1(pir, id)
            buf = pirAppend(buf, pir)
            // Scan constructor args for class var uses
            return pirEmitExprUses(initId, id, buf)
        }
        if (initKind == "IDENT") {
            const pir = newPir("RC_INC")
            pirSetS1(pir, nGetS1(initId))
            pirSetS2(pir, name)
            pirSetI1(pir, id)
            return pirAppend(buf, pir)
        }
        if (initKind == "CALL" || initKind == "METHOD_CALL") {
            const pir = newPir("CALL")
            pirSetS1(pir, nGetS1(initId))
            pirSetS2(pir, name)
            pirSetI1(pir, id)
            buf = pirAppend(buf, pir)
            // Scan call args for class var uses
            return pirEmitExprUses(initId, id, buf)
        }
        return buf
    }

    // Non-class variable: still scan init expr for class var uses
    return pirEmitExprUses(initId, id, buf)
}

function pirLowerAssign(id: int, buf: string): string {
    const name = nGetS1(id)
    const ssType = pirGetType(name)
    if (pirIsClass(ssType) == 0) { return buf }

    // Reassign: RC_DEC old value
    const decPir = newPir("RC_DEC")
    pirSetS1(decPir, name)
    pirSetS2(decPir, ssType)
    pirSetI1(decPir, id)
    buf = pirAppend(buf, decPir)

    // RC_INC new value if borrowed (IDENT), owned (NEW_EXPR/CALL) needs no inc
    const valId = nGetI1(id)
    if (nGetKind(valId) == "IDENT") {
        const incPir = newPir("RC_INC")
        pirSetS1(incPir, nGetS1(valId))
        pirSetS2(incPir, name)
        pirSetI1(incPir, id)
        buf = pirAppend(buf, incPir)
    }
    return buf
}

function pirLowerFieldSet(id: int, buf: string): string {
    const objVar = pirExtractRootVar(nGetI1(id))
    if (objVar == "" || pirIsClass(pirGetType(objVar)) == 0) { return buf }
    const pir = newPir("FIELD_SET")
    pirSetS1(pir, objVar)
    pirSetS2(pir, nGetS1(id))
    pirSetI1(pir, id)
    return pirAppend(buf, pir)
}

function pirLowerReturn(id: int, buf: string): string {
    const valId = nGetI1(id)
    if (valId <= 0) { return buf }
    if (nGetKind(valId) == "IDENT") {
        const name = nGetS1(valId)
        if (pirIsClass(pirGetType(name)) == 1) {
            const pir = newPir("MOVE")
            pirSetS1(pir, name)
            pirSetS2(pir, "__return__")
            pirSetI1(pir, id)
            return pirAppend(buf, pir)
        }
    }
    // Non-class return: scan expression for class var uses
    return pirEmitExprUses(valId, id, buf)
}

function pirLowerExprStmt(id: int, buf: string): string {
    return pirEmitExprUses(nGetI1(id), id, buf)
}

// ── Expression scanning ──────────────────────────────────────────

function pirExtractRootVar(exprId: int): string {
    if (exprId <= 0) { return "" }
    const kind = nGetKind(exprId)
    if (kind == "IDENT") { return nGetS1(exprId) }
    if (kind == "MEMBER_ACCESS") { return pirExtractRootVar(nGetI1(exprId)) }
    if (kind == "THIS") { return "this" }
    return ""
}

// Collect unique class variable names referenced in an expression
let pirUseAccum = ""

function pirCollectUses(exprId: int): string {
    pirUseAccum = ""
    pirCollectUsesRec(exprId)
    return pirUseAccum
}

function pirAddUse(name: string) {
    if (pirUseAccum == "") { pirUseAccum = name; return }
    const parts = pirUseAccum.split(",")
    for (p in parts) {
        if (p == name) { return }
    }
    pirUseAccum = `${pirUseAccum},${name}`
}

function pirCollectUsesRec(exprId: int) {
    if (exprId <= 0) { return }
    const kind = nGetKind(exprId)
    if (kind == "IDENT") {
        const name = nGetS1(exprId)
        if (pirIsClass(pirGetType(name)) == 1) { pirAddUse(name) }
        return
    }
    if (kind == "METHOD_CALL") {
        pirCollectUsesRec(nGetI1(exprId))
        pirCollectUsesArgs(nGetList(exprId))
        return
    }
    if (kind == "CALL") {
        pirCollectUsesArgs(nGetList(exprId))
        return
    }
    if (kind == "MEMBER_ACCESS") {
        pirCollectUsesRec(nGetI1(exprId))
        return
    }
    if (kind == "BINARY") {
        pirCollectUsesRec(nGetI1(exprId))
        pirCollectUsesRec(nGetI2(exprId))
        return
    }
    if (kind == "UNARY" || kind == "GROUPING") {
        pirCollectUsesRec(nGetI1(exprId))
        return
    }
    if (kind == "TERNARY") {
        pirCollectUsesRec(nGetI1(exprId))
        pirCollectUsesRec(nGetI2(exprId))
        pirCollectUsesRec(nGetI3(exprId))
        return
    }
    if (kind == "NEW_EXPR") {
        pirCollectUsesArgs(nGetList(exprId))
        return
    }
    if (kind == "TEMPLATE_LIT") {
        pirCollectUsesArgs(nGetList(exprId))
        return
    }
    if (kind == "INDEX_ACCESS") {
        pirCollectUsesRec(nGetI1(exprId))
        pirCollectUsesRec(nGetI2(exprId))
        return
    }
    if (kind == "NAMED_ARG") {
        pirCollectUsesRec(nGetI1(exprId))
        return
    }
}

function pirCollectUsesArgs(argList: string) {
    if (argList == "") { return }
    const parts = argList.split(",")
    for (a in parts) {
        const aId = parseInt(a)
        if (aId > 0) { pirCollectUsesRec(aId) }
    }
}
