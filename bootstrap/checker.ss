// SimpleScript Bootstrap Type Checker
// Walks the Map-based AST, registers functions, checks variable usage.
// For the bootstrap compiler, this is simplified: no deep type inference,
// focus on detecting undefined vars/funcs and const reassignment.

import { nGetKind, nGetS1, nGetS2, nGetS3, nGetI1, nGetI2, nGetI3, nGetI4, nGetList } from "./parser"

// ── Scope + function registry ─────────────────────────────────

let scopeDepth = 0
let varNames = Map()     // "depth:name" -> "type"
let varConst = Map()     // "depth:name" -> 1 if const
let funcNames = Map()    // "funcName" -> "retType"
let funcReady = 0

function initChecker() {
    if (funcReady == 1) { return }
    varNames = Map()
    varConst = Map()
    funcNames = Map()
    scopeDepth = 0
    // Built-in functions
    const builtins = "println,print,readLine,readFile,writeFile,args,arg,exit,system,parseInt,parseDouble,Map,sqrt,abs,floor,ceil,round,log,sin,cos,pow,min,max,random,timeMs"
    const parts = builtins.split(",")
    for (name in parts) {
        funcNames.set(name, "builtin")
    }
    funcReady = 1
}

function pushScope() {
    scopeDepth = scopeDepth + 1
}

function popScope() {
    // Remove vars at current depth
    // (simplified: we don't clean up, just decrement depth; lookups check all depths)
    scopeDepth = scopeDepth - 1
}

function defineVar(name: string, varType: string, isConst: int) {
    const key = scopeDepth + ":" + name
    varNames.set(key, varType)
    if (isConst == 1) {
        varConst.set(key, 1)
    }
}

function lookupVar(name: string): string {
    let d = scopeDepth
    while (d >= 0) {
        const key = d + ":" + name
        if (varNames.has(key) == 1) {
            return varNames.getString(key)
        }
        d = d - 1
    }
    return ""
}

function isVarConst(name: string): int {
    let d = scopeDepth
    while (d >= 0) {
        const key = d + ":" + name
        if (varNames.has(key) == 1) {
            return varConst.has(key)
        }
        d = d - 1
    }
    return 0
}

function defineFunc(name: string, retType: string) {
    funcNames.set(name, retType)
}

function lookupFunc(name: string): int {
    return funcNames.has(name)
}

// ── Public API ────────────────────────────────────────────────

function check(rootId: int): int {
    initChecker()
    const kind = nGetKind(rootId)
    if (kind != "PROGRAM") {
        println("checker error: expected PROGRAM node")
        exit(1)
    }
    const stmtList = nGetList(rootId)
    // Pass 1: register all function declarations
    if (stmtList != "") {
        const parts = stmtList.split(",")
        for (p in parts) {
            const stmtId = parseInt(p)
            if (stmtId > 0) {
                const sk = nGetKind(stmtId)
                if (sk == "FUNC_DECL") {
                    const fname = nGetS1(stmtId)
                    const retType = nGetS2(stmtId)
                    defineFunc(fname, retType)
                }
            }
        }
    }
    // Pass 2: check all statements
    if (stmtList != "") {
        const parts = stmtList.split(",")
        for (p in parts) {
            const stmtId = parseInt(p)
            if (stmtId > 0) {
                checkStmt(stmtId)
            }
        }
    }
    return 1
}

// ── Statement checking ────────────────────────────────────────

function checkStmt(id: int) {
    const kind = nGetKind(id)
    if (kind == "FUNC_DECL") {
        pushScope()
        // Define params
        const paramList = nGetList(id)
        checkParamList(paramList)
        // Check body
        const bodyId = nGetI1(id)
        checkBlock(bodyId)
        popScope()
        return
    }
    if (kind == "CLASS_DECL") {
        // Check methods
        const methodsBlockId = nGetI2(id)
        if (methodsBlockId > 0) {
            const methodList = nGetList(methodsBlockId)
            checkStmtList(methodList)
        }
        return
    }
    if (kind == "VAR_DECL") {
        const name = nGetS1(id)
        const varKind = nGetS2(id)
        let typeAnn = nGetS3(id)
        const initId = nGetI1(id)
        if (initId > 0) { checkExpr(initId) }
        if (typeAnn == "") { typeAnn = "auto" }
        if (varKind == "CONST") {
            defineVar(name, typeAnn, 1)
        } else {
            defineVar(name, typeAnn, 0)
        }
        return
    }
    if (kind == "ASSIGN") {
        const name = nGetS1(id)
        if (lookupVar(name) == "") {
            println("checker error: undefined variable '" + name + "'")
            exit(1)
        }
        if (isVarConst(name) == 1) {
            println("checker error: cannot reassign const variable '" + name + "'")
            exit(1)
        }
        const valId = nGetI1(id)
        if (valId > 0) { checkExpr(valId) }
        return
    }
    if (kind == "INDEX_ASSIGN") {
        const indexId = nGetI1(id)
        const valId = nGetI2(id)
        if (indexId > 0) { checkExpr(indexId) }
        if (valId > 0) { checkExpr(valId) }
        return
    }
    if (kind == "EXPR_STMT") {
        const exprId = nGetI1(id)
        if (exprId > 0) { checkExpr(exprId) }
        return
    }
    if (kind == "RETURN") {
        const valId = nGetI1(id)
        if (valId > 0) { checkExpr(valId) }
        return
    }
    if (kind == "IF") {
        checkExpr(nGetI1(id))
        pushScope()
        checkBlock(nGetI2(id))
        popScope()
        const elseId = nGetI3(id)
        if (elseId > 0) {
            pushScope()
            checkBlock(elseId)
            popScope()
        }
        return
    }
    if (kind == "FOR") {
        pushScope()
        checkStmt(nGetI1(id))
        checkExpr(nGetI2(id))
        checkStmt(nGetI3(id))
        checkBlock(nGetI4(id))
        popScope()
        return
    }
    if (kind == "FOR_IN") {
        pushScope()
        checkExpr(nGetI1(id))
        defineVar(nGetS1(id), "auto", 0)
        checkBlock(nGetI2(id))
        popScope()
        return
    }
    if (kind == "WHILE") {
        checkExpr(nGetI1(id))
        pushScope()
        checkBlock(nGetI2(id))
        popScope()
        return
    }
    if (kind == "DO_WHILE") {
        pushScope()
        checkBlock(nGetI1(id))
        popScope()
        checkExpr(nGetI2(id))
        return
    }
    if (kind == "SWITCH") {
        checkExpr(nGetI1(id))
        const caseList = nGetList(id)
        checkStmtList(caseList)
        const defId = nGetI2(id)
        if (defId > 0) { checkBlock(defId) }
        return
    }
    if (kind == "SWITCH_CASE") {
        checkBlock(nGetI2(id))
        return
    }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") {
        const name = nGetS1(id)
        if (lookupVar(name) == "") {
            println("checker error: undefined variable '" + name + "'")
            exit(1)
        }
        return
    }
    // IMPORT, INTERFACE_DECL, ENUM_DECL, BREAK, CONTINUE — no checks needed
}

