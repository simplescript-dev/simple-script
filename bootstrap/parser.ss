// SimpleScript Bootstrap Parser
// Produces a Map-based AST from a token buffer string (from lexer).
// Each AST node has a unique integer ID. Properties stored in global Maps.

import { tkGet, tkKind, tkValue } from "./lexer"

// ── AST node storage ──────────────────────────────────────────

let nextId = 1
let nKind = ""
let nStr1 = ""
let nStr2 = ""
let nStr3 = ""
let nInt1 = ""
let nInt2 = ""
let nInt3 = ""
let nInt4 = ""
let nList = ""
let mapsReady = 0

function initParser() {
    if (mapsReady == 1) { return }
    nKind = Map()
    nStr1 = Map()
    nStr2 = Map()
    nStr3 = Map()
    nInt1 = Map()
    nInt2 = Map()
    nInt3 = Map()
    nInt4 = Map()
    nList = Map()
    mapsReady = 1
}

function newNode(kind: string): int {
    initParser()
    const id = nextId
    nextId = nextId + 1
    nKind.set(id + "", kind)
    return id
}

function nSetS1(id: int, val: string) { nStr1.set(id + "", val) }
function nSetS2(id: int, val: string) { nStr2.set(id + "", val) }
function nSetS3(id: int, val: string) { nStr3.set(id + "", val) }
function nSetI1(id: int, val: int) { nInt1.set(id + "", val) }
function nSetI2(id: int, val: int) { nInt2.set(id + "", val) }
function nSetI3(id: int, val: int) { nInt3.set(id + "", val) }
function nSetI4(id: int, val: int) { nInt4.set(id + "", val) }
function nSetList(id: int, val: string) { nList.set(id + "", val) }

function nGetKind(id: int): string { return nKind.getString(id + "") }
function nGetS1(id: int): string { return nStr1.getString(id + "") }
function nGetS2(id: int): string { return nStr2.getString(id + "") }
function nGetS3(id: int): string { return nStr3.getString(id + "") }
function nGetI1(id: int): int { return nInt1.get(id + "") }
function nGetI2(id: int): int { return nInt2.get(id + "") }
function nGetI3(id: int): int { return nInt3.get(id + "") }
function nGetI4(id: int): int { return nInt4.get(id + "") }
function nGetList(id: int): string { return nList.getString(id + "") }

// Append child ID to a node's list
function listAppend(listStr: string, childId: int): string {
    if (listStr == "") { return childId + "" }
    return listStr + "," + childId
}

// ── Parser state ──────────────────────────────────────────────

let tokens = ""
let tPos = 0

function curKind(): string {
    return tkKind(tkGet(tokens, tPos))
}

function curValue(): string {
    return tkValue(tkGet(tokens, tPos))
}

function pAdvance() {
    if (curKind() != "EOF") {
        tPos = tPos + 1
    }
}

function pExpect(kind: string) {
    if (curKind() != kind) {
        println("parse error: expected " + kind + ", found " + curKind() + " '" + curValue() + "'")
        exit(1)
    }
    pAdvance()
}

function pExpectIdent(): string {
    if (curKind() != "IDENT") {
        println("parse error: expected identifier, found " + curKind())
        exit(1)
    }
    const name = curValue()
    pAdvance()
    return name
}

function skipNL() {
    while (curKind() == "NEWLINE") {
        pAdvance()
    }
}

function expectNLOrRB() {
    const k = curKind()
    if (k == "NEWLINE") { pAdvance(); return }
    if (k == "RBRACE" || k == "EOF") { return }
    if (k == "SEMICOLON") { pAdvance(); return }
    println("parse error: expected newline or '}', found " + k)
    exit(1)
}

// ── Public API ────────────────────────────────────────────────

// Returns root program node ID
function parse(tokenBuf: string): int {
    initParser()
    tokens = tokenBuf
    tPos = 0
    skipNL()
    const progId = newNode("PROGRAM")
    let stmts = ""
    while (curKind() != "EOF") {
        const stmtId = parseStmt()
        stmts = listAppend(stmts, stmtId)
        skipNL()
    }
    nSetList(progId, stmts)
    return progId
}

// ── Statements ────────────────────────────────────────────────

function parseStmt(): int {
    skipNL()
    const k = curKind()
    if (k == "FUNCTION" || k == "OVERRIDE") { return parseFuncDecl() }
    if (k == "CLASS") { return parseClassDecl() }
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
    if (k == "IMPORT") { return parseImport() }
    if (k == "IDENT") { return parseAssignOrExpr() }
    // Fallback: expression statement
    const exprId = parseExpr()
    expectNLOrRB()
    const id = newNode("EXPR_STMT")
    nSetI1(id, exprId)
    return id
}

