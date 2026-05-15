// parse_stmts.ss — Statement parsing functions
// Used by parser.ss via textual import. No own imports needed.

// ── Statements ────────────────────────────────────────────────

function parseStmt(): int {
    skipNL()
    const annotations = parseAnnotationList()
    const k = curKind()
    if (k == "FUNCTION" || k == "OVERRIDE") {
        const fId = parseFuncDecl()
        attachAnnotations(fId, annotations)
        return fId
    }
    if (k == "CLASS" || k == "ABSTRACT") {
        let isAbstractClass = 0
        if (k == "ABSTRACT") {
            isAbstractClass = 1
            pAdvance()
        }
        const cId = parseClassDecl()
        if (isAbstractClass == 1) { nSetI1(cId, 1) }
        attachAnnotations(cId, annotations)
        return cId
    }
    if (k == "INTERFACE") { return parseInterfaceDecl() }
    if (k == "ENUM") { return parseEnumDecl() }
    if (k == "SWITCH") { return parseSwitch() }
    if (k == "CONST" || k == "LET") { return parseVarDecl() }
    if (k == "RETURN") { return parseReturn() }
    if (k == "IF") { return parseIf() }
    if (k == "FOR") { return parseFor() }
    if (k == "WHILE") { return parseWhile() }
    if (k == "DO") { return parseDoWhile() }
    if (k == "BREAK") {
        pAdvance()
        expectNLOrRB()
        return newNode("BREAK")
    }
    if (k == "CONTINUE") {
        pAdvance()
        expectNLOrRB()
        return newNode("CONTINUE")
    }
    if (k == "TRY") { return parseTryCatch() }
    if (k == "THROW") { return parseThrow() }
    if (k == "COMPTIME") { return parseComptime() }
    if (k == "IMPORT") { return parseImport() }
    if (k == "IDENT" || k == "THIS") { return parseAssignOrExpr() }
    // Fallback: expression statement
    const exprId = parseExpr()
    expectNLOrRB()
    const id = newNode("EXPR_STMT")
    nSetI1(id, exprId)
    return id
}

// try { ... } catch (e) { ... } catch (e: Type) { ... } finally { ... }
function parseTryCatch(): int {
    pExpect("TRY")
    const tryBody = parseBlock()
    skipNL()
    // Parse catch clauses (multiple allowed)
    let catchClauses = ""
    while (curKind() == "CATCH") {
        pAdvance()
        pExpect("LPAREN")
        const errName = pExpectIdent()
        let errType = ""
        if (curKind() == "COLON") {
            pAdvance()
            errType = parseTypeAnn()
        }
        pExpect("RPAREN")
        const catchBody = parseBlock()
        skipNL()
        const clause = newNode("CATCH_CLAUSE")
        nSetS1(clause, errName)
        nSetS2(clause, errType)
        nSetI1(clause, catchBody)
        catchClauses = listAppend(catchClauses, clause)
    }
    let finallyBody = 0
    if (curKind() == "FINALLY") {
        pAdvance()
        finallyBody = parseBlock()
    }
    const id = newNode("TRY")
    nSetI1(id, tryBody)
    nSetI3(id, finallyBody)
    nSetList(id, catchClauses)
    return id
}

// throw("message") or throw(expr)
function parseThrow(): int {
    pExpect("THROW")
    pExpect("LPAREN")
    const msgId = parseExpr()
    pExpect("RPAREN")
    const id = newNode("THROW")
    nSetI1(id, msgId)
    return id
}

// comptime { ... } — compile-time execution block (D087)
function parseComptime(): int {
    pExpect("COMPTIME")
    const body = parseBlock()
    const id = newNode("COMPTIME_BLOCK")
    nSetI1(id, body)
    return id
}

function parseSwitch(): int {
    pExpect("SWITCH")
    pExpect("LPAREN")
    const subjectId = parseExpr()
    pExpect("RPAREN")
    skipNL()
    pExpect("LBRACE")
    skipNL()
    let cases = ""
    let defaultId = 0
    while (curKind() != "RBRACE" && curKind() != "EOF") {
        if (curKind() == "DEFAULT") {
            pAdvance()
            pExpect("THIN_ARROW")
            defaultId = parseSwitchBody()
        } else {
            pExpect("CASE")
            let patIds = parseSwitchPat() + ""
            while (curKind() == "COMMA") {
                pAdvance()
                patIds = listAppend(patIds, parseSwitchPat())
            }
            pExpect("THIN_ARROW")
            const bodyId = parseSwitchBody()
            const caseId = newNode("SWITCH_CASE")
            nSetList(caseId, patIds)
            nSetI2(caseId, bodyId)
            cases = listAppend(cases, caseId)
        }
        skipNL()
    }
    pExpect("RBRACE")
    const id = newNode("SWITCH")
    nSetI1(id, subjectId)
    nSetI2(id, defaultId)
    nSetList(id, cases)
    return id
}

