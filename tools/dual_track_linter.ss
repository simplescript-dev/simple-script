// tools/dual_track_linter.ss
//
// D093 双轨代码检测器 —— 守护 "一份求值逻辑" 第一性需求。
// 不可伪造指标:调用图可达性——单 kind helper 传播给 caller，提取 helper 不改变双轨数。
//
// 判断标准:comptime/runtime 双入口(如 genMethodCall vs genValCtMethodCall)
// 本身就是双轨——不是可接受的架构,是 Zig SEMA 要消灭的目标。
// 最终形态:单入口 + comptimeDepth 内部状态,所有 kind 双轨数→0。
//
// 用法: bin/ss run tools/dual_track_linter.ss

import { tokenize } from "@/bootstrap/lexer"
import { parse, nGetKind, nGetS1, nGetI1, nGetI2, nGetI3, nGetList, nGetLine } from "@/bootstrap/parser"

// ── Linter state ─────────────────────────────────────────────

// kindHandlers: Map<kind, "func|file|line|phase;func|file|line|phase;...">
let kindHandlers = new Map()
// funcEndCalls: Map<"file|func", "call1,call2,...">
let funcEndCalls = new Map()
// comptimeBranchCount: Map<file, "count">
let comptimeBranchCount = new Map()
let kindList = ""
let totalComptimeBranches = 0
let currentPhase = ""
let funcKindSet = new Map()
let funcCallKeyList = ""
let funcCallers = new Map()
let dualEntryList = ""
let funcCtDepthRefs = new Map()
let funcReachEmit = new Map()
let funcReachInterp = new Map()
let funcNameToKey = new Map()
let funcDirectBridge = new Map()
let gvBranchList = ""
let gvBranchCtGuard = new Map()
let gvBranchIsCtBranch = new Map()
let gvBranchRegBridge = new Map()
let gvBranchSharedEvals = new Map()

let gsBranchList = ""
let gsBranchCtGuard = new Map()
let gsBranchDelegate = new Map()
let gsBranchHasIsCt = new Map()
let funcHasIsCt = new Map()

let ctDepthRefList = ""
let ctDepthRefCount = 0
let funcCtDepthStructural = new Map()

// ── Phase classification ─────────────────────────────────────

function filePhase(file: string): string {
    if (file.contains("gen_") == 1) { return "codegen" }
    if (file.contains("codegen") == 1) { return "codegen" }
    if (file.contains("interp") == 1) { return "codegen" }
    if (file.contains("check") == 1) { return "checker" }
    if (file.contains("parse") == 1) { return "parser" }
    if (file.contains("lexer") == 1) { return "parser" }
    if (file.contains("lex_") == 1) { return "parser" }
    if (file.contains("pir") == 1) { return "pir" }
    return "other"
}

// ── Helpers ───────────────────────────────────────────────────

function recordKindSeen(kind: string) {
    if (kindList == "") { kindList = kind; return }
    if (setContainsExact(kindList, kind) == 1) { return }
    kindList = `${kindList},${kind}`
}

function addHandler(kind: string, funcName: string, file: string, line: int) {
    recordKindSeen(kind)
    const entry = `${funcName}|${file}|${line}|${currentPhase}`
    if (kindHandlers.has(kind) == 1) {
        kindHandlers.set(kind, `${kindHandlers.getString(kind)};${entry}`)
    } else {
        kindHandlers.set(kind, entry)
    }
    const fk = `${file}|${funcName}`
    if (funcKindSet.has(fk) == 1) {
        if (setContainsExact(funcKindSet.getString(fk), kind) != 1) {
            funcKindSet.set(fk, `${funcKindSet.getString(fk)},${kind}`)
        }
    } else {
        funcKindSet.set(fk, kind)
    }
}

function addEndCall(funcKey: string, callName: string) {
    if (funcEndCalls.has(funcKey) == 1) {
        const prev = funcEndCalls.getString(funcKey)
        if (setContainsExact(prev, callName) == 1) { return }
        funcEndCalls.set(funcKey, `${prev},${callName}`)
    } else {
        funcEndCalls.set(funcKey, callName)
        if (funcCallKeyList == "") { funcCallKeyList = funcKey } else { funcCallKeyList = `${funcCallKeyList}\n${funcKey}` }
    }
}

function bumpComptime(file: string) {
    const prev = comptimeBranchCount.has(file) == 1 ? parseInt(comptimeBranchCount.getString(file)) : 0
    comptimeBranchCount.set(file, `${prev + 1}`)
    totalComptimeBranches = totalComptimeBranches + 1
}

function bumpFuncCtDepth(file: string, funcName: string) {
    const key = `${file}|${funcName}`
    const prev = funcCtDepthRefs.has(key) == 1 ? parseInt(funcCtDepthRefs.getString(key)) : 0
    funcCtDepthRefs.set(key, `${prev + 1}`)
}

// ── AST visitor ──────────────────────────────────────────────

function visitList(listStr: string, funcName: string, file: string) {
    if (listStr == "") { return }
    const parts = listStr.split(",")
    for (p in parts) {
        if (p == "") { continue }
        const id = parseInt(p)
        if (id > 0) { visitNode(id, funcName, file) }
    }
}

