// parse_exprs.ss — Expression parsing (precedence climbing)
// Used by parser.ss via textual import. No own imports needed.

// ── Expressions (precedence climbing) ─────────────────────────

function parseExpr(): int {
    const left = parseOr()
    if (curKind() == "QUESTION") {
        pAdvance()
        const thenId = parseExpr()
        pExpect("COLON")
        const elseId = parseExpr()
        const id = newNode("TERNARY")
        nSetI1(id, left)
        nSetI2(id, thenId)
        nSetI3(id, elseId)
        return id
    }
    return left
}

function parseOr(): int {
    let left = parseNullish()
    while (curKind() == "OR") {
        pAdvance()
        const right = parseNullish()
        const id = newNode("BINARY"); nSetS1(id, "Or"); nSetI1(id, left); nSetI2(id, right)
        left = id
    }
    return left
}

function parseNullish(): int {
    let left = parseAndExpr()
    while (curKind() == "NULLISH") {
        pAdvance()
        const right = parseAndExpr()
        const id = newNode("BINARY"); nSetS1(id, "NullCoalesce"); nSetI1(id, left); nSetI2(id, right)
        left = id
    }
    return left
}

function parseAndExpr(): int {
    let left = parseBitOr()
    while (curKind() == "AND") {
        pAdvance()
        const right = parseBitOr()
        const id = newNode("BINARY"); nSetS1(id, "And"); nSetI1(id, left); nSetI2(id, right)
        left = id
    }
    return left
}

function parseBitOr(): int {
    let left = parseBitXor()
    while (curKind() == "BIT_OR") {
        pAdvance()
        const right = parseBitXor()
        const id = newNode("BINARY"); nSetS1(id, "BitOr"); nSetI1(id, left); nSetI2(id, right)
        left = id
    }
    return left
}

function parseBitXor(): int {
    let left = parseBitAnd()
    while (curKind() == "BIT_XOR") {
        pAdvance()
        const right = parseBitAnd()
        const id = newNode("BINARY"); nSetS1(id, "BitXor"); nSetI1(id, left); nSetI2(id, right)
        left = id
    }
    return left
}

function parseBitAnd(): int {
    let left = parseEquality()
    while (curKind() == "BIT_AND") {
        pAdvance()
        const right = parseEquality()
        const id = newNode("BINARY"); nSetS1(id, "BitAnd"); nSetI1(id, left); nSetI2(id, right)
        left = id
    }
    return left
}

function parseEquality(): int {
    let left = parseComparison()
    while (curKind() == "EQ" || curKind() == "NE") {
        const op = curKind()
        pAdvance()
        const right = parseComparison()
        const id = newNode("BINARY")
        if (op == "EQ") { nSetS1(id, "Eq") } else { nSetS1(id, "Ne") }
        nSetI1(id, left)
        nSetI2(id, right)
        left = id
    }
    return left
}

function parseComparison(): int {
    let left = parseAdditive()
    while (curKind() == "LT" || curKind() == "GT" || curKind() == "LE" || curKind() == "GE") {
        const op = curKind()
        pAdvance()
        const right = parseAdditive()
        const id = newNode("BINARY")
        if (op == "LT") { nSetS1(id, "Lt") } else if (op == "GT") { nSetS1(id, "Gt") } else if (op == "LE") { nSetS1(id, "Le") } else { nSetS1(id, "Ge") }
        nSetI1(id, left)
        nSetI2(id, right)
        left = id
    }
    return left
}

function parseAdditive(): int {
    let left = parseShift()
    while (curKind() == "PLUS" || curKind() == "MINUS") {
        const op = curKind()
        pAdvance()
        const right = parseShift()
        const id = newNode("BINARY")
        if (op == "PLUS") { nSetS1(id, "Add") } else { nSetS1(id, "Sub") }
        nSetI1(id, left)
        nSetI2(id, right)
        left = id
    }
    return left
}

function parseShift(): int {
    let left = parseMultiplicative()
    while (curKind() == "SHL" || curKind() == "SHR" || curKind() == "USHR") {
        const op = curKind()
        pAdvance()
        const right = parseMultiplicative()
        const id = newNode("BINARY")
        if (op == "SHL") { nSetS1(id, "Shl") } else if (op == "SHR") { nSetS1(id, "Shr") } else { nSetS1(id, "UShr") }
        nSetI1(id, left)
        nSetI2(id, right)
        left = id
    }
    return left
}

