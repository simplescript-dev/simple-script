// SimpleScript Bootstrap Type Checker
// Walks the Map-based AST, registers functions, checks variable usage.
// For the bootstrap compiler, this is simplified: no deep type inference,
// focus on detecting undefined vars/funcs and const reassignment.

import { nGetKind, nGetS1, nGetS2, nGetS3, nGetI1, nGetI2, nGetI3, nGetI4, nGetList } from "./parser"

// ── Scope + function registry ─────────────────────────────────

let scopeId = 0
let currentScope = 0
let scopeParent = ""  // Map: "scopeId" -> "parentScopeId" (chain-based scope)
let varNames = ""     // "scopeId:name" -> "type"
let varConst = ""     // "scopeId:name" -> "const" if const
let funcNames = ""    // "funcName" -> "retType"
let ifaceMethods = ""
let funcParamMin = ""  // "funcName" -> min args (required params)
let funcParamMax = ""  // "funcName" -> max args (total params)
let funcReady = 0

function initChecker() {
    if (funcReady == 1) { return }
    varNames = Map()
    varConst = Map()
    funcNames = Map()
    ifaceMethods = Map()
    scopeParent = Map()
    funcParamMin = Map()
    funcParamMax = Map()
    scopeId = 0
    currentScope = 0
    // Built-in functions
    const builtins = "println,print,readLine,readFile,writeFile,args,arg,exit,system,parseInt,parseDouble,Map,sqrt,abs,floor,ceil,round,log,sin,cos,pow,min,max,random,timeMs"
    const parts = builtins.split(",")
    for (name in parts) {
        funcNames.set(name, "builtin")
    }
    // Built-in param counts
    const zeroArgFns = "readLine,args,Map,random,timeMs"
    const za = zeroArgFns.split(",")
    for (z in za) {
        funcParamMin.set(z, "0")
        funcParamMax.set(z, "0")
    }
    const oneArgFns = "println,print,readFile,arg,exit,system,parseInt,parseDouble,sqrt,abs,floor,ceil,round,log,sin,cos"
    const oa = oneArgFns.split(",")
    for (o in oa) {
        funcParamMin.set(o, "1")
        funcParamMax.set(o, "1")
    }
    const twoArgFns = "writeFile,pow,min,max"
    const ta = twoArgFns.split(",")
    for (t in ta) {
        funcParamMin.set(t, "2")
        funcParamMax.set(t, "2")
    }
    funcReady = 1
}

function pushScope() {
    scopeId = scopeId + 1
    scopeParent.set(`${scopeId}`, `${currentScope}`)
    currentScope = scopeId
}

function popScope() {
    currentScope = parseInt(scopeParent.getString(`${currentScope}`))
}

function defineVar(name: string, varType: string, isConst: int) {
    const key = `${currentScope}:${name}`
    varNames.set(key, varType)
    if (isConst == 1) {
        varConst.set(key, "const")
    }
}

function lookupVar(name: string): string {
    let s = currentScope
    while (s >= 0) {
        const key = `${s}:${name}`
        if (varNames.has(key) == 1) {
            return varNames.getString(key)
        }
        if (s == 0) { break }
        s = parseInt(scopeParent.getString(`${s}`))
    }
    return ""
}

function isVarConst(name: string): int {
    let s = currentScope
    while (s >= 0) {
        const key = `${s}:${name}`
        if (varNames.has(key) == 1) {
            return varConst.has(key)
        }
        if (s == 0) { break }
        s = parseInt(scopeParent.getString(`${s}`))
    }
    return 0
}

function checkInterfaceImpl(className: string, implList: string, classMethods: string) {
    // Scan comma-separated interface names without for-in (avoids i64/ptr issue)
    let remaining = implList
    while (remaining != "") {
        let iface = remaining
        const commaIdx = remaining.indexOf(",")
        if (commaIdx >= 0) {
            iface = remaining.substring(0, commaIdx)
            remaining = remaining.substring(commaIdx + 1, remaining.length() - commaIdx - 1)
        } else {
            remaining = ""
        }
        if (ifaceMethods.has(iface) == 1) {
            const required = ifaceMethods.getString(iface)
            if (required != "") {
                let remReq = required
                while (remReq != "") {
                    let req = remReq
                    const ci = remReq.indexOf(",")
                    if (ci >= 0) {
                        req = remReq.substring(0, ci)
                        remReq = remReq.substring(ci + 1, remReq.length() - ci - 1)
                    } else {
                        remReq = ""
                    }
                    if (classMethods.contains(`,${req},`) == 0) {
                        println(`checker error: class '${className}' missing method '${req}' required by interface '${iface}'`)
                        exit(1)
                    }
                }
            }
        }
    }
}