function visitNode(nodeId: int, funcName: string, file: string) {
    if (nodeId <= 0) { return }
    const kind = nGetKind(nodeId)

    if (kind == "BINARY" && (nGetS1(nodeId) == "Eq" || nGetS1(nodeId) == "Ne")) {
        const leftId = nGetI1(nodeId)
        const rightId = nGetI2(nodeId)
        if (rightId > 0 && nGetKind(rightId) == "STRING_LIT") {
            let isKindCheck = 0
            if (leftId > 0) {
                const lk = nGetKind(leftId)
                if (lk == "CALL" && nGetS1(leftId) == "nGetKind") {
                    isKindCheck = 1
                } else if (lk == "METHOD_CALL" && nGetS1(leftId) == "getString") {
                    const recvId = nGetI1(leftId)
                    if (recvId > 0 && nGetKind(recvId) == "IDENT" && nGetS1(recvId) == "nKind") {
                        isKindCheck = 1
                    }
                }
            }
            if (isKindCheck == 1) {
                addHandler(nGetS1(rightId), funcName, file, nGetLine(nodeId))
            }
        }
    }

    if (kind == "CALL" || kind == "METHOD_CALL") {
        addEndCall(`${file}|${funcName}`, nGetS1(nodeId))
    }

    if (kind == "CALL" && nGetS1(nodeId) == "isCt") {
        funcHasIsCt.set(`${file}|${funcName}`, "1")
    }
    if (kind == "CALL" && nGetS1(nodeId) == "interpShouldStop") {
        funcCtDepthStructural.set(`${file}|${funcName}`, "1")
    }

    if (kind == "ASSIGN" && nGetS1(nodeId) == "comptimeDepth") {
        funcCtDepthStructural.set(`${file}|${funcName}`, "1")
    }

    if (kind == "IDENT" && nGetS1(nodeId) == "comptimeDepth") {
        bumpComptime(file)
        bumpFuncCtDepth(file, funcName)
        const ctdLine = nGetLine(nodeId)
        const ctdEntry = `${file}|${funcName}|${ctdLine}`
        if (ctDepthRefList == "") { ctDepthRefList = ctdEntry }
        else { ctDepthRefList = `${ctDepthRefList}\n${ctdEntry}` }
        ctDepthRefCount = ctDepthRefCount + 1
    }

    visitChildren(nodeId, kind, funcName, file)
}

function visitChildren(nodeId: int, kind: string, funcName: string, file: string) {
    if (kind == "IDENT" || kind == "STRING_LIT" || kind == "INT_LIT" || kind == "DOUBLE_LIT") { return }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT" || kind == "NULL_LIT") { return }
    if (kind == "THIS" || kind == "SUPER") { return }

    if (kind == "BLOCK" || kind == "PROGRAM") { visitList(nGetList(nodeId), funcName, file); return }
    if (kind == "CALL" || kind == "NEW_EXPR" || kind == "ARRAY_LIT") { visitList(nGetList(nodeId), funcName, file); return }
    if (kind == "TEMPLATE_LIT" || kind == "OBJ_LITERAL") { visitList(nGetList(nodeId), funcName, file); return }
    if (kind == "ANNOTATION_LIST") { visitList(nGetList(nodeId), funcName, file); return }

    if (kind == "METHOD_CALL") {
        visitNode(nGetI1(nodeId), funcName, file)
        visitList(nGetList(nodeId), funcName, file)
        return
    }

    if (kind == "BINARY" || kind == "INDEX_ACCESS" || kind == "WHILE" || kind == "FOR_IN" || kind == "FOR_OF" || kind == "ASSIGN" || kind == "COMPOUND_ASSIGN" || kind == "SWITCH_CASE" || kind == "DO_WHILE") {
        visitNode(nGetI1(nodeId), funcName, file)
        visitNode(nGetI2(nodeId), funcName, file)
        return
    }

    if (kind == "IF" || kind == "TERNARY" || kind == "TRY") {
        visitNode(nGetI1(nodeId), funcName, file)
        visitNode(nGetI2(nodeId), funcName, file)
        visitNode(nGetI3(nodeId), funcName, file)
        return
    }

    if (kind == "UNARY" || kind == "GROUPING" || kind == "RETURN" || kind == "MEMBER_ACCESS" || kind == "VAR_DECL" || kind == "COMPTIME_EXPR" || kind == "COMPTIME_EMIT" || kind == "TYPEINFO_EXPR" || kind == "EXPR_STMT" || kind == "THROW") {
        visitNode(nGetI1(nodeId), funcName, file)
        return
    }

    if (kind == "CATCH") {
        visitNode(nGetI2(nodeId), funcName, file)
        return
    }

    if (kind == "SWITCH") {
        visitNode(nGetI1(nodeId), funcName, file)
        visitList(nGetList(nodeId), funcName, file)
        return
    }

    // Fallback: try I1/I2/I3 (safe: leaf ints like isOptional won't cause harm)
    const i1 = nGetI1(nodeId)
    const i2 = nGetI2(nodeId)
    const i3 = nGetI3(nodeId)
    if (i1 > 0) { visitNode(i1, funcName, file) }
    if (i2 > 0) { visitNode(i2, funcName, file) }
    if (i3 > 0) { visitNode(i3, funcName, file) }
}

// ── Subtree search helpers (for operand-driven audit) ───────

function subtreeHasIdent(nid: int, name: string): int {
    if (nid <= 0) { return 0 }
    const k = nGetKind(nid)
    if (k == "IDENT" && nGetS1(nid) == name) { return 1 }
    if (k == "STRING_LIT" || k == "INT_LIT" || k == "DOUBLE_LIT") { return 0 }
    if (k == "TRUE_LIT" || k == "FALSE_LIT" || k == "NULL_LIT") { return 0 }
    if (nGetI1(nid) > 0 && subtreeHasIdent(nGetI1(nid), name) == 1) { return 1 }
    if (nGetI2(nid) > 0 && subtreeHasIdent(nGetI2(nid), name) == 1) { return 1 }
    if (nGetI3(nid) > 0 && subtreeHasIdent(nGetI3(nid), name) == 1) { return 1 }
    const lst = nGetList(nid)
    if (lst != "") {
        const lParts = lst.split(",")
        for (lp in lParts) {
            const lid = parseInt(lp)
            if (lid > 0 && subtreeHasIdent(lid, name) == 1) { return 1 }
        }
    }
    return 0
}