function parseMultiplicative(): int {
    let left = parsePower()
    while (curKind() == "STAR" || curKind() == "SLASH" || curKind() == "PERCENT") {
        const op = curKind()
        pAdvance()
        const right = parsePower()
        const id = newNode("BINARY")
        if (op == "STAR") { nSetS1(id, "Mul") } else if (op == "SLASH") { nSetS1(id, "Div") } else { nSetS1(id, "Mod") }
        nSetI1(id, left)
        nSetI2(id, right)
        left = id
    }
    return left
}

function parsePower(): int {
    let left = parseUnary()
    if (curKind() == "POWER") {
        pAdvance()
        const right = parsePower()
        const id = newNode("BINARY"); nSetS1(id, "Pow"); nSetI1(id, left); nSetI2(id, right)
        left = id
    }
    return left
}

function parseUnary(): int {
    if (curKind() == "MINUS" || curKind() == "NOT" || curKind() == "BIT_NOT") {
        let opName = "Not"
        if (curKind() == "MINUS") { opName = "Neg" }
        if (curKind() == "BIT_NOT") { opName = "BitNot" }
        pAdvance()
        const operandId = parseUnary()
        const id = newNode("UNARY")
        nSetS1(id, opName)
        nSetI1(id, operandId)
        return id
    }
    return parsePrimary()
}

function parsePrimary(): int {
    let expr = parseAtom()
    // Postfix: .member, .method(), [index], ?.member
    // Support multiline chaining: NEWLINE followed by DOT continues the chain
    while (curKind() == "DOT" || curKind() == "LBRACKET" || curKind() == "OPT_CHAIN" || (curKind() == "NEWLINE" && tkKind(tkGet(tokens, tPos + 1)) == "DOT")) {
        if (curKind() == "NEWLINE") { pAdvance() }
        if (curKind() == "LBRACKET") {
            pAdvance()
            const indexId = parseExpr()
            pExpect("RBRACKET")
            const id = newNode("INDEX_ACCESS")
            nSetI1(id, expr)
            nSetI2(id, indexId)
            expr = id
            continue
        }
        // Dot or ?. access
        const isOptional = curKind() == "OPT_CHAIN" ? 1 : 0
        pAdvance()
        const member = pExpectIdent()
        if (curKind() == "LPAREN") {
            pAdvance()
            const argsStr = parseArgs()
            pExpect("RPAREN")
            const id = newNode("METHOD_CALL")
            nSetS1(id, member)
            nSetI1(id, expr)
            nSetList(id, argsStr)
            nSetI3(id, isOptional)
            expr = id
        } else {
            const id = newNode("MEMBER_ACCESS")
            nSetS1(id, member)
            nSetI1(id, expr)
            nSetI3(id, isOptional)
            expr = id
        }
    }
    return expr
}

// Lookahead: is current ( the start of an arrow function?
// Scan forward from ( to find matching ), check if => follows
function isArrowFunc(): int {
    // Quick check: ( must be followed by ) or IDENT
    const nextK = tkKind(tkGet(tokens, tPos + 1))
    if (nextK != "RPAREN" && nextK != "IDENT") { return 0 }
    if (nextK == "IDENT") {
        const afterIdent = tkKind(tkGet(tokens, tPos + 2))
        // Must be param: name COLON type or name RPAREN or name COMMA
        if (afterIdent != "COLON" && afterIdent != "RPAREN" && afterIdent != "COMMA") { return 0 }
    }
    // Scan to matching )
    let lookahead = tPos + 1
    let depth = 1
    while (depth > 0) {
        const lk = tkKind(tkGet(tokens, lookahead))
        if (lk == "LPAREN") { depth = depth + 1 }
        if (lk == "RPAREN") { depth = depth - 1 }
        if (lk == "EOF") { return 0 }
        lookahead = lookahead + 1
    }
    // Token right after ) must be => or : (return type annotation)
    const afterParen = tkKind(tkGet(tokens, lookahead))
    if (afterParen == "ARROW") { return 1 }
    if (afterParen != "COLON") { return 0 }
    // Skip return type to find =>
    let checkPos = lookahead + 1
    // Max 5 tokens for type (e.g. Array < string , int >)
    let maxScan = 0
    while (maxScan < 5) {
        const tk = tkKind(tkGet(tokens, checkPos))
        if (tk == "ARROW") { return 1 }
        if (tk == "EOF" || tk == "LBRACE" || tk == "NEWLINE" || tk == "SEMICOLON") { return 0 }
        checkPos = checkPos + 1
        maxScan = maxScan + 1
    }
    return 0
}