function parseSwitchPat(): int {
    const patId = newNode("SWITCH_PAT")
    let patKind = "IDENT"
    let patValue = ""
    if (curKind() == "INT") { patKind = "INT"; patValue = curValue(); pAdvance() }
    else if (curKind() == "STRING") { patKind = "STRING"; patValue = curValue(); pAdvance() }
    else if (curKind() == "TRUE") { patKind = "BOOL"; patValue = "1"; pAdvance() }
    else if (curKind() == "FALSE") { patKind = "BOOL"; patValue = "0"; pAdvance() }
    else if (curKind() == "IDENT") {
        const name = curValue(); pAdvance()
        if (curKind() == "DOT") {
            pAdvance()
            const member = curValue(); pExpect("IDENT")
            patKind = "ENUM"; patValue = `${name}.${member}`
        } else {
            patValue = name
        }
    } else { patValue = curValue(); pAdvance() }
    nSetS1(patId, patKind)
    nSetS2(patId, patValue)
    return patId
}

function parseSwitchBody(): int {
    if (curKind() == "LBRACE") { return parseBlock() }
    const stmtId = parseStmt()
    const blockId = newNode("BLOCK")
    nSetList(blockId, stmtId + "")
    return blockId
}

function parseVarDeclCore(): int {
    const startLine = curLineNum()
    const startCol = curColNum()
    const varKind = curKind()
    pAdvance()
    // Array destructuring: const [a, b, c] = expr  /  const [a, ...rest] = expr
    if (curKind() == "LBRACKET") {
        pAdvance()
        let names = ""
        while (curKind() != "RBRACKET" && curKind() != "EOF") {
            if (curKind() == "SPREAD") {
                pAdvance()
                const n = pExpectIdent()
                names = listAppendStr(names, `...${n}`)
                if (curKind() == "COMMA") {
                    println(`parse error at line ${curLineNum()}: rest element must be last`)
                    exit(1)
                }
            } else {
                const n = pExpectIdent()
                names = listAppendStr(names, n)
                if (curKind() == "COMMA") { pAdvance() }
            }
        }
        pExpect("RBRACKET")
        pExpect("ASSIGN")
        const initId = parseExpr()
        const id = newNode("DESTRUCTURE_ARRAY")
        nSetLine(id, startLine)
        nSetCol(id, startCol)
        nSetS1(id, names)
        nSetS2(id, varKind)
        nSetI1(id, initId)
        return id
    }
    // Object destructuring: const { x, y } = expr  /  const { x: alias } = expr
    if (curKind() == "LBRACE") {
        pAdvance()
        let names = ""
        while (curKind() != "RBRACE" && curKind() != "EOF") {
            const n = pExpectIdent()
            if (curKind() == "COLON") {
                pAdvance()
                const alias = pExpectIdent()
                names = listAppendStr(names, `${n}:${alias}`)
            } else {
                names = listAppendStr(names, n)
            }
            if (curKind() == "COMMA") { pAdvance() }
        }
        pExpect("RBRACE")
        pExpect("ASSIGN")
        const initId = parseExpr()
        const id = newNode("DESTRUCTURE_OBJECT")
        nSetLine(id, startLine)
        nSetCol(id, startCol)
        nSetS1(id, names)
        nSetS2(id, varKind)
        nSetI1(id, initId)
        return id
    }
    const name = pExpectIdent()
    let typeAnn = ""
    if (curKind() == "COLON") { pAdvance(); typeAnn = parseTypeAnn() }
    pExpect("ASSIGN")
    const initId = parseExpr()
    const id = newNode("VAR_DECL")
    nSetLine(id, startLine)
    nSetCol(id, startCol)
    nSetS1(id, name)
    nSetS2(id, varKind)
    nSetS3(id, typeAnn)
    nSetI1(id, initId)
    return id
}