function subtreeHasCall(nid: int, fname: string): int {
    if (nid <= 0) { return 0 }
    const k = nGetKind(nid)
    if (k == "CALL" && nGetS1(nid) == fname) { return 1 }
    if (k == "STRING_LIT" || k == "INT_LIT" || k == "DOUBLE_LIT" || k == "IDENT") { return 0 }
    if (k == "TRUE_LIT" || k == "FALSE_LIT" || k == "NULL_LIT") { return 0 }
    if (nGetI1(nid) > 0 && subtreeHasCall(nGetI1(nid), fname) == 1) { return 1 }
    if (nGetI2(nid) > 0 && subtreeHasCall(nGetI2(nid), fname) == 1) { return 1 }
    if (nGetI3(nid) > 0 && subtreeHasCall(nGetI3(nid), fname) == 1) { return 1 }
    const lst = nGetList(nid)
    if (lst != "") {
        const lParts = lst.split(",")
        for (lp in lParts) {
            const lid = parseInt(lp)
            if (lid > 0 && subtreeHasCall(lid, fname) == 1) { return 1 }
        }
    }
    return 0
}

function collectKindsFromCond(condId: int, result: string): string {
    if (condId <= 0) { return result }
    if (nGetKind(condId) != "BINARY") { return result }
    const op = nGetS1(condId)
    if (op == "Eq") {
        const li = nGetI1(condId)
        const ri = nGetI2(condId)
        if (li > 0 && ri > 0 && nGetKind(li) == "IDENT" && nGetS1(li) == "kind" && nGetKind(ri) == "STRING_LIT") {
            const kn = nGetS1(ri)
            if (result == "") { return kn }
            return `${result};${kn}`
        }
        return result
    }
    let r = collectKindsFromCond(nGetI1(condId), result)
    r = collectKindsFromCond(nGetI2(condId), r)
    return r
}

function analyzeKindBody(kindName: string, thenId: int) {
    if (thenId <= 0) { return }
    let stmts = ""
    if (nGetKind(thenId) == "BLOCK") { stmts = nGetList(thenId) }
    else { stmts = `${thenId}` }
    if (stmts == "") { return }
    const parts = stmts.split(",")
    let seenCtGuard = 0
    let sharedCount = 0
    for (sp in parts) {
        const sid = parseInt(sp)
        if (sid <= 0) { continue }
        if (nGetKind(sid) == "IF" && subtreeHasIdent(nGetI1(sid), "comptimeDepth") == 1) {
            gvBranchCtGuard.set(kindName, "1")
            seenCtGuard = 1
            if (subtreeHasCall(sid, "isCt") == 1) {
                gvBranchIsCtBranch.set(kindName, "1")
            }
            continue
        }
        if (subtreeHasCall(sid, "isCt") == 1) {
            gvBranchIsCtBranch.set(kindName, "1")
        }
        if (seenCtGuard == 0 && (subtreeHasCall(sid, "genVal") == 1 || subtreeHasCall(sid, "genExpr") == 1)) {
            sharedCount = sharedCount + 1
        }
        if (subtreeHasCall(sid, "reg") == 1) {
            gvBranchRegBridge.set(kindName, "1")
        }
    }
    gvBranchSharedEvals.set(kindName, `${sharedCount}`)
}

function analyzeGenValBranches(bodyId: int) {
    if (bodyId <= 0 || nGetKind(bodyId) != "BLOCK") { return }
    const stmtList = nGetList(bodyId)
    if (stmtList == "") { return }
    const stmts = stmtList.split(",")
    for (s in stmts) {
        const sid = parseInt(s)
        if (sid <= 0 || nGetKind(sid) != "IF") { continue }
        const condId = nGetI1(sid)
        if (condId <= 0 || nGetKind(condId) != "BINARY" || nGetS1(condId) != "Eq") { continue }
        const leftId = nGetI1(condId)
        const rightId = nGetI2(condId)
        if (leftId <= 0 || rightId <= 0) { continue }
        if (nGetKind(leftId) != "IDENT" || nGetS1(leftId) != "kind") { continue }
        if (nGetKind(rightId) != "STRING_LIT") { continue }
        const kindName = nGetS1(rightId)
        if (gvBranchList == "") { gvBranchList = kindName }
        else { gvBranchList = `${gvBranchList};${kindName}` }
        analyzeKindBody(kindName, nGetI2(sid))
    }
}

// ── genStmt branch analysis ─────────────────────────────────

function analyzeStmtKindBody(kindName: string, thenId: int) {
    if (thenId <= 0) { return }
    let stmts = ""
    if (nGetKind(thenId) == "BLOCK") { stmts = nGetList(thenId) }
    else { stmts = `${thenId}` }
    if (stmts == "") { return }
    const parts = stmts.split(",")
    for (sp in parts) {
        const sid = parseInt(sp)
        if (sid <= 0) { continue }
        if (nGetKind(sid) == "IF" && subtreeHasIdent(nGetI1(sid), "comptimeDepth") == 1) {
            gsBranchCtGuard.set(kindName, "1")
        }
        if (subtreeHasCall(sid, "isCt") == 1) {
            gsBranchHasIsCt.set(kindName, "1")
        }
        if (nGetKind(sid) == "EXPR_STMT") {
            const esId = nGetI1(sid)
            if (esId > 0 && nGetKind(esId) == "CALL") {
                const cn = nGetS1(esId)
                if (cn.startsWith("gen") == 1 || cn.startsWith("run") == 1 || cn.startsWith("register") == 1) {
                    if (gsBranchDelegate.has(kindName) != 1) {
                        gsBranchDelegate.set(kindName, cn)
                    }
                }
            }
        }
    }
}