// Parse: (params) => expr  or  (params): Type => expr  or  (params) => { block }
function parseArrowFunc(): int {
    pExpect("LPAREN")
    let params = ""
    while (curKind() != "RPAREN" && curKind() != "EOF") {
        const pId = newNode("PARAM")
        nSetS1(pId, pExpectIdent())
        if (curKind() == "COLON") {
            pAdvance()
            nSetS2(pId, parseTypeAnn())
        }
        params = listAppend(params, pId)
        if (curKind() == "COMMA") { pAdvance() }
    }
    pExpect("RPAREN")
    let retType = ""
    if (curKind() == "COLON") {
        pAdvance()
        retType = parseTypeAnn()
    }
    pExpect("ARROW")
    // Body: either a block { ... } or a single expression
    let bodyId = 0
    if (curKind() == "LBRACE") {
        bodyId = parseBlock()
    } else {
        // Single expression → wrap in implicit return
        const exprId = parseExpr()
        const retNode = newNode("RETURN")
        nSetI1(retNode, exprId)
        const blockId = newNode("BLOCK")
        nSetList(blockId, `${retNode}`)
        bodyId = blockId
    }
    const id = newNode("ARROW_FUNC")
    nSetS2(id, retType)
    nSetList(id, params)
    nSetI1(id, bodyId)
    return id
}

// Lookahead: is current position the start of explicit type args for a generic call?
// Scans from tPos (which should be at LT) without modifying tPos.
// Returns 1 if pattern matches: < type_args > (
function isGenericCallSite(): int {
    let look = tPos + 1
    let depth = 1
    let maxScan = 0
    while (depth > 0) {
        if (maxScan > 30) { return 0 }
        const tk = tkKind(tkGet(tokens, look))
        if (tk == "GT") { depth = depth - 1 }
        else if (tk == "LT") { depth = depth + 1 }
        else if (tk == "EOF") { return 0 }
        else if (tk != "IDENT" && tk != "INT_TYPE" && tk != "DOUBLE_TYPE" && tk != "STRING_TYPE" && tk != "BOOL_TYPE" && tk != "VOID_TYPE" && tk != "COMMA") {
            return 0
        }
        look = look + 1
        maxScan = maxScan + 1
    }
    if (tkKind(tkGet(tokens, look)) == "LPAREN") { return 1 }
    return 0
}

// Parse explicit type argument list: < Type1, Type2, ... >
// Returns comma-separated type string (e.g., "int,string")
function parseTypeArgList(): string {
    pAdvance()
    let typeArgs = parseTypeAnn()
    while (curKind() == "COMMA") {
        pAdvance()
        typeArgs = listAppendStr(typeArgs, parseTypeAnn())
    }
    pExpect("GT")
    return typeArgs
}