function parseVarDecl(): int {
    const id = parseVarDeclCore()
    expectNLOrRB()
    return id
}

function parseVarDeclNoNL(): int {
    return parseVarDeclCore()
}

function parseReturn(): int {
    pAdvance()
    const k = curKind()
    let valId = 0
    if (k != "NEWLINE" && k != "RBRACE" && k != "EOF") {
        valId = parseExpr()
    }
    expectNLOrRB()
    const id = newNode("RETURN")
    nSetI1(id, valId)
    return id
}

function parseIf(): int {
    pExpect("IF")
    pExpect("LPAREN")
    const condId = parseExpr()
    pExpect("RPAREN")
    skipNL()
    const thenId = parseBlock()
    skipNL()
    let elseId = 0
    if (curKind() == "ELSE") {
        pAdvance()
        skipNL()
        if (curKind() == "IF") {
            // else if -> wrap in block
            const elseIfId = parseIf()
            const blockId = newNode("BLOCK")
            nSetList(blockId, elseIfId + "")
            elseId = blockId
        } else {
            elseId = parseBlock()
        }
    }
    const id = newNode("IF")
    nSetI1(id, condId)
    nSetI2(id, thenId)
    nSetI3(id, elseId)
    return id
}

function parseFor(): int {
    pExpect("FOR")
    pExpect("LPAREN")
    // Check for for-in / for-of: for (item in expr), for (item of expr)
    if (curKind() == "IDENT") {
        const savedPos = tPos
        const itemName = curValue()
        pAdvance()
        if (curKind() == "IN") {
            pAdvance()
            const iterableId = parseExpr()
            pExpect("RPAREN")
            skipNL()
            const bodyId = parseBlock()
            const id = newNode("FOR_IN")
            nSetS1(id, itemName)
            nSetI1(id, iterableId)
            nSetI2(id, bodyId)
            return id
        }
        if (curKind() == "IDENT" && curValue() == "of") {
            pAdvance()
            const iterableId = parseExpr()
            pExpect("RPAREN")
            skipNL()
            const bodyId = parseBlock()
            const id = newNode("FOR_OF")
            nSetS1(id, itemName)
            nSetI1(id, iterableId)
            nSetI2(id, bodyId)
            return id
        }
        tPos = savedPos
    }
    // Check for for-of with const/let: for (const x of expr), for (let x of expr)
    if (curKind() == "CONST" || curKind() == "LET") {
        const savedPos2 = tPos
        pAdvance()
        if (curKind() == "IDENT") {
            const itemName2 = curValue()
            pAdvance()
            if (curKind() == "IDENT" && curValue() == "of") {
                pAdvance()
                const iterableId2 = parseExpr()
                pExpect("RPAREN")
                skipNL()
                const bodyId2 = parseBlock()
                const id2 = newNode("FOR_OF")
                nSetS1(id2, itemName2)
                nSetI1(id2, iterableId2)
                nSetI2(id2, bodyId2)
                return id2
            }
        }
        tPos = savedPos2
    }
    // C-style for
    const initId = parseVarDeclNoNL()
    pExpect("SEMICOLON")
    const condId = parseExpr()
    pExpect("SEMICOLON")
    const updateId = parseUpdateStmt()
    pExpect("RPAREN")
    skipNL()
    const bodyId = parseBlock()
    const id = newNode("FOR")
    nSetI1(id, initId)
    nSetI2(id, condId)
    nSetI3(id, updateId)
    nSetI4(id, bodyId)
    return id
}

function parseUpdateStmt(): int {
    const startLine = curLineNum()
    const startCol = curColNum()
    const name = pExpectIdent()
    const k = curKind()
    if (k == "PLUS_PLUS") {
        pAdvance()
        const id = newNode("POSTFIX_INC")
        nSetLine(id, startLine)
        nSetCol(id, startCol)
        nSetS1(id, name)
        return id
    }
    if (k == "MINUS_MINUS") {
        pAdvance()
        const id = newNode("POSTFIX_DEC")
        nSetLine(id, startLine)
        nSetCol(id, startCol)
        nSetS1(id, name)
        return id
    }
    // Assignment operators
    let op = k
    pAdvance()
    const valId = parseExpr()
    const id = newNode("ASSIGN")
    nSetLine(id, startLine)
    nSetCol(id, startCol)
    nSetS1(id, name)
    nSetS2(id, op)
    nSetI1(id, valId)
    return id
}