function analyzeGenStmtBranches(bodyId: int) {
    if (bodyId <= 0 || nGetKind(bodyId) != "BLOCK") { return }
    const stmtList = nGetList(bodyId)
    if (stmtList == "") { return }
    const stmts = stmtList.split(",")
    for (s in stmts) {
        const sid = parseInt(s)
        if (sid <= 0 || nGetKind(sid) != "IF") { continue }
        const condId = nGetI1(sid)
        if (condId <= 0) { continue }
        const kindNames = collectKindsFromCond(condId, "")
        if (kindNames == "") { continue }
        const knParts = kindNames.split(";")
        for (kn in knParts) {
            if (kn == "") { continue }
            if (gsBranchList == "") { gsBranchList = kn }
            else if ((`${gsBranchList};`).contains(`${kn};`) != 1) { gsBranchList = `${gsBranchList};${kn}` }
            analyzeStmtKindBody(kn, nGetI2(sid))
        }
    }
}

// ── File scanning ────────────────────────────────────────────

let fileList = ""
let fileCount = 0

function collectSSFiles(dir: string) {
    const entries = listDir(dir)
    if (entries == "") { return }
    const parts = entries.split("\n")
    for (entry in parts) {
        if (entry == "") { continue }
        if (entry.endsWith(".ss") == 1) {
            const path = `${dir}/${entry}`
            if (fileList == "") { fileList = path } else { fileList = `${fileList}\n${path}` }
            fileCount = fileCount + 1
        }
    }
}

function processFile(path: string) {
    currentPhase = filePhase(path)
    const source = readFile(path)
    tokenize(source)
    const rootId = parse("done")
    const topList = nGetList(rootId)
    if (topList == "") { return }
    const parts = topList.split(",")
    for (p in parts) {
        if (p == "") { continue }
        const stmtId = parseInt(p)
        if (stmtId <= 0) { continue }
        if (nGetKind(stmtId) == "FUNC_DECL") {
            const fname = nGetS1(stmtId)
            if (fname.startsWith("genValCt") == 1) {
                const deEntry = `${fname}|${path}`
                if (dualEntryList == "") { dualEntryList = deEntry } else { dualEntryList = `${dualEntryList};${deEntry}` }
            }
            const body = nGetI1(stmtId)
            if (fname == "genVal" && path.contains("gen_exprs") == 1) {
                analyzeGenValBranches(body)
            }
            if (fname == "genStmt" && path.contains("gen_stmts") == 1) {
                analyzeGenStmtBranches(body)
            }
            if (body > 0) { visitNode(body, fname, path) }
        }
    }
}

// ── Output ───────────────────────────────────────────────────

function countEntries(s: string): int {
    let c = 1
    let i = 0
    while (i < s.length()) {
        if (s.charAt(i) == ";") { c = c + 1 }
        i = i + 1
    }
    return c
}

function padRight(s: string, width: int): string {
    let out = s
    while (out.length() < width) { out = `${out} ` }
    return out
}

function filterByPhase(entries: string, phase: string): string {
    let result = ""
    const parts = entries.split(";")
    for (p in parts) {
        if (p == "") { continue }
        if (p.endsWith(`|${phase}`) == 1) {
            if (result == "") { result = p } else { result = `${result};${p}` }
        }
    }
    return result
}

function formatEntry(entry: string): string {
    const segs = entry.split("|")
    if (segs[2] == "0") { return `${segs[0]}@${segs[1]}(propagated)` }
    return `${segs[0]}@${segs[1]}:${segs[2]}`
}

function formatEntries(entries: string): string {
    let result = ""
    const parts = entries.split(";")
    for (p in parts) {
        if (p == "") { continue }
        if (result == "") { result = formatEntry(p) } else { result = `${result}, ${formatEntry(p)}` }
    }
    return result
}

function setContainsExact(s: string, elem: string): int {
    return ((`${s},`).contains(`${elem},`) == 1) ? 1 : 0
}

function setContainsPrefix(s: string, prefix: string): int {
    const parts = s.split(",")
    for (p in parts) {
        if (p == "") { continue }
        if (p.startsWith(prefix) == 1) { return 1 }
    }
    return 0
}

function checkEndTrackSplit(entries: string): int {
    let anyEmit = 0
    let anyInterp = 0
    const hParts = entries.split(";")
    for (hp in hParts) {
        if (hp == "") { continue }
        const segs = hp.split("|")
        const funcKey = `${segs[1]}|${segs[0]}`
        const calls = funcEndCalls.has(funcKey) == 1 ? funcEndCalls.getString(funcKey) : ""
        if (setContainsExact(calls, "emitIR") == 1) { anyEmit = 1 }
        if (setContainsPrefix(calls, "interp") == 1) { anyInterp = 1 }
    }
    return (anyEmit == 1 && anyInterp == 1) ? 1 : 0
}

function entryListHasFunc(entries: string, funcName: string, file: string): int {
    const parts = entries.split(";")
    for (p in parts) {
        if (p == "") { continue }
        const segs = p.split("|")
        if (segs[0] == funcName && segs[1] == file) { return 1 }
    }
    return 0
}

function buildCallerGraph() {
    if (funcCallKeyList == "") { return }
    const keys = funcCallKeyList.split("\n")
    for (key in keys) {
        if (key == "") { continue }
        const kParts = key.split("|")
        const callerFile = kParts[0]
        const callerFunc = kParts[1]
        const calls = funcEndCalls.getString(key)
        const callParts = calls.split(",")
        for (callName in callParts) {
            if (callName == "") { continue }
            const callerEntry = `${callerFunc}|${callerFile}`
            if (funcCallers.has(callName) == 1) {
                const prev = funcCallers.getString(callName)
                if ((`${prev}\n`).contains(`${callerEntry}\n`) != 1) {
                    funcCallers.set(callName, `${prev}\n${callerEntry}`)
                }
            } else {
                funcCallers.set(callName, callerEntry)
            }
        }
    }
}