function parseFuncDecl(): int {
    if (curKind() == "OVERRIDE") { pAdvance() }
    pExpect("FUNCTION")
    const name = pExpectIdent()
    pExpect("LPAREN")
    const params = parseParams()
    pExpect("RPAREN")
    let retType = ""
    if (curKind() == "COLON") {
        pAdvance()
        retType = parseTypeAnn()
    }
    skipNL()
    const bodyId = parseBlock()
    const id = newNode("FUNC_DECL")
    nSetS1(id, name)
    nSetS2(id, retType)
    nSetList(id, params)
    nSetI1(id, bodyId)
    return id
}

function parseClassDecl(): int {
    pExpect("CLASS")
    const name = pExpectIdent()
    let extendsName = ""
    if (curKind() == "EXTENDS") {
        pAdvance()
        extendsName = pExpectIdent()
    }
    pExpect("LPAREN")
    const fields = parseParams()
    pExpect("RPAREN")
    // Optional implements
    let implList = ""
    if (curKind() == "COLON") {
        pAdvance()
        implList = pExpectIdent()
        while (curKind() == "COMMA") {
            pAdvance()
            implList = implList + "," + pExpectIdent()
        }
    }
    skipNL()
    // Optional body with methods
    let methods = ""
    if (curKind() == "LBRACE") {
        pExpect("LBRACE")
        skipNL()
        while (curKind() != "RBRACE" && curKind() != "EOF") {
            const mId = parseFuncDecl()
            methods = listAppend(methods, mId)
            skipNL()
        }
        pExpect("RBRACE")
    }
    const id = newNode("CLASS_DECL")
    nSetS1(id, name)
    nSetS2(id, extendsName)
    nSetS3(id, implList)
    nSetList(id, fields)
    // Store methods in nInt2 as a BLOCK node
    const methodsBlock = newNode("BLOCK")
    nSetList(methodsBlock, methods)
    nSetI2(id, methodsBlock)
    return id
}

function parseInterfaceDecl(): int {
    pExpect("INTERFACE")
    const name = pExpectIdent()
    skipNL()
    pExpect("LBRACE")
    skipNL()
    let methods = ""
    while (curKind() != "RBRACE" && curKind() != "EOF") {
        pExpect("FUNCTION")
        const mName = pExpectIdent()
        pExpect("LPAREN")
        const params = parseParams()
        pExpect("RPAREN")
        let retType = ""
        if (curKind() == "COLON") {
            pAdvance()
            retType = parseTypeAnn()
        }
        expectNLOrRB()
        skipNL()
        const mId = newNode("IFACE_METHOD")
        nSetS1(mId, mName)
        nSetS2(mId, retType)
        nSetList(mId, params)
        methods = listAppend(methods, mId)
    }
    pExpect("RBRACE")
    const id = newNode("INTERFACE_DECL")
    nSetS1(id, name)
    nSetList(id, methods)
    return id
}