function parseWhile(): int {
    pExpect("WHILE")
    pExpect("LPAREN")
    const condId = parseExpr()
    pExpect("RPAREN")
    skipNL()
    const bodyId = parseBlock()
    const id = newNode("WHILE")
    nSetI1(id, condId)
    nSetI2(id, bodyId)
    return id
}

function parseDoWhile(): int {
    pExpect("DO")
    skipNL()
    const bodyId = parseBlock()
    skipNL()
    pExpect("WHILE")
    pExpect("LPAREN")
    const condId = parseExpr()
    pExpect("RPAREN")
    expectNLOrRB()
    const id = newNode("DO_WHILE")
    nSetI1(id, bodyId)
    nSetI2(id, condId)
    return id
}

function parseBlock(): int {
    pExpect("LBRACE")
    skipNL()
    let stmts = ""
    while (curKind() != "RBRACE" && curKind() != "EOF") {
        const stmtId = parseStmt()
        stmts = listAppend(stmts, stmtId)
        skipNL()
    }
    pExpect("RBRACE")
    const id = newNode("BLOCK")
    nSetList(id, stmts)
    return id
}

// SS-LIM-2: builds INDEX_ASSIGN node — name="" + objExprId>0 = obj-expr form (h.items[0] = v); else var-name form.
function makeIndexAssign(name: string, indexId: int, valId: int, objExprId: int, startLine: int, startCol: int): int {
    const id = newNode("INDEX_ASSIGN")
    nSetLine(id, startLine); nSetCol(id, startCol)
    nSetS1(id, name); nSetI1(id, indexId); nSetI2(id, valId); nSetI3(id, objExprId)
    return id
}

function makeMemberAssign(objId: int, name: string, op: string, valId: int, startLine: int, startCol: int): int {
    const id = newNode("MEMBER_ASSIGN")
    nSetLine(id, startLine); nSetCol(id, startCol)
    nSetI1(id, objId); nSetS1(id, name); nSetS2(id, op); nSetI2(id, valId)
    return id
}

function makeAssignNode(name: string, op: string, valId: int, startLine: int, startCol: int): int {
    const id = newNode("ASSIGN")
    nSetLine(id, startLine); nSetCol(id, startCol)
    nSetS1(id, name); nSetS2(id, op); nSetI1(id, valId)
    return id
}

function parseIndexAssignTail(accessExpr: int, startLine: int, startCol: int): int {
    pAdvance(); const v = parseExpr(); expectNLOrRB()
    return makeIndexAssign("", nGetI2(accessExpr), v, nGetI1(accessExpr), startLine, startCol)
}

