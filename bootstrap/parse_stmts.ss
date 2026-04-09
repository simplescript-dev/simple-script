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
            pExpect("THIN_ARROW")
            const bodyId = parseSwitchBody()
            const caseId = newNode("SWITCH_CASE")
            nSetI1(caseId, patId)
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
            const id = newNode("INDEX_ASSIGN")
            nSetLine(id, startLine)
            nSetCol(id, startCol)
            nSetS1(id, name)
            nSetI1(id, indexId)
            nSetI2(id, valId)
            return id
        }
        // Not assignment, expression stmt
        const objExpr = newNode("IDENT")
        nSetS1(objExpr, name)
        const accessId = newNode("INDEX_ACCESS")
        nSetI1(accessId, objExpr)
        nSetI2(accessId, indexId)
        expectNLOrRB()
        const stmtId = newNode("EXPR_STMT")
        nSetI1(stmtId, accessId)
        return stmtId
    }
    // Simple assignment: x = expr
    if (nextTok == "ASSIGN") {
        pAdvance()
        pAdvance()
        const valId = parseExpr()
        expectNLOrRB()
        const id = newNode("ASSIGN")
        nSetLine(id, startLine)
        nSetCol(id, startCol)
        nSetS1(id, name)
        nSetS2(id, "ASSIGN")
        nSetI1(id, valId)
        return id
    }
    // Compound assignment: x += expr
    if (nextTok == "PLUS_ASSIGN" || nextTok == "MINUS_ASSIGN" || nextTok == "STAR_ASSIGN" || nextTok == "SLASH_ASSIGN" || nextTok == "PERCENT_ASSIGN" || nextTok == "POWER_ASSIGN") {
        pAdvance()
        const op = curKind()
        pAdvance()
        const valId = parseExpr()
        expectNLOrRB()
        const id = newNode("ASSIGN")
        nSetLine(id, startLine)
        nSetCol(id, startCol)
        nSetS1(id, name)
        nSetS2(id, op)
        nSetI1(id, valId)
        return id
    }
    if (nextTok == "PLUS_PLUS" || nextTok == "MINUS_MINUS") {
        let pfKind = "POSTFIX_DEC"
        if (nextTok == "PLUS_PLUS") { pfKind = "POSTFIX_INC" }
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
    // Expression statement — or member assignment (obj.field = value)
    const exprId = parseExpr()
    const ck = curKind()
    if (nGetKind(exprId) == "MEMBER_ACCESS" && (ck == "ASSIGN" || ck == "PLUS_ASSIGN" || ck == "MINUS_ASSIGN" || ck == "STAR_ASSIGN" || ck == "SLASH_ASSIGN" || ck == "PERCENT_ASSIGN" || ck == "POWER_ASSIGN")) {
        let mOp = "ASSIGN"
        if (ck != "ASSIGN") { mOp = ck }
        pAdvance()
        const mVal = parseExpr()
        expectNLOrRB()
        const mId = newNode("MEMBER_ASSIGN")
        nSetLine(mId, startLine)
        nSetCol(mId, startCol)
        nSetI1(mId, nGetI1(exprId))
        nSetS1(mId, nGetS1(exprId))
        nSetS2(mId, mOp)
        nSetI2(mId, mVal)
        return mId
    }
    expectNLOrRB()
    const id = newNode("EXPR_STMT")
    nSetI1(id, exprId)
    return id
}