function propagateHandlers() {
    buildCallerGraph()
    const kinds = kindList.split(",")
    for (k in kinds) {
        if (k == "") { continue }
        if (kindHandlers.has(k) != 1) { continue }
        let entries = kindHandlers.getString(k)
        let propagated = ""
        let changed = 1
        let iters = 0
        while (changed == 1 && iters < 10) {
            changed = 0
            iters = iters + 1
            let newEntries = ""
            const parts = entries.split(";")
            for (p in parts) {
                if (p == "") { continue }
                const segs = p.split("|")
                const funcName = segs[0]
                const file = segs[1]
                const fk = `${file}|${funcName}`
                let isSingle = 0
                if (propagated == "" || (`\n${propagated}\n`).contains(`\n${fk}\n`) != 1) {
                    if (funcKindSet.has(fk) == 1) {
                        const kindSetStr = funcKindSet.getString(fk)
                        if (kindSetStr.contains(",") != 1 && kindSetStr == k) {
                            isSingle = 1
                        }
                    }
                }
                if (isSingle == 1 && funcCallers.has(funcName) == 1) {
                    changed = 1
                    if (propagated == "") { propagated = fk } else { propagated = `${propagated}\n${fk}` }
                    const callers = funcCallers.getString(funcName)
                    const callerParts = callers.split("\n")
                    for (cp in callerParts) {
                        if (cp == "") { continue }
                        const cSegs = cp.split("|")
                        const callerFunc = cSegs[0]
                        const callerFile = cSegs[1]
                        const callerPhase = filePhase(callerFile)
                        const callerEntry = `${callerFunc}|${callerFile}|0|${callerPhase}`
                        if (newEntries == "") {
                            newEntries = callerEntry
                        } else if (entryListHasFunc(newEntries, callerFunc, callerFile) != 1) {
                            newEntries = `${newEntries};${callerEntry}`
                        }
                    }
                } else {
                    if (newEntries == "") { newEntries = p } else { newEntries = `${newEntries};${p}` }
                }
            }
            entries = newEntries
        }
        kindHandlers.set(k, entries)
    }
}

function printHeatmap() {
    println("=== Codegen Dual-Track Heatmap ===")
    println("(only gen_*.ss / codegen.ss handlers — the actual dual-track zone)")
    println("")
    let codegenDualCount = 0
    let codegenEndSplitCount = 0
    let allDualCount = 0
    const kinds = kindList.split(",")
    for (k in kinds) {
        if (k == "") { continue }
        const allEntries = kindHandlers.getString(k)
        const cgEntries = filterByPhase(allEntries, "codegen")
        const cgCount = cgEntries != "" ? countEntries(cgEntries) : 0
        const allCount = countEntries(allEntries)
        if (allCount >= 2) { allDualCount = allDualCount + 1 }
        if (cgCount >= 2) {
            let line = `${padRight(k, 18)}: ${cgCount} codegen handlers`
            line = `${line}  [${formatEntries(cgEntries)}]`
            codegenDualCount = codegenDualCount + 1
            if (checkEndTrackSplit(cgEntries) == 1) {
                line = `${line}  *END-SPLIT*`
                codegenEndSplitCount = codegenEndSplitCount + 1
            }
            println(line)
        } else if (cgCount == 1) {
            println(`${padRight(k, 18)}: 1 codegen handler  (OK)`)
        }
    }
    println("")
    println("=== Totals ===")
    println(`codegen 双轨 kinds : ${codegenDualCount}   (理想: 0)`)
    println(`  末端双轨 kinds   : ${codegenEndSplitCount}   (emitIR vs interp* 不相交)`)
    println(`全阶段双轨 kinds   : ${allDualCount}   (含 checker/parser,仅参考)`)
    println(`comptimeDepth 命中 : ${totalComptimeBranches}   (codegen 阶段 IDENT 引用)`)
    println("")
    println("=== comptimeDepth 文件分布 ===")
    const fParts = fileList.split("\n")
    for (f in fParts) {
        if (f == "") { continue }
        if (comptimeBranchCount.has(f) == 1) {
            println(`  ${f} : ${comptimeBranchCount.getString(f)}`)
        }
    }
}

function printZigConformance() {
    println("")
    println("=== Zig SEMA Conformance — genVal Single-Entry Audit ===")
    println("(genValCt* ↔ gen* 配对: 不可伪造分类确认分裂,目标合并为 direct bridge)")
    println("")
    if (dualEntryList == "") {
        println("  无 genValCt* 函数 —— genVal 完全 Zig 合规!")
        println("")
        return
    }
    const entries = dualEntryList.split(";")
    let count = 0
    for (e in entries) {
        if (e == "") { continue }
        count = count + 1
        const segs = e.split("|")
        const fname = segs[0]
        const file = segs[1]
        const ctKey = `${file}|${fname}`
        const ctClass = getFuncClass(ctKey)
        const suffix = fname.substring(8, fname.length() - 8)
        const rtName = `gen${suffix}`
        let rtClass = "?"
        if (funcNameToKey.has(rtName) == 1) {
            rtClass = getFuncClass(funcNameToKey.getString(rtName))
        }
        println(`  ${padRight(fname, 24)} [${ctClass}] ↔ ${padRight(rtName, 20)} [${rtClass}]`)
    }
    const genValKey = "bootstrap/gen_exprs.ss|genVal"
    let genValClass = "?"
    if (funcNameToKey.has("genVal") == 1) {
        genValClass = getFuncClass(funcNameToKey.getString("genVal"))
    }
    let genValCtRefs = 0
    if (funcCtDepthRefs.has(genValKey) == 1) {
        genValCtRefs = parseInt(funcCtDepthRefs.getString(genValKey))
    }
    const inlineCount = genValCtRefs - count
    println("")
    println(`  genVal dispatcher: [${genValClass}]  ctDepth×${genValCtRefs} (内联:${inlineCount} 分发:${count})`)
    println(`  待合并配对: ${count} (Zig 目标: 0)`)
}