function checkBlock(blockId: int) {
    if (blockId <= 0) { return }
    const kind = nGetKind(blockId)
    if (kind != "BLOCK") { return }
    const stmtList = nGetList(blockId)
    checkStmtList(stmtList)
}

function checkStmtList(listStr: string) {
    if (listStr == "") { return }
    const parts = listStr.split(",")
    for (p in parts) {
        const childId = parseInt(p)
        if (childId > 0) {
            checkStmt(childId)
        }
    }
}

function checkParamList(listStr: string) {
    if (listStr == "") { return }
    const parts = listStr.split(",")
    for (p in parts) {
        const paramId = parseInt(p)
        if (paramId > 0) {
            const pk = nGetKind(paramId)
            if (pk == "PARAM") {
                defineVar(nGetS1(paramId), nGetS2(paramId), 0)
            }
        }
    }
}

// ── Expression checking ───────────────────────────────────────

function checkExpr(id: int) {
    if (id <= 0) { return }
    const kind = nGetKind(id)
    if (kind == "INT_LIT" || kind == "DOUBLE_LIT" || kind == "STRING_LIT") { return }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT" || kind == "NULL_LIT") { return }
    if (kind == "THIS") { return }
    if (kind == "IDENT") {
        const name = nGetS1(id)
        if (lookupVar(name) == "" && lookupFunc(name) == 0) {
            println("checker error: undefined variable '" + name + "'")
            exit(1)
        }
        return
    }
    if (kind == "BINARY") {
        checkExpr(nGetI1(id))
        checkExpr(nGetI2(id))
        return
    }
    if (kind == "UNARY") {
        checkExpr(nGetI1(id))
        return
    }
    if (kind == "CALL") {
        const callee = nGetS1(id)
        if (lookupFunc(callee) == 0) {
            println("checker error: undefined function '" + callee + "'")
            exit(1)
        }
        checkArgList(nGetList(id))
        return
    }
    if (kind == "METHOD_CALL") {
        checkExpr(nGetI1(id))
        checkArgList(nGetList(id))
        return
    }
    if (kind == "MEMBER_ACCESS") {
        checkExpr(nGetI1(id))
        return
    }
    if (kind == "INDEX_ACCESS") {
        checkExpr(nGetI1(id))
        checkExpr(nGetI2(id))
        return
    }
    if (kind == "NEW_EXPR") {
        checkArgList(nGetList(id))
        return
    }
    if (kind == "ARRAY_LIT") {
        checkArgList(nGetList(id))
        return
    }
    if (kind == "TERNARY") {
        checkExpr(nGetI1(id))
        checkExpr(nGetI2(id))
        checkExpr(nGetI3(id))
        return
    }
    if (kind == "GROUPING") {
        checkExpr(nGetI1(id))
        return
    }
    if (kind == "TEMPLATE_LIT") {
        const fragList = nGetList(id)
        if (fragList != "") {
            const parts = fragList.split(",")
            for (p in parts) {
                const fragId = parseInt(p)
                if (fragId > 0) {
                    const fk = nGetKind(fragId)
                    if (fk == "TMPL_FRAG_EXPR") {
                        checkExpr(nGetI1(fragId))
                    }
                }
            }
        }
        return
    }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") {
        const name = nGetS1(id)
        if (lookupVar(name) == "") {
            println("checker error: undefined variable '" + name + "'")
            exit(1)
        }
        return
    }
}

function checkArgList(listStr: string) {
    if (listStr == "") { return }
    const parts = listStr.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0) {
            checkExpr(argId)
        }
    }
}