function parseEnumDecl(): int {
    pExpect("ENUM")
    const name = pExpectIdent()
    pExpect("LBRACE")
    skipNL()
    let variants = ""
    while (curKind() != "RBRACE" && curKind() != "EOF") {
        const vId = newNode("ENUM_VARIANT")
        nSetS1(vId, pExpectIdent())
        variants = listAppend(variants, vId)
        if (curKind() == "COMMA") { pAdvance() }
        skipNL()
    }
    pExpect("RBRACE")
    // Rebuild variants properly
    const id = newNode("ENUM_DECL")
    nSetS1(id, name)
    nSetList(id, variants)
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
            if (curKind() == "INT") { patKind = "INT" }
            if (curKind() == "STRING") { patKind = "STRING" }
            nSetS1(patId, patKind)
            nSetS2(patId, curValue())
            pAdvance()
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
    const varKind = curKind()
    pAdvance()
    const name = pExpectIdent()
    let typeAnn = ""
    if (curKind() == "COLON") { pAdvance(); typeAnn = parseTypeAnn() }
    pExpect("ASSIGN")
    const initId = parseExpr()
    const id = newNode("VAR_DECL")
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
    // Check for for-in: for (item in expr)
    if (curKind() == "IDENT") {
        // Look ahead for "in" keyword
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
        // Not for-in, restore position
        tPos = savedPos
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
    const name = pExpectIdent()
    const k = curKind()
    if (k == "PLUS_PLUS") {
        pAdvance()
        const id = newNode("POSTFIX_INC")
        nSetS1(id, name)
        return id
    }
    if (k == "MINUS_MINUS") {
        pAdvance()
        const id = newNode("POSTFIX_DEC")
        nSetS1(id, name)
        return id
    }
    // Assignment operators
    let op = k
    pAdvance()
    const valId = parseExpr()
    const id = newNode("ASSIGN")
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

function parseImport(): int {
    pExpect("IMPORT")
    pExpect("LBRACE")
    let names = ""
    while (curKind() != "RBRACE" && curKind() != "EOF") {
        const n = pExpectIdent()
        if (names == "") { names = n } else { names = names + "," + n }
        if (curKind() == "COMMA") { pAdvance() }
    }
    pExpect("RBRACE")
    pExpect("FROM")
    const path = curValue()
    pAdvance()
    expectNLOrRB()
    const id = newNode("IMPORT")
    nSetS1(id, names)
    nSetS2(id, path)
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
    const name = curValue()
    // Look ahead
    const nextTok = tkKind(tkGet(tokens, tPos + 1))
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
        nSetS1(id, name)
        nSetS2(id, "ASSIGN")
        nSetI1(id, valId)
        return id
    }
    // Compound assignment: x += expr
    if (nextTok == "PLUS_ASSIGN" || nextTok == "MINUS_ASSIGN" || nextTok == "STAR_ASSIGN" || nextTok == "SLASH_ASSIGN" || nextTok == "PERCENT_ASSIGN") {
        pAdvance()
        const op = curKind()
        pAdvance()
        const valId = parseExpr()
        expectNLOrRB()
        const id = newNode("ASSIGN")
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
        nSetS1(pfId, name)
        nSetI1(id, pfId)
        return id
    }
    // Expression statement
    const exprId = parseExpr()
    expectNLOrRB()
    const id = newNode("EXPR_STMT")
    nSetI1(id, exprId)
    return id
}

// ── Helpers ───────────────────────────────────────────────────

function parseParams(): string {
    skipNL()
    if (curKind() == "RPAREN") { return "" }
    let params = ""
    while (curKind() != "EOF") {
        skipNL()
        const pName = pExpectIdent()
        pExpect("COLON")
        const pType = parseTypeAnn()
        let defId = 0
        if (curKind() == "ASSIGN") {
            pAdvance()
            defId = parseExpr()
        }
        const pId = newNode("PARAM")
        nSetS1(pId, pName)
        nSetS2(pId, pType)
        nSetI1(pId, defId)
        params = listAppend(params, pId)
        if (curKind() == "COMMA") { pAdvance() } else { break }
    }
    return params
}

function parseTypeAnn(): string {
    const k = curKind()
    if (k == "INT_TYPE") { pAdvance(); return "int" }
    if (k == "DOUBLE_TYPE") { pAdvance(); return "double" }
    if (k == "STRING_TYPE") { pAdvance(); return "string" }
    if (k == "BOOL_TYPE") { pAdvance(); return "bool" }
    if (k == "VOID_TYPE") { pAdvance(); return "void" }
    if (k == "IDENT") {
        const name = curValue()
        pAdvance()
        // Generic type: Name<T, U, ...>
        if (curKind() == "LT") {
            pAdvance()
            let typeArgs = parseTypeAnn()
            while (curKind() == "COMMA") {
                pAdvance()
                typeArgs = typeArgs + "," + parseTypeAnn()
            }
            pExpect("GT")
            return name + "<" + typeArgs + ">"
        }
        return name
    }
    println("parse error: expected type, found " + k)
    exit(1)
    return ""
}

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
    let left = parseAndExpr()
    while (curKind() == "OR") {
        pAdvance()
        const right = parseAndExpr()
        const id = newNode("BINARY"); nSetS1(id, "Or"); nSetI1(id, left); nSetI2(id, right)
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
        const right = parseMultiplicative()
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
    // Postfix: .member, .method(), [index]
    while (curKind() == "DOT" || curKind() == "LBRACKET") {
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
        // Dot access
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
            expr = id
        } else {
            const id = newNode("MEMBER_ACCESS")
            nSetS1(id, member)
            nSetI1(id, expr)
            expr = id
        }
    }
    return expr
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
    if (k == "NEW") {
        pAdvance()
        const className = pExpectIdent()
        pExpect("LPAREN")
        const argsStr = parseArgs()
        pExpect("RPAREN")
        const id = newNode("NEW_EXPR")
        nSetS1(id, className)
        nSetList(id, argsStr)
        return id
    }
    // Template literal tokens: TMPL_LIT ... TMPL_EXPR_START ... TMPL_EXPR_END ... TMPL_END
    if (k == "TMPL_LIT" || k == "TMPL_EXPR_START") {
        return parseTemplateLit()
    }
    if (k == "IDENT") {
        const name = v
        pAdvance()
        if (curKind() == "LPAREN") {
            pAdvance()
            const argsStr = parseArgs()
            pExpect("RPAREN")
            const id = newNode("CALL")
            nSetS1(id, name)
            nSetList(id, argsStr)
            return id
        }
        const id = newNode("IDENT")
        nSetS1(id, name)
        return id
    }
    if (k == "LPAREN") {
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
                const elemId = parseExpr()
                elems = listAppend(elems, elemId)
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
    println("parse error: unexpected token " + k + " '" + v + "'")
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
        const argId = parseExpr()
        args = listAppend(args, argId)
        skipNL()
        if (curKind() == "COMMA") { pAdvance() } else { break }
    }
    return args
}

