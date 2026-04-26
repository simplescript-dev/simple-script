// SimpleScript Bootstrap Parser — Core
// AST node system, parser state, public API, declarations, helpers.
// Statement parsing in parse_stmts.ss, expression parsing in parse_exprs.ss.

import { tkCol } from "../lexer/lexer"
import { parseStmt, parseBlock, parseVarDecl, parseVarDeclNoNL, parseUpdateStmt } from "./parse_stmts"
import { parseExpr, parseArgs } from "./parse_exprs"

// ── AST node storage ──────────────────────────────────────────

let nextId = 1
let nKind = ""
let nStr1 = ""
let nStr2 = ""
let nStr3 = ""
let nInt1: Array<int> = []
let nInt2: Array<int> = []
let nInt3: Array<int> = []
let nInt4: Array<int> = []
let nList = ""
let nLine: Array<int> = []
let nCol: Array<int> = []
let mapsReady = 0
let parsingAbstractMethod = 0  // D071: skip body parsing for abstract methods

function initParser() {
    if (mapsReady == 1) { return }
    nKind = Map()
    nStr1 = Map()
    nStr2 = Map()
    nStr3 = Map()
    // index 0 is unused (node IDs start at 1)
    nInt1.push(0)
    nInt2.push(0)
    nInt3.push(0)
    nInt4.push(0)
    nList = Map()
    nLine.push(0)
    nCol.push(0)
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
    nInt1.push(0)
    nInt2.push(0)
    nInt3.push(0)
    nInt4.push(0)
    nLine.push(curLineNum())
    nCol.push(curColNum())
    return id
}

function nSetS1(id: int, val: string) { nStr1.set(id + "", val) }
function nSetS2(id: int, val: string) { nStr2.set(id + "", val) }
function nSetS3(id: int, val: string) { nStr3.set(id + "", val) }
function nSetI1(id: int, val: int) { nInt1[id] = val }
function nSetI2(id: int, val: int) { nInt2[id] = val }
function nSetI3(id: int, val: int) { nInt3[id] = val }
function nSetI4(id: int, val: int) { nInt4[id] = val }
function nSetList(id: int, val: string) { nList.set(id + "", val) }

function nGetKind(id: int): string { return nKind.getString(id + "") }
function nGetS1(id: int): string { return nStr1.getString(id + "") }
function nGetS2(id: int): string { return nStr2.getString(id + "") }
function nGetS3(id: int): string { return nStr3.getString(id + "") }
function nGetI1(id: int): int { return nInt1[id] }
function nGetI2(id: int): int { return nInt2[id] }
function nGetI3(id: int): int { return nInt3[id] }
function nGetI4(id: int): int { return nInt4[id] }
function nGetList(id: int): string { return nList.getString(id + "") }
function nGetLine(id: int): int { return nLine[id] }
function nGetCol(id: int): int { return nCol[id] }
function nSetLine(id: int, val: int) { nLine[id] = val }
function nSetCol(id: int, val: int) { nCol[id] = val }

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
    return tkKinds[tPos]
}

function curValue(): string {
    return tkValues[tPos]
}