// ── Unfakeable Metrics — Call Graph Topology ──────────────────

function buildNameToKeyMap() {
    if (funcCallKeyList == "") { return }
    const keys = funcCallKeyList.split("\n")
    for (nk in keys) {
        if (nk == "") { continue }
        const kp = nk.split("|")
        if (funcNameToKey.has(kp[1]) != 1) {
            funcNameToKey.set(kp[1], nk)
        }
    }
}

function computeReachability() {
    if (funcCallKeyList == "") { return }
    const allKeys = funcCallKeyList.split("\n")
    for (fk in allKeys) {
        if (fk == "") { continue }
        const kp = fk.split("|")
        if (kp[1] == "emitIR") { funcReachEmit.set(fk, "1") }
        if (kp[1].startsWith("interp") == 1) { funcReachInterp.set(fk, "1") }
        if (funcEndCalls.has(fk) != 1) { continue }
        const calls = funcEndCalls.getString(fk)
        if (setContainsExact(calls, "emitIR") == 1) { funcReachEmit.set(fk, "1") }
        if (setContainsPrefix(calls, "interp") == 1) { funcReachInterp.set(fk, "1") }
        if (setContainsExact(calls, "emitIR") == 1 && setContainsPrefix(calls, "interp") == 1) {
            funcDirectBridge.set(fk, "1")
        }
    }
    let changed = 1
    let iters = 0
    while (changed == 1 && iters < 30) {
        changed = 0
        iters = iters + 1
        for (fk in allKeys) {
            if (fk == "") { continue }
            if (funcEndCalls.has(fk) != 1) { continue }
            const calls = funcEndCalls.getString(fk)
            const cParts = calls.split(",")
            for (cn in cParts) {
                if (cn == "") { continue }
                if (funcNameToKey.has(cn) != 1) { continue }
                const ck = funcNameToKey.getString(cn)
                if (funcReachEmit.has(ck) == 1 && funcReachEmit.has(fk) != 1) {
                    funcReachEmit.set(fk, "1")
                    changed = 1
                }
                if (funcReachInterp.has(ck) == 1 && funcReachInterp.has(fk) != 1) {
                    funcReachInterp.set(fk, "1")
                    changed = 1
                }
            }
        }
    }
}

function getFuncClass(key: string): string {
    const re = funcReachEmit.has(key) == 1 ? 1 : 0
    const ri = funcReachInterp.has(key) == 1 ? 1 : 0
    if (re == 1 && ri == 1) {
        if (funcDirectBridge.has(key) == 1) { return "direct" }
        return "bridge"
    }
    if (re == 1) { return "emit" }
    if (ri == 1) { return "interp" }
    return "none"
}

function collectUnionCgCallees(startKeys: string): string {
    if (startKeys == "") { return "" }
    let result = ""
    let rMap = new Map()
    let visited = new Map()
    let frontier = startKeys
    const sParts = startKeys.split("\n")
    for (sp in sParts) { if (sp != "") { visited.set(sp, "1") } }
    while (frontier != "") {
        let nextFrontier = ""
        const fParts = frontier.split("\n")
        for (fk in fParts) {
            if (fk == "") { continue }
            if (funcEndCalls.has(fk) != 1) { continue }
            const calls = funcEndCalls.getString(fk)
            const cParts = calls.split(",")
            for (cn in cParts) {
                if (cn == "") { continue }
                if (funcNameToKey.has(cn) != 1) { continue }
                const nk = funcNameToKey.getString(cn)
                if (filePhase(nk) == "codegen" && rMap.has(cn) != 1) {
                    rMap.set(cn, "1")
                    if (result == "") { result = cn } else { result = `${result},${cn}` }
                }
                if (visited.has(nk) != 1) {
                    visited.set(nk, "1")
                    if (nextFrontier == "") { nextFrontier = nk } else { nextFrontier = `${nextFrontier}\n${nk}` }
                }
            }
        }
        frontier = nextFrontier
    }
    return result
}

function setIntersect(a: string, b: string): string {
    if (a == "" || b == "") { return "" }
    let result = ""
    const parts = a.split(",")
    for (p in parts) {
        if (p == "") { continue }
        if (setContainsExact(b, p) == 1) {
            if (result == "") { result = p } else { result = `${result},${p}` }
        }
    }
    return result
}

function setSize(s: string): int {
    if (s == "") { return 0 }
    let c = 0
    const parts = s.split(",")
    for (p in parts) { if (p != "") { c = c + 1 } }
    return c
}

