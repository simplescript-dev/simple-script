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

    if (kind == "IDENT" && nGetS1(nodeId) == "comptimeDepth") {
        bumpComptime(file)
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
            const body = nGetI1(stmtId)
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

function main() {
    collectSSFiles("bootstrap")
    println(`Scanning ${fileCount} bootstrap files...`)
    const files = fileList.split("\n")
    for (f in files) {
        if (f == "") { continue }
        processFile(f)
    }
    println("")
    propagateHandlers()
    printHeatmap()
}