function defineFunc(name: string, retType: string) {
    funcNames.set(name, retType)
}

function lookupFunc(name: string): int {
    return funcNames.has(name)
}

function defineFuncParams(name: string, minArgs: int, maxArgs: int) {
    if (funcParamMin.has(name) == 1) {
        const existMin = parseInt(funcParamMin.getString(name))
        const existMax = parseInt(funcParamMax.getString(name))
        if (minArgs < existMin) { funcParamMin.set(name, `${minArgs}`) }
        if (maxArgs > existMax) { funcParamMax.set(name, `${maxArgs}`) }
    } else {
        funcParamMin.set(name, `${minArgs}`)
        funcParamMax.set(name, `${maxArgs}`)
    }
}

function countArgs(listStr: string): int {
    if (listStr == "") { return 0 }
    let count = 0
    const parts = listStr.split(",")
    for (p in parts) {
        const argId = parseInt(p)
        if (argId > 0) { count = count + 1 }
    }
    return count
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
    // Pass 1: register function declarations + interface definitions
    if (stmtList != "") {
        const p1 = stmtList.split(",")
        for (p in p1) {
            const s = parseInt(p)
            if (s <= 0) { continue }
            if (nGetKind(s) == "FUNC_DECL") {
                const fname = nGetS1(s)
                defineFunc(fname, nGetS2(s))
                const paramList = nGetList(s)
                let minP = 0
                let maxP = 0
                if (paramList != "") {
                    const ps = paramList.split(",")
                    for (pp in ps) {
                        const ppId = parseInt(pp)
                        if (ppId > 0 && nGetKind(ppId) == "PARAM") {
                            maxP = maxP + 1
                            if (nGetI1(ppId) <= 0 && nGetI2(ppId) <= 0) {
                                minP = minP + 1
                            }
                        }
                    }
                }
                defineFuncParams(fname, minP, maxP)
            }
            if (nGetKind(s) == "INTERFACE_DECL") {
                const ifName = nGetS1(s)
                const ml = nGetList(s)
                let methodNames = ""
                if (ml != "") {
                    const ms = ml.split(",")
                    for (m in ms) {
                        const mId = parseInt(m)
                        if (mId > 0) {
                            if (methodNames == "") { methodNames = nGetS1(mId) }
                            else { methodNames = `${methodNames},${nGetS1(mId)}` }
                        }
                    }
                }
                ifaceMethods.set(ifName, methodNames)
            }
        }
    }
    // Pass 2: check all statements
    checkStmtList(stmtList)
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
        const className = nGetS1(id)
        const implList = nGetS3(id)
        const methodsBlockId = nGetI2(id)
        // Collect class method names
        let classMethods = ","
        if (methodsBlockId > 0) {
            const ml = nGetList(methodsBlockId)
            if (ml != "") {
                const ms = ml.split(",")
                for (m in ms) {
                    const mId = parseInt(m)
                    if (mId > 0 && nGetKind(mId) == "FUNC_DECL") {
                        classMethods = `${classMethods}${nGetS1(mId)},`
                    }
                }
            }
        }
        // Verify interface implementations (uses contains to avoid i64/ptr bootstrap issue)
        if (implList != "") {
            checkInterfaceImpl(className, implList, classMethods)
        }
        // Check method bodies
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
            println(`checker error: cannot reassign const variable '${name}'`)
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
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { checkExpr(id); return }
    if (kind == "TRY") {
        pushScope()
        checkBlock(nGetI1(id))
        popScope()
        pushScope()
        defineVar(nGetS1(id), "string", 0)
        checkBlock(nGetI2(id))
        popScope()
        return
    }
    if (kind == "THROW") {
        checkExpr(nGetI1(id))
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
        const argCount = countArgs(nGetList(id))
        if (funcParamMin.has(callee) == 1) {
            const minArgs = parseInt(funcParamMin.getString(callee))
            const maxArgs = parseInt(funcParamMax.getString(callee))
            if (argCount < minArgs || argCount > maxArgs) {
                if (minArgs == maxArgs) {
                    println(`checker error: function '${callee}' expects ${minArgs} arguments, got ${argCount}`)
                } else {
                    println(`checker error: function '${callee}' expects ${minArgs}-${maxArgs} arguments, got ${argCount}`)
                }
                exit(1)
            }
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