function printUnfakeableMetrics() {
    println("")
    println("=== Unfakeable Metrics — Call Graph Topology ===")
    println("(基于 emitIR/interp* 传递闭包,不依赖命名约定)")
    println("")
    let totalCg = 0
    let directCount = 0
    let transitiveCount = 0
    let emitOnlyCount = 0
    let interpOnlyCount = 0
    let noneCount = 0
    let directList = ""
    const allKeys = funcCallKeyList.split("\n")
    for (fk in allKeys) {
        if (fk == "") { continue }
        if (filePhase(fk) != "codegen") { continue }
        totalCg = totalCg + 1
        const cls = getFuncClass(fk)
        if (cls == "direct") {
            directCount = directCount + 1
            const dkp = fk.split("|")
            if (directList == "") { directList = dkp[1] } else { directList = `${directList},${dkp[1]}` }
        }
        else if (cls == "bridge") { transitiveCount = transitiveCount + 1 }
        else if (cls == "emit") { emitOnlyCount = emitOnlyCount + 1 }
        else if (cls == "interp") { interpOnlyCount = interpOnlyCount + 1 }
        else { noneCount = noneCount + 1 }
    }
    println("Metric 1: Terminal Reachability (codegen 函数)")
    println(`  direct bridge:             ${directCount}   (body 直接含 emitIR + interp*)`)
    println(`  transitive bridge:         ${transitiveCount}   (仅通过调用链到达两端)`)
    println(`  runtime-only (emitIR):     ${emitOnlyCount}`)
    println(`  comptime-only (interp*):   ${interpOnlyCount}`)
    println(`  neutral:                   ${noneCount}`)
    println(`  total:                     ${totalCg}`)
    if (directList != "") {
        println(`  direct bridge 函数: ${directList}`)
    }
    println("")
    println("Metric 2+3: Per-Kind Fork Depth + Path Intersection (END-SPLIT kinds)")
    println("")
    const kinds = kindList.split(",")
    for (k in kinds) {
        if (k == "") { continue }
        if (kindHandlers.has(k) != 1) { continue }
        const cgEntries = filterByPhase(kindHandlers.getString(k), "codegen")
        if (cgEntries == "" || countEntries(cgEntries) < 2) { continue }
        if (checkEndTrackSplit(cgEntries) != 1) { continue }
        let eKeys = ""
        let iKeys = ""
        let dCount = 0
        let tCount = 0
        const hParts = cgEntries.split(";")
        for (hp in hParts) {
            if (hp == "") { continue }
            const segs = hp.split("|")
            const hKey = `${segs[1]}|${segs[0]}`
            const cls = getFuncClass(hKey)
            if (cls == "direct") { dCount = dCount + 1 }
            else if (cls == "bridge") { tCount = tCount + 1 }
            else if (cls == "emit") { if (eKeys == "") { eKeys = hKey } else { eKeys = `${eKeys}\n${hKey}` } }
            else if (cls == "interp") { if (iKeys == "") { iKeys = hKey } else { iKeys = `${iKeys}\n${hKey}` } }
        }
        const eReach = collectUnionCgCallees(eKeys)
        const iReach = collectUnionCgCallees(iKeys)
        const inter = setIntersect(eReach, iReach)
        const iSize = setSize(inter)
        let iNames = ""
        if (iSize > 0) {
            const iParts = inter.split(",")
            let shown = 0
            for (ip in iParts) {
                if (ip == "" || shown >= 5) { continue }
                if (iNames == "") { iNames = ip } else { iNames = `${iNames},${ip}` }
                shown = shown + 1
            }
            if (iSize > 5) { iNames = `${iNames},...` }
        }
        println(`  ${padRight(k, 18)} direct:${dCount} trans:${tCount}  共享:|${iSize}|  {${iNames}}`)
    }
}

function printOperandDrivenAudit() {
    if (gvBranchList == "") { return }
    println("")
    println("=== Zig SEMA 操作数驱动审计 (genVal 逐 kind) ===")
    println("(不可伪造: genVal/genExpr 求值位置 vs comptimeDepth 守卫位置)")
    println("(共享求值=守卫前调 genVal; isCt=操作数驱动分叉; reg=ct→rt 桥接)")
    println("")
    const branches = gvBranchList.split(";")
    let dualCount = 0
    let zigCount = 0
    let simpleCount = 0
    let dualKinds = ""
    let zigKinds = ""
    for (b in branches) {
        if (b == "") { continue }
        const hasGuard = gvBranchCtGuard.has(b) == 1 ? 1 : 0
        const hasIsCt = gvBranchIsCtBranch.has(b) == 1 ? 1 : 0
        const hasReg = gvBranchRegBridge.has(b) == 1 ? 1 : 0
        let shared = 0
        if (gvBranchSharedEvals.has(b) == 1) { shared = parseInt(gvBranchSharedEvals.getString(b)) }
        let cls = "simple"
        if (hasGuard == 1 && hasIsCt == 0) { cls = "dual" }
        else if (hasIsCt == 1 || hasReg == 1) { cls = "zig" }
        else if (hasGuard == 1) { cls = "dual" }
        let guardStr = "-"
        if (hasGuard == 1) { guardStr = "ctDepth" }
        let isCtStr = "-"
        if (hasIsCt == 1) { isCtStr = "Y" }
        let regStr = "-"
        if (hasReg == 1) { regStr = "Y" }
        if (cls == "dual") {
            dualCount = dualCount + 1
            if (dualKinds == "") { dualKinds = b } else { dualKinds = `${dualKinds} ${b}` }
            println(`  ${padRight(b, 20)} 守卫:${padRight(guardStr, 8)} 共享:${shared}  isCt:${isCtStr}  reg:${regStr}  → ${cls}`)
        } else if (cls == "zig") {
            zigCount = zigCount + 1
            if (zigKinds == "") { zigKinds = b } else { zigKinds = `${zigKinds} ${b}` }
            println(`  ${padRight(b, 20)} 守卫:${padRight(guardStr, 8)} 共享:${shared}  isCt:${isCtStr}  reg:${regStr}  → ${cls}`)
        } else {
            simpleCount = simpleCount + 1
        }
    }
    println("")
    println(`  dual (comptimeDepth 驱动): ${dualCount}   ← 反模式, 目标: 0`)
    println(`  zig (isCt + reg 驱动):     ${zigCount}   ← 正模式`)
    println(`  simple (无 ct 处理):        ${simpleCount}`)
    if (dualCount + zigCount > 0) {
        const total = dualCount + zigCount
        const pct = zigCount * 100 / total
        println(`  转化率: ${pct}% (${zigCount}/${total})`)
    }
}

// ── genStmt handler audit ───────────────────────────────────