function kindAt(index: int): string {
    if (index >= tokenCount) { return "EOF" }
    return tkKinds[index]
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

// I021-requestbody-nested-array-array — 类型上下文 ">" 期望:lexer 把 `>>`/`>>>` emit
// 为 SHR/USHR 单 token,在嵌套泛型 (Array<Array<X>> / Array<Array<Array<X>>>) 闭合处
// 必须按"虚拟拆分"消耗:遇 SHR 视作两个 GT(消耗一个,留下一个),USHR 视作三个 GT。
// pendingGtTokens 是"已虚拟消耗 SHR/USHR 但尚未抵充完毕的 GT 余量",下一次类型上下文
// expectGtTypeCtx 调用直接递减不动 token。仅类型上下文 (parseTypeAnn / parseTypeArgList)
// 用此函数;表达式上下文 SHR/USHR 仍走右移运算符路径 (parse_exprs.ss:135)。
let pendingGtTokens = 0

function expectGtTypeCtx() {
    if (pendingGtTokens > 0) {
        pendingGtTokens = pendingGtTokens - 1
        return
    }
    const k = curKind()
    if (k == "GT") {
        pAdvance()
        return
    }
    if (k == "SHR") {
        pendingGtTokens = 1
        pAdvance()
        return
    }
    if (k == "USHR") {
        pendingGtTokens = 2
        pAdvance()
        return
    }
    println(`parse error at line ${curLineNum()}: expected '>', found ${k} '${curValue()}'`)
    exit(1)
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
        // D087: comptime directives are expressions, not annotations
        if (aName == "typeInfo" || aName == "comptimeEmit") { break }
        pAdvance()
        let aArgs = ""
        if (curKind() == "LPAREN") {
            pAdvance()
            aArgs = parseArgs(1)
            pExpect("RPAREN")
        }
        const aId = newNode("ANNOTATION")
        nSetS1(aId, aName)
        nSetList(aId, aArgs)
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

// D096: class body accessor —— `get NAME(): T { body }` / `set NAME(v: T) { body }`.
// Caller already consumed the leading `get`/`set` identifier; this parses what follows.
// Returns a FUNC_DECL node; caller stashes accessor kind (2=get / 3=set) into I2.
function parseAccessorDecl(): int {
    const startLine = curLineNum()
    const startCol = curColNum()
    const name = pExpectIdent()
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
    nSetList(id, params)
    skipNL()
    const bodyId = parseBlock()
    nSetI1(id, bodyId)
    return id
}

function parseFuncDecl(): int {
    const startLine = curLineNum()
    const startCol = curColNum()
    if (curKind() == "OVERRIDE") { pAdvance() }
    pExpect("FUNCTION")
    // D095 Stage E: computed method name `function [${expr}]()` — only
    // meaningful on @methodOf-annotated nested functions inside a handler's
    // for-in over cls.fields. Resolved at codegen after foldComptimeIdents.
    let name = ""
    let nameTemplateId = 0
    if (curKind() == "LBRACKET") {
        pAdvance()
        nameTemplateId = parseExpr()
        pExpect("RBRACKET")
    } else {
        name = pExpectIdent()
    }
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
    // D095 Stage E: stash computed-name template node in I2 (S1 stays empty).
    if (nameTemplateId > 0) { nSetI2(id, nameTemplateId) }
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
            if (curKind() == "COMPTIME") {
                pAdvance()
                const ctBody = parseBlock()
                const ctId = newNode("COMPTIME_BLOCK")
                nSetI1(ctId, ctBody)
                methods = listAppend(methods, ctId)
                skipNL()
                continue
            }
            if (isBodyFieldStart() == 1) {
                let fieldAnns = ""
                if (curKind() == "ANNOTATION") {
                    fieldAnns = parseAnnotationList()
                }
                const pId = parseBodyField()
                if (fieldAnns != "") {
                    // Store as ANNOTATION_LIST node ID in PARAM's nList
                    const fAnnList = newNode("ANNOTATION_LIST")
                    nSetList(fAnnList, fieldAnns)
                    nSetList(pId, fAnnList + "")
                }
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
                // D096: accessor `get NAME(...)` / `set NAME(...)` — non-static only.
                // Lookahead: IDENT "get"|"set" then IDENT then LPAREN disambiguates from a
                // method literally named get/set (which would be followed directly by LPAREN).
                let accessorKind = 0
                const isGetSetIdent = isStatic == 0 && isAbstract == 0 && curKind() == "IDENT" && (curValue() == "get" || curValue() == "set")
                if (isGetSetIdent && kindAt(tPos + 1) == "IDENT" && kindAt(tPos + 2) == "LPAREN") {
                    accessorKind = curValue() == "get" ? 2 : 3
                    pAdvance()
                }
                const mId = accessorKind > 0 ? parseAccessorDecl() : parseFuncDecl()
                attachAnnotations(mId, mAnnotations)
                if (methodAccess > 0) { nSetI3(mId, methodAccess) }
                if (isStatic == 1) { nSetI2(mId, 1) }
                else if (accessorKind > 0) {
                    nSetI2(mId, accessorKind)
                    // D096: getter must have 0 params, setter must have exactly 1.
                    const accParams = nGetList(mId)
                    const accParamCount = accParams == "" ? 0 : accParams.split(",").length()
                    const accName = nGetS1(mId)
                    if (accessorKind == 2 && accParamCount != 0) {
                        println(`parse error at line ${nGetLine(mId)}: getter '${accName}' must have 0 parameters (found ${accParamCount})`)
                        exit(1)
                    }
                    if (accessorKind == 3 && accParamCount != 1) {
                        println(`parse error at line ${nGetLine(mId)}: setter '${accName}' must have exactly 1 parameter (found ${accParamCount})`)
                        exit(1)
                    }
                }
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

// Check if tokens at pos match [const] | [static [const]] ident(:|?)
function isFieldPatternAt(pos: int): int {
    if (kindAt(pos) == "CONST") { return 1 }
    if (kindAt(pos) == "STATIC") {
        const afterStatic = kindAt(pos + 1)
        if (afterStatic == "CONST") { return 1 }
        if (afterStatic == "IDENT") {
            if (kindAt(pos + 2) == "COLON" || kindAt(pos + 2) == "QUESTION") { return 1 }
        }
        return 0
    }
    if (kindAt(pos) == "IDENT") {
        if (kindAt(pos + 1) == "COLON" || kindAt(pos + 1) == "QUESTION") { return 1 }
    }
    return 0
}

// Check if current token starts a field declaration in class body
function isBodyFieldStart(): int {
    if (isFieldPatternAt(tPos) == 1) { return 1 }
    if (curKind() == "PRIVATE" || curKind() == "PROTECTED") {
        return isFieldPatternAt(tPos + 1)
    }
    if (curKind() == "ANNOTATION") {
        // Peek past all annotations to see if a field pattern follows
        let pos = tPos
        while (kindAt(pos) == "ANNOTATION") {
            pos = pos + 1
            if (kindAt(pos) == "LPAREN") {
                let depth = 1
                pos = pos + 1
                while (depth > 0 && kindAt(pos) != "EOF") {
                    if (kindAt(pos) == "LPAREN") { depth = depth + 1 }
                    else if (kindAt(pos) == "RPAREN") { depth = depth - 1 }
                    pos = pos + 1
                }
            }
            while (kindAt(pos) == "NEWLINE") { pos = pos + 1 }
        }
        return isFieldPatternAt(pos)
    }
    return 0
}

// Parse a single field declaration in class body: [private|protected] [static] [const] name[?]: type [= default]
function parseBodyField(): int {
    let accessLevel = 0
    if (curKind() == "PRIVATE") {
        accessLevel = 1
        pAdvance()
    } else if (curKind() == "PROTECTED") {
        accessLevel = 2
        pAdvance()
    }
    // D078: static fields
    let isStatic = 0
    if (curKind() == "STATIC") {
        isStatic = 1
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
    if (isStatic == 1) { nSetI4(pId, 1) }
    expectNLOrRB()
    return pId
}

function parseParams(): string {
    skipNL()
    if (curKind() == "RPAREN") { return "" }
    let params = ""
    while (curKind() != "EOF") {
        skipNL()
        // Parameter-level annotation: @PathVariable name: type
        let paramAnn = 0
        if (curKind() == "ANNOTATION") {
            const annName = curValue()
            pAdvance()
            let pAnnArgs = ""
            if (curKind() == "LPAREN") {
                pAdvance()
                pAnnArgs = parseArgs(1)
                pExpect("RPAREN")
            }
            paramAnn = newNode("ANNOTATION")
            nSetS1(paramAnn, annName)
            nSetList(paramAnn, pAnnArgs)
            skipNL()
        }
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
        if (paramAnn > 0) { nSetI4(pId, paramAnn) }
        params = listAppend(params, pId)
        if (curKind() == "COMMA") { pAdvance() } else { break }
    }
    return params
}

// Check for nullable suffix '?' after a parsed type (D067)
// D132: SHR/USHR 拆分中间状态 (pendingGtTokens > 0) outer 容器尚未闭合,cursor 上的
// QUESTION 属 outer 不属当前 baseType。inner 必须留给 outer maybeNullable 在 outer
// expectGtTypeCtx pendingGtTokens 递减归零后消耗,否则 `Array<Array<Tag>>?` 类型字符串
// 错位为 `Array<Array<Tag>?>`(outer `?` 下沉到 inner element)。
function maybeNullable(baseType: string): string {
    if (pendingGtTokens > 0) { return baseType }
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
    // `${expr}` type-position comptime interpolation. Encoded as `ct:<exprId>`;
    // codegen folds the expr to a string at FUNC_DECL PARAM binding time.
    if (k == "TMPL_EXPR_START") {
        pAdvance()
        const exprId = parseExpr()
        pExpect("TMPL_EXPR_END")
        return `ct:${exprId}`
    }
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
            expectGtTypeCtx()
            return maybeNullable(name + "<" + typeArgs + ">")
        }
        return maybeNullable(name)
    }
    println(`parse error at line ${curLineNum()}: expected type, found ${k}`)
    exit(1)
    return ""
}