function parseAssignOrExpr(): int {
    const startLine = curLineNum()
    const startCol = curColNum()
    const name = curValue()
    // Look ahead
    const nextTok = kindAt(tPos + 1)
    // Index assignment: arr[i] = val
    if (nextTok == "LBRACKET") {
        pAdvance()
        pAdvance()
        const indexId = parseExpr()
        pExpect("RBRACKET")
        if (curKind() == "ASSIGN") {
            pAdvance()
            const valId = parseExpr()
            expectNLOrRB()
            return makeIndexAssign(name, indexId, valId, 0, startLine, startCol)
        }
        // Not assignment — build INDEX_ACCESS and continue postfix chain
        const objExpr = newNode("IDENT")
        nSetLine(objExpr, startLine)
        nSetCol(objExpr, startCol)
        nSetS1(objExpr, name)
        const accessId = newNode("INDEX_ACCESS")
        nSetI1(accessId, objExpr)
        nSetI2(accessId, indexId)
        let expr = accessId
        // Postfix chain: .field, .method(), [i], ?.member
        while (curKind() == "DOT" || curKind() == "LBRACKET" || curKind() == "OPT_CHAIN") {
            if (curKind() == "LBRACKET") {
                pAdvance()
                const idx2 = parseExpr()
                pExpect("RBRACKET")
                const ia2 = newNode("INDEX_ACCESS")
                nSetI1(ia2, expr)
                nSetI2(ia2, idx2)
                expr = ia2
                continue
            }
            const isOpt = curKind() == "OPT_CHAIN" ? 1 : 0
            pAdvance()
            const mem = pExpectIdent()
            if (curKind() == "LPAREN") {
                pAdvance()
                const args = parseArgs(0)
                pExpect("RPAREN")
                const mc = newNode("METHOD_CALL")
                nSetS1(mc, mem)
                nSetI1(mc, expr)
                nSetList(mc, args)
                nSetI3(mc, isOpt)
                expr = mc
            } else {
                const ma = newNode("MEMBER_ACCESS")
                nSetS1(ma, mem)
                nSetI1(ma, expr)
                nSetI3(ma, isOpt)
                expr = ma
            }
        }
        // SS-LIM-2: chain ending in INDEX_ACCESS followed by ASSIGN — arr[i].field[j] = val
        const ck2 = curKind()
        if (nGetKind(expr) == "INDEX_ACCESS" && ck2 == "ASSIGN") {
            return parseIndexAssignTail(expr, startLine, startCol)
        }
        // Member assign: arr[i].field = val
        if (nGetKind(expr) == "MEMBER_ACCESS" && (ck2 == "ASSIGN" || ck2 == "PLUS_ASSIGN" || ck2 == "MINUS_ASSIGN" || ck2 == "STAR_ASSIGN" || ck2 == "SLASH_ASSIGN" || ck2 == "PERCENT_ASSIGN" || ck2 == "POWER_ASSIGN")) {
            const mOp = ck2 == "ASSIGN" ? "ASSIGN" : ck2
            pAdvance()
            const mVal = parseExpr()
            expectNLOrRB()
            return makeMemberAssign(nGetI1(expr), nGetS1(expr), mOp, mVal, startLine, startCol)
        }
        expectNLOrRB()
        const stmtId = newNode("EXPR_STMT")
        nSetI1(stmtId, expr)
        return stmtId
    }
    // Simple assignment: x = expr
    if (nextTok == "ASSIGN") {
        pAdvance(); pAdvance()
        const valId = parseExpr()
        expectNLOrRB()
        return makeAssignNode(name, "ASSIGN", valId, startLine, startCol)
    }
    // Compound assignment: x += expr
    if (nextTok == "PLUS_ASSIGN" || nextTok == "MINUS_ASSIGN" || nextTok == "STAR_ASSIGN" || nextTok == "SLASH_ASSIGN" || nextTok == "PERCENT_ASSIGN" || nextTok == "POWER_ASSIGN") {
        pAdvance()
        const op = curKind()
        pAdvance()
        const valId = parseExpr()
        expectNLOrRB()
        return makeAssignNode(name, op, valId, startLine, startCol)
    }
    if (nextTok == "PLUS_PLUS" || nextTok == "MINUS_MINUS") {
        const pfKind = nextTok == "PLUS_PLUS" ? "POSTFIX_INC" : "POSTFIX_DEC"
        pAdvance()
        pAdvance()
        expectNLOrRB()
        const id = newNode("EXPR_STMT")
        const pfId = newNode(pfKind)
        nSetLine(pfId, startLine)
        nSetCol(pfId, startCol)
        nSetS1(pfId, name)
        nSetI1(id, pfId)
        return id
    }
    // Expression statement — or member assignment (obj.field = value) — or index assignment (obj.field[i] = value)
    const exprId = parseExpr()
    const ck = curKind()
    // SS-LIM-2: obj.field[i] = value — INDEX_ACCESS LHS over arbitrary obj-expr
    if (nGetKind(exprId) == "INDEX_ACCESS" && ck == "ASSIGN") {
        return parseIndexAssignTail(exprId, startLine, startCol)
    }
    if (nGetKind(exprId) == "MEMBER_ACCESS" && (ck == "ASSIGN" || ck == "PLUS_ASSIGN" || ck == "MINUS_ASSIGN" || ck == "STAR_ASSIGN" || ck == "SLASH_ASSIGN" || ck == "PERCENT_ASSIGN" || ck == "POWER_ASSIGN")) {
        const mOp = ck == "ASSIGN" ? "ASSIGN" : ck
        pAdvance()
        const mVal = parseExpr()
        expectNLOrRB()
        return makeMemberAssign(nGetI1(exprId), nGetS1(exprId), mOp, mVal, startLine, startCol)
    }
    expectNLOrRB()
    const id = newNode("EXPR_STMT")
    nSetI1(id, exprId)
    return id
}