function classifyStmtKind(kindName: string): string {
    const hasGuard = gsBranchCtGuard.has(kindName) == 1 ? 1 : 0
    const hasIsCt = gsBranchHasIsCt.has(kindName) == 1 ? 1 : 0
    let delReachEmit = 0
    let delCtDepth = 0
    let delIsCt = 0
    if (gsBranchDelegate.has(kindName) == 1) {
        const delName = gsBranchDelegate.getString(kindName)
        if (funcNameToKey.has(delName) == 1) {
            const delKey = funcNameToKey.getString(delName)
            delReachEmit = funcReachEmit.has(delKey) == 1 ? 1 : 0
            delCtDepth = funcCtDepthRefs.has(delKey) == 1 ? parseInt(funcCtDepthRefs.getString(delKey)) : 0
            delIsCt = funcHasIsCt.has(delKey) == 1 ? 1 : 0
        }
    }
    if (hasIsCt == 1 || delIsCt == 1) { return "zig" }
    if (hasGuard == 1 || delCtDepth > 0) { return "dual" }
    if (delReachEmit == 1) { return "missing" }
    return "simple"
}

function printStmtHandlerAudit() {
    if (gsBranchList == "") { return }
    println("")
    println("=== Zig SEMA 语句处理审计 (genStmt 逐 kind) ===")
    println("(物理指标: emitIR 可达性, interp* 可达性, comptimeDepth 引用, isCt 调用)")
    println("(指标不可被函数重命名或嵌套深度规避)")
    println("")
    const branches = gsBranchList.split(";")
    let missingCount = 0
    let dualCount = 0
    let zigCount = 0
    let simpleCount = 0
    let missingKinds = ""
    for (b in branches) {
        if (b == "") { continue }
        const cls = classifyStmtKind(b)
        const hasGuard = gsBranchCtGuard.has(b) == 1 ? "ctDepth" : "-"
        const hasIsCt = gsBranchHasIsCt.has(b) == 1 ? "Y" : "-"
        let delInfo = "-"
        if (gsBranchDelegate.has(b) == 1) {
            const delName = gsBranchDelegate.getString(b)
            let delClass = "?"
            let delCtD = 0
            let delIsCtStr = "-"
            if (funcNameToKey.has(delName) == 1) {
                const delKey = funcNameToKey.getString(delName)
                delClass = getFuncClass(delKey)
                delCtD = funcCtDepthRefs.has(delKey) == 1 ? parseInt(funcCtDepthRefs.getString(delKey)) : 0
                delIsCtStr = funcHasIsCt.has(delKey) == 1 ? "Y" : "-"
            }
            delInfo = `${delName}[${delClass},ctD:${delCtD},isCt:${delIsCtStr}]`
        }
        if (cls == "missing") {
            missingCount = missingCount + 1
            if (missingKinds == "") { missingKinds = b } else { missingKinds = `${missingKinds} ${b}` }
        } else if (cls == "dual") {
            dualCount = dualCount + 1
        } else if (cls == "zig") {
            zigCount = zigCount + 1
        } else {
            simpleCount = simpleCount + 1
        }
        println(`  ${padRight(b, 22)} 守卫:${padRight(hasGuard, 8)} isCt:${hasIsCt}  委托:${padRight(delInfo, 45)} → ${cls}`)
    }
    println("")
    println(`  missing (无 comptime 路径): ${missingCount}   ← 需要实现`)
    println(`  dual (comptimeDepth 驱动):  ${dualCount}`)
    println(`  zig (isCt 驱动):            ${zigCount}   ← 正模式`)
    println(`  simple (无 RT 效果):         ${simpleCount}`)
    if (missingKinds != "") {
        println(`  missing kinds: ${missingKinds}`)
    }
}

function printCtDepthRefAudit() {
    println("")
    println("=== comptimeDepth 逐条引用审计 ===")
    println("(分类: coexist=函数内已有 isCt 共存, structural=声明/模式入口, replaceable=可替换为 isCt)")
    println("")
    if (ctDepthRefList == "") { println("  (无引用)"); return }
    const refs = ctDepthRefList.split("\n")
    let coexistCount = 0
    let structuralCount = 0
    let replaceableCount = 0
    for (r in refs) {
        if (r == "") { continue }
        const rParts = r.split("|")
        if (rParts.length() < 3) { continue }
        const rFile = rParts[0]
        const rFunc = rParts[1]
        const rLine = rParts[2]
        const rKey = `${rFile}|${rFunc}`
        const hasIsCt = funcHasIsCt.has(rKey) == 1
        const reachEmit = funcReachEmit.has(rKey) == 1
        const reachInterp = funcReachInterp.has(rKey) == 1
        const isWriter = funcCtDepthStructural.has(rKey) == 1
        let cls = ""
        if (hasIsCt) {
            cls = "coexist"
            coexistCount = coexistCount + 1
        } else if (isWriter || reachEmit == false || reachInterp == false) {
            cls = "structural"
            structuralCount = structuralCount + 1
        } else {
            cls = "replaceable"
            replaceableCount = replaceableCount + 1
        }
        const shortFile = rFile.contains("/") == 1 ? rFile.split("/")[rFile.split("/").length() - 1] : rFile
        println(`  ${padRight(shortFile, 20)} ${padRight(rFunc, 28)} L${padRight(rLine, 5)} → ${cls}`)
    }
    println("")
    println(`  coexist (isCt 共存):    ${coexistCount}   ← 已是 zig 内部守卫`)
    println(`  structural (声明/入口): ${structuralCount}   ← comptimeDepth 正确`)
    println(`  replaceable (可替换):   ${replaceableCount}   ← 下一步工作目标`)
    println(`  total:                  ${ctDepthRefCount}`)
}

function main() {
    collectSSFiles("bootstrap")
    collectSSFiles("bootstrap/eval")
    println(`Scanning ${fileCount} bootstrap files...`)
    const files = fileList.split("\n")
    for (f in files) {
        if (f == "") { continue }
        processFile(f)
    }
    println("")
    propagateHandlers()
    buildNameToKeyMap()
    computeReachability()
    printHeatmap()
    printZigConformance()
    printUnfakeableMetrics()
    printOperandDrivenAudit()
    printStmtHandlerAudit()
    printCtDepthRefAudit()
}