function parseAtom(): int {
    const k = curKind()
    const v = curValue()

    if (k == "INT" || k == "DOUBLE" || k == "STRING") {
        pAdvance()
        let nk = "INT_LIT"
        if (k == "DOUBLE") { nk = "DOUBLE_LIT" }
        if (k == "STRING") { nk = "STRING_LIT" }
        const id = newNode(nk)
        nSetS1(id, v)
        return id
    }
    if (k == "TRUE") {
        pAdvance()
        return newNode("TRUE_LIT")
    }
    if (k == "FALSE") {
        pAdvance()
        return newNode("FALSE_LIT")
    }
    if (k == "NULL") {
        pAdvance()
        return newNode("NULL_LIT")
    }
    if (k == "THIS") {
        pAdvance()
        return newNode("THIS")
    }
    if (k == "SUPER") {
        pAdvance()
        return newNode("SUPER")
    }
    if (k == "NEW") {
        pAdvance()
        const className = pExpectIdent()
        let newExplicitTypes = ""
        if (curKind() == "LT") {
            newExplicitTypes = parseTypeArgList()
        }
        pExpect("LPAREN")
        const argsStr = parseArgs()
        pExpect("RPAREN")
        const id = newNode("NEW_EXPR")
        nSetS1(id, className)
        if (newExplicitTypes != "") { nSetS2(id, newExplicitTypes) }
        nSetList(id, argsStr)
        return id
    }
    // Template literal tokens: TMPL_LIT ... TMPL_EXPR_START ... TMPL_EXPR_END ... TMPL_END
    if (k == "TMPL_LIT" || k == "TMPL_EXPR_START") {
        return parseTemplateLit()
    }
    if (k == "IDENT") {
        const identLine = curLineNum()
        const identCol = curColNum()
        const name = v
        pAdvance()
        if (curKind() == "LT" && isGenericCallSite() == 1) {
            const callTypeArgs = parseTypeArgList()
            pExpect("LPAREN")
            const argsStr = parseArgs()
            pExpect("RPAREN")
            const id = newNode("CALL")
            nSetLine(id, identLine)
            nSetCol(id, identCol)
            nSetS1(id, name)
            nSetS2(id, callTypeArgs)
            nSetList(id, argsStr)
            return id
        }
        if (curKind() == "LPAREN") {
            pAdvance()
            const argsStr = parseArgs()
            pExpect("RPAREN")
            const id = newNode("CALL")
            nSetLine(id, identLine)
            nSetCol(id, identCol)
            nSetS1(id, name)
            nSetList(id, argsStr)
            return id
        }
        const id = newNode("IDENT")
        nSetLine(id, identLine)
        nSetCol(id, identCol)
        nSetS1(id, name)
        return id
    }
    if (k == "LPAREN") {
        // Check if this is an arrow function: (...) => expr
        if (isArrowFunc() == 1) {
            return parseArrowFunc()
        }
        pAdvance()
        const exprId = parseExpr()
        pExpect("RPAREN")
        const id = newNode("GROUPING")
        nSetI1(id, exprId)
        return id
    }
    if (k == "LBRACKET") {
        pAdvance()
        skipNL()
        let elems = ""
        if (curKind() != "RBRACKET") {
            while (curKind() != "EOF") {
                skipNL()
                if (curKind() == "SPREAD") {
                    pAdvance()
                    const spreadExpr = parseExpr()
                    const spreadNode = newNode("SPREAD_ELEM")
                    nSetI1(spreadNode, spreadExpr)
                    elems = listAppend(elems, spreadNode)
                } else {
                    const elemId = parseExpr()
                    elems = listAppend(elems, elemId)
                }
                skipNL()
                if (curKind() == "COMMA") { pAdvance() } else { break }
            }
        }
        skipNL()
        pExpect("RBRACKET")
        const id = newNode("ARRAY_LIT")
        nSetList(id, elems)
        return id
    }
    println(`parse error at line ${curLineNum()}: unexpected token ${k} '${v}'`)
    exit(1)
    return 0
}

function parseTemplateLit(): int {
    // Collect fragments: TMPL_LIT and TMPL_EXPR_START...TMPL_EXPR_END pairs, ending with TMPL_END
    let frags = ""
    while (curKind() != "TMPL_END" && curKind() != "EOF") {
        if (curKind() == "TMPL_LIT") {
            const litId = newNode("TMPL_FRAG_LIT")
            nSetS1(litId, curValue())
            pAdvance()
            frags = listAppend(frags, litId)
        } else if (curKind() == "TMPL_EXPR_START") {
            pAdvance()
            const exprId = parseExpr()
            const fragId = newNode("TMPL_FRAG_EXPR")
            nSetI1(fragId, exprId)
            frags = listAppend(frags, fragId)
            if (curKind() == "TMPL_EXPR_END") { pAdvance() }
        } else {
            break
        }
    }
    if (curKind() == "TMPL_END") { pAdvance() }
    const id = newNode("TEMPLATE_LIT")
    nSetList(id, frags)
    return id
}

function parseArgs(): string {
    skipNL()
    if (curKind() == "RPAREN") { return "" }
    let args = ""
    while (curKind() != "EOF") {
        skipNL()
        // Spread arg: ...expr
        if (curKind() == "SPREAD") {
            pAdvance()
            const spreadExpr = parseExpr()
            const spreadNode = newNode("SPREAD_ELEM")
            nSetI1(spreadNode, spreadExpr)
            args = listAppend(args, spreadNode)
        // Named arg: IDENT followed by COLON → NAMED_ARG node
        } else if (curKind() == "IDENT" && tkKind(tkGet(tokens, tPos + 1)) == "COLON") {
            const naName = curValue()
            pAdvance()
            pAdvance()
            const valId = parseExpr()
            const naId = newNode("NAMED_ARG")
            nSetS1(naId, naName)
            nSetI1(naId, valId)
            args = listAppend(args, naId)
        } else {
            const argId = parseExpr()
            args = listAppend(args, argId)
        }
        skipNL()
        if (curKind() == "COMMA") { pAdvance() } else { break }
    }
    return args
}
