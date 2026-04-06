// SimpleScript Bootstrap Parser — Core
// AST node system, parser state, public API, declarations, helpers.
// Statement parsing in parse_stmts.ss, expression parsing in parse_exprs.ss.

import { tkGet, tkKind, tkValue, tkCol } from "./lexer"
import { parseStmt, parseBlock, parseVarDecl, parseVarDeclNoNL, parseUpdateStmt } from "./parse_stmts"
import { parseExpr, parseArgs } from "./parse_exprs"

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
let nLine = ""
let nCol = ""
let mapsReady = 0
let parsingAbstractMethod = 0  // D071: skip body parsing for abstract methods

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
    nLine = Map()
    nCol = Map()
    classTypeParamsMap = Map()
    funcConstraintMap = Map()
    classConstraintMap = Map()
    classTPReady = 1
    mapsReady = 1
}

function newNode(kind: string): int {
    initParser()
    const id = nextId
    nextId = nextId + 1
    nKind.set(id + "", kind)
    nLine.set(id + "", curLineNum())
    nCol.set(id + "", curColNum())
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
function nGetLine(id: int): int { return nLine.get(id + "") }
function nGetCol(id: int): int { return nCol.get(id + "") }
function nSetLine(id: int, val: int) { nLine.set(id + "", val) }
function nSetCol(id: int, val: int) { nCol.set(id + "", val) }

// ── Semantic AST accessors ────────────────────────────────────
// Use these instead of raw nGetS1/nGetI1 for self-documenting code.
// FUNC_DECL: S1=name, S2=retType, List=params, I1=body, I4=annotations
function funcName(id: int): string { return nGetS1(id) }
function funcRetType(id: int): string { return nGetS2(id) }
function funcParams(id: int): string { return nGetList(id) }
function funcBody(id: int): int { return nGetI1(id) }
// CLASS_DECL: S1=className, S2=parentName, S3=implList, List=fields, I2=methodsBlock, I4=annotations
function classNodeName(id: int): string { return nGetS1(id) }
function classParentName(id: int): string { return nGetS2(id) }
function classFieldList(id: int): string { return nGetList(id) }
function classMethodsBlock(id: int): int { return nGetI2(id) }
// Generic class type params: stored in separate Map (CLASS_DECL S1-S3 all used)
let classTypeParamsMap = ""
let classTPReady = 0
function classTypeParams(id: int): string {
    if (classTPReady == 0) { return "" }
    const key = id + ""
    if (classTypeParamsMap.has(key) == 1) { return classTypeParamsMap.getString(key) }
    return ""
}
// Generic type constraints: "&"-separated for multi-constraints, e.g. "Printable&Scorable"
let funcConstraintMap = ""
let classConstraintMap = ""
function funcConstraint(funcName: string, tp: string): string {
    const key = `${funcName}.${tp}`
    if (funcConstraintMap.has(key) == 1) { return funcConstraintMap.getString(key) }
    return ""
}
function classConstraint(className: string, tp: string): string {
    const key = `${className}.${tp}`
    if (classConstraintMap.has(key) == 1) { return classConstraintMap.getString(key) }
    return ""
}
// VAR_DECL: S1=name, S2=mutability(CONST/LET), S3=typeAnnotation, I1=initExpr
function varName(id: int): string { return nGetS1(id) }
function varMut(id: int): string { return nGetS2(id) }
function varTypeAnn(id: int): string { return nGetS3(id) }
function varInit(id: int): int { return nGetI1(id) }
// PARAM: S1=name, S2=type, I1=defaultValue, I2=isOptional
function paramName(id: int): string { return nGetS1(id) }
function paramType(id: int): string { return nGetS2(id) }

// Append child ID to a node's list
function listAppend(listStr: string, childId: int): string {
    if (listStr == "") { return childId + "" }
    return listStr + "," + childId
}

function listAppendStr(listStr: string, item: string): string {
    if (listStr == "") { return item }
    return listStr + "," + item
}

function listGet(listStr: string, index: int): string {
    if (listStr == "") { return "" }
    const parts = listStr.split(",")
    let i = 0
    for (p in parts) {
        if (i == index) { return p }
        i = i + 1
    }
    return ""
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

let lineOffset = 0

function setLineOffset(offset: int) {
    lineOffset = offset
}

function curLineNum(): int {
    const raw = tkLine(tPos)
    const adjusted = raw - lineOffset
    return adjusted > 0 ? adjusted : raw
}

function curColNum(): int {
    return tkCol(tPos)
}

function getLineOffset(): int {
    return lineOffset
}

function pExpect(kind: string) {
    if (curKind() != kind) {
        println(`parse error at line ${curLineNum()}: expected ${kind}, found ${curKind()} '${curValue()}'`)
        exit(1)
    }
    pAdvance()
}

function pExpectIdent(): string {
    if (curKind() != "IDENT") {
        println(`parse error at line ${curLineNum()}: expected identifier, found ${curKind()}`)
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
    println(`parse error at line ${curLineNum()}: expected newline or '}', found ${k}`)
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

// ── Annotations ──────────────────────────────────────────────

function parseAnnotationList(): string {
    let annotations = ""
    while (curKind() == "ANNOTATION") {
        const aName = curValue()
        pAdvance()
        let aArg = ""
        if (curKind() == "LPAREN") {
            pAdvance()
            if (curKind() == "STRING") { aArg = curValue(); pAdvance() }
            pExpect("RPAREN")
        }
        const aId = newNode("ANNOTATION")
        nSetS1(aId, aName)
        nSetS2(aId, aArg)
        annotations = listAppend(annotations, aId)
        skipNL()
    }
    return annotations
}

function attachAnnotations(nodeId: int, annotations: string) {
    if (annotations == "") { return }
    const annListNode = newNode("ANNOTATION_LIST")
    nSetList(annListNode, annotations)
    nSetI4(nodeId, annListNode)
}

// ── Declarations ─────────────────────────────────────────────

function parseTypeParamList(ownerName: string, cMap: Map): string {
    let tp = pExpectIdent()
    if (curKind() == "EXTENDS") {
        pAdvance()
        let constraint = pExpectIdent()
        while (curKind() == "BIT_AND") {
            pAdvance()
            constraint = `${constraint}&${pExpectIdent()}`
        }
        cMap.set(`${ownerName}.${tp}`, constraint)
    }
    let result = tp
    while (curKind() == "COMMA") {
        pAdvance()
        tp = pExpectIdent()
        if (curKind() == "EXTENDS") {
            pAdvance()
            let constraint = pExpectIdent()
            while (curKind() == "BIT_AND") {
                pAdvance()
                constraint = `${constraint}&${pExpectIdent()}`
            }
            cMap.set(`${ownerName}.${tp}`, constraint)
        }
        result = listAppendStr(result, tp)
    }
    pExpect("GT")
    return result
}

function parseFuncDecl(): int {
    const startLine = curLineNum()
    const startCol = curColNum()
    if (curKind() == "OVERRIDE") { pAdvance() }
    pExpect("FUNCTION")
    const name = pExpectIdent()
    let typeParams = ""
    if (curKind() == "LT") {
        pAdvance()
        typeParams = parseTypeParamList(name, funcConstraintMap)
    }
    pExpect("LPAREN")
    const params = parseParams()
    pExpect("RPAREN")
    let retType = ""
    if (curKind() == "COLON") {
        pAdvance()
        retType = parseTypeAnn()
    }
    const id = newNode("FUNC_DECL")
    nSetLine(id, startLine)
    nSetCol(id, startCol)
    nSetS1(id, name)
    nSetS2(id, retType)
    nSetS3(id, typeParams)
    nSetList(id, params)
    if (parsingAbstractMethod == 1) {
        // D071: abstract method — no body
        parsingAbstractMethod = 0
    } else {
        skipNL()
        const bodyId = parseBlock()
        nSetI1(id, bodyId)
    }
    return id
}

function parseClassDecl(): int {
    const startLine = curLineNum()
    const startCol = curColNum()
    pExpect("CLASS")
    const name = pExpectIdent()
    let classTP = ""
    if (curKind() == "LT") {
        pAdvance()
        classTP = parseTypeParamList(name, classConstraintMap)
    }
    let extendsName = ""
    if (curKind() == "EXTENDS") {
        pAdvance()
        extendsName = parseTypeAnn()
    }
    let fields = ""
    // Optional implements
    let implList = ""
    if (curKind() == "COLON") {
        pAdvance()
        implList = pExpectIdent()
        while (curKind() == "COMMA") {
            pAdvance()
            implList = listAppendStr(implList, pExpectIdent())
        }
    }
    skipNL()
    // Optional body with fields and/or methods
    let methods = ""
    if (curKind() == "LBRACE") {
        pExpect("LBRACE")
        skipNL()
        while (curKind() != "RBRACE" && curKind() != "EOF") {
            if (isBodyFieldStart() == 1) {
                const pId = parseBodyField()
                fields = listAppend(fields, pId)
            } else {
                let methodAccess = 0
                if (curKind() == "PRIVATE") {
                    methodAccess = 1
                    pAdvance()
                } else if (curKind() == "PROTECTED") {
                    methodAccess = 2
                    pAdvance()
                }
                let isStatic = 0
                let isAbstract = 0
                if (curKind() == "STATIC") {
                    isStatic = 1
                    pAdvance()
                } else if (curKind() == "ABSTRACT") {
                    isAbstract = 1
                    pAdvance()
                }
                if (isAbstract == 1) { parsingAbstractMethod = 1 }
                const mAnnotations = parseAnnotationList()
                const mId = parseFuncDecl()
                attachAnnotations(mId, mAnnotations)
                if (methodAccess > 0) { nSetI3(mId, methodAccess) }
                if (isStatic == 1) { nSetI2(mId, 1) }
                if (isAbstract == 1) { nSetI4(mId, 1) }
                methods = listAppend(methods, mId)
            }
            skipNL()
        }
        pExpect("RBRACE")
    }
    const id = newNode("CLASS_DECL")
    nSetLine(id, startLine)
    nSetCol(id, startCol)
    nSetS1(id, name)
    nSetS2(id, extendsName)
    nSetS3(id, implList)
    nSetList(id, fields)
    // Store methods in nInt2 as a BLOCK node
    const methodsBlock = newNode("BLOCK")
    nSetList(methodsBlock, methods)
    nSetI2(id, methodsBlock)
    // Store generic type params in separate Map (S1-S3 all used)
    if (classTP != "") {
        classTypeParamsMap.set(id + "", classTP)
    }
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
    let nextVal = 0
    let isStringEnum = 0
    while (curKind() != "RBRACE" && curKind() != "EOF") {
        const vId = newNode("ENUM_VARIANT")
        nSetS1(vId, pExpectIdent())
        if (curKind() == "ASSIGN") {
            pAdvance()
            if (curKind() == "STRING") {
                nSetS2(vId, curValue())
                isStringEnum = 1
            } else {
                nextVal = parseInt(curValue())
            }
            pAdvance()
        }
        if (isStringEnum == 0) {
            nSetI1(vId, nextVal)
            nextVal = nextVal + 1
        }
        variants = listAppend(variants, vId)
        if (curKind() == "COMMA") { pAdvance() }
        skipNL()
    }
    pExpect("RBRACE")
    const id = newNode("ENUM_DECL")
    nSetS1(id, name)
    nSetList(id, variants)
    if (isStringEnum == 1) { nSetI1(id, 1) }
    return id
}

function parseImport(): int {
    pExpect("IMPORT")
    pExpect("LBRACE")
    let names = ""
    while (curKind() != "RBRACE" && curKind() != "EOF") {
        const n = pExpectIdent()
        // Support: import { Foo as Bar } — parse but alias stored for future use
        if (curKind() == "IDENT" && curValue() == "as") {
            pAdvance()
            const alias = pExpectIdent()
            names = listAppendStr(names, `${n}:${alias}`)
        } else {
            names = listAppendStr(names, n)
        }
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

// ── Helpers ───────────────────────────────────────────────────

// Check if current token starts a field declaration in class body
function isBodyFieldStart(): int {
    if (curKind() == "CONST") { return 1 }
    if (curKind() == "PRIVATE" || curKind() == "PROTECTED") {
        const nextTok = tkKind(tkGet(tokens, tPos + 1))
        if (nextTok == "CONST") { return 1 }
        if (nextTok == "IDENT") {
            const nextNextTok = tkKind(tkGet(tokens, tPos + 2))
            if (nextNextTok == "COLON" || nextNextTok == "QUESTION") { return 1 }
        }
        return 0
    }
    if (curKind() == "IDENT") {
        const nextTok = tkKind(tkGet(tokens, tPos + 1))
        if (nextTok == "COLON" || nextTok == "QUESTION") { return 1 }
    }
    return 0
}

// Parse a single field declaration in class body: [private|protected] [const] name[?]: type [= default]
function parseBodyField(): int {
    let accessLevel = 0
    if (curKind() == "PRIVATE") {
        accessLevel = 1
        pAdvance()
    } else if (curKind() == "PROTECTED") {
        accessLevel = 2
        pAdvance()
    }
    let isFieldConst = 0
    if (curKind() == "CONST") {
        isFieldConst = 1
        pAdvance()
    }
    const pName = pExpectIdent()
    let isOptional = 0
    if (curKind() == "QUESTION") {
        isOptional = 1
        pAdvance()
    }
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
    nSetI2(pId, isOptional)
    if (isFieldConst == 1) { nSetS3(pId, "const") }
    if (accessLevel > 0) { nSetI3(pId, accessLevel) }
    expectNLOrRB()
    return pId
}

function parseParams(): string {
    skipNL()
    if (curKind() == "RPAREN") { return "" }
    let params = ""
    while (curKind() != "EOF") {
        skipNL()
        // Field-level const: const name: Type
        let isFieldConst = 0
        if (curKind() == "CONST") {
            isFieldConst = 1
            pAdvance()
        }
        const pName = pExpectIdent()
        // Optional param: name?: type (equivalent to name: type = default)
        let isOptional = 0
        if (curKind() == "QUESTION") {
            isOptional = 1
            pAdvance()
        }
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
        nSetI2(pId, isOptional)
        if (isFieldConst == 1) { nSetS3(pId, "const") }
        params = listAppend(params, pId)
        if (curKind() == "COMMA") { pAdvance() } else { break }
    }
    return params
}

// Check for nullable suffix '?' after a parsed type (D067)
function maybeNullable(baseType: string): string {
    if (curKind() == "QUESTION") {
        pAdvance()
        return baseType + "?"
    }
    return baseType
}

function parseTypeAnn(): string {
    const k = curKind()
    if (k == "INT_TYPE") { pAdvance(); return maybeNullable("int") }
    if (k == "DOUBLE_TYPE") { pAdvance(); return maybeNullable("double") }
    if (k == "STRING_TYPE") { pAdvance(); return maybeNullable("string") }
    if (k == "BOOL_TYPE") { pAdvance(); return maybeNullable("bool") }
    if (k == "VOID_TYPE") { pAdvance(); return "void" }
    // Tuple type: [type, type, ...]
    if (k == "LBRACKET") {
        pAdvance()
        let types = parseTypeAnn()
        while (curKind() == "COMMA") {
            pAdvance()
            types = listAppendStr(types, parseTypeAnn())
        }
        pExpect("RBRACKET")
        return maybeNullable("Tuple<" + types + ">")
    }
    if (k == "IDENT") {
        let name = curValue()
        pAdvance()
        // Normalize List → Array (user-facing alias, D021)
        if (name == "List") { name = "Array" }
        // Generic type: Name<T, U, ...>
        if (curKind() == "LT") {
            pAdvance()
            let typeArgs = parseTypeAnn()
            while (curKind() == "COMMA") {
                pAdvance()
                typeArgs = listAppendStr(typeArgs, parseTypeAnn())
            }
            pExpect("GT")
            return maybeNullable(name + "<" + typeArgs + ">")
        }
        return maybeNullable(name)
    }
    println(`parse error at line ${curLineNum()}: expected type, found ${k}`)
    exit(1)
    return ""
}
