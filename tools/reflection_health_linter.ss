// tools/reflection_health_linter.ss
//
// 反射根因指标守护。详细规则/目标/不可伪造性论证见
// docs/3-decisions/D097-reflection-root-cause-metrics.md。
//
// Gate 行为: G1-G4 高于 baseline 或 G5 低于 baseline → exit(1)。
// 仅阻挡回归,不强制逼近 Target;Target 推进靠人工跟进。
//
// 用法: bin/ss run tools/reflection_health_linter.ss

import { tokenize } from "@/bootstrap/lexer"
import { parse, nGetKind, nGetS1, nGetI1, nGetI2, nGetI3, nGetList, nGetLine } from "@/bootstrap/parser"

// Baseline frozen 2026-04-18 @ commit 0750511
let BASELINE_G1 = 6
let BASELINE_G2 = 6
let BASELINE_G3 = 4
let BASELINE_G4 = 8
let BASELINE_G5 = 0

let TARGET_G1 = 0
let TARGET_G2 = 1
let TARGET_G3 = 0
let TARGET_G4 = 2
let TARGET_G5 = 4

// ── State ──────────────────────────────────────────────────

let files: Array<string> = []

let currentFile = ""

let g1Count = 0
let g1Hits = ""

let g2Count = 0
let g2Names = ""

let g3Suffixes = ""

let g4Count = 0
let g4Hits = ""

let g5Count = 0
let g5Types = ""

// ── Helpers ─────────────────────────────────────────────────

function setContainsExact(s: string, elem: string): int {
    return ((`,${s},`).contains(`,${elem},`) == 1) ? 1 : 0
}

function addToSet(set: string, elem: string): string {
    if (set == "") { return elem }
    if (setContainsExact(set, elem) == 1) { return set }
    return `${set},${elem}`
}

function setSize(s: string): int {
    if (s == "") { return 0 }
    return s.split(",").length()
}

function padRight(s: string, width: int): string {
    let out = s
    while (out.length() < width) { out = `${out} ` }
    return out
}

function isIdentChar(code: int): int {
    if (code >= 97 && code <= 122) { return 1 }  // a-z
    if (code >= 65 && code <= 90) { return 1 }   // A-Z
    if (code >= 48 && code <= 57) { return 1 }   // 0-9
    if (code == 95) { return 1 }                 // _
    return 0
}

// 输入:TMPL_FRAG_LIT 文本;提取紧随第一个 ".__" 之后的标识符。
// 例: ".__methodCls" -> "__methodCls"; "foo.__x.bar" -> "__x"。
function extractSidecarSuffix(fragText: string): string {
    if (fragText.contains(".__") != 1) { return "" }
    const parts = fragText.split(".__")
    if (parts.length() < 2) { return "" }
    const tail = parts[1]
    let out = ""
    let i = 0
    while (i < tail.length()) {
        const code = tail.charCodeAt(i)
        if (isIdentChar(code) == 1) {
            out = `${out}${tail.charAt(i)}`
            i = i + 1
        } else { break }
    }
    if (out == "") { return "" }
    return `__${out}`
}

function isExcludedSidecar(suffix: string): int {
    if (suffix == "__comptime") { return 1 }
    if (suffix == "__ct_") { return 1 }
    if (suffix == "__ct") { return 1 }
    if (suffix == "__FILE__") { return 1 }
    if (suffix == "__LINE__") { return 1 }
    return 0
}

function isCallOfNGetS1(id: int): int {
    if (id <= 0) { return 0 }
    if (nGetKind(id) != "CALL") { return 0 }
    if (nGetS1(id) != "nGetS1") { return 0 }
    return 1
}

function isReflectionMember(m: string): int {
    if (m == "fields") { return 1 }
    if (m == "methods") { return 1 }
    if (m == "annotations") { return 1 }
    if (m == "args") { return 1 }
    return 0
}

function isMetaType(t: string): int {
    if (t == "ClassMeta") { return 1 }
    if (t == "FieldMeta") { return 1 }
    if (t == "MethodMeta") { return 1 }
    if (t == "AnnotationMeta") { return 1 }
    if (t == "ParamMeta") { return 1 }
    return 0
}

// ── AST 遍历 ───────────────────────────────────────────────

function visitList(listStr: string) {
    if (listStr == "") { return }
    const parts = listStr.split(",")
    for (p in parts) {
        if (p == "") { continue }
        const id = parseInt(p)
        if (id > 0) { visitNode(id) }
    }
}

function visitNode(nid: int) {
    if (nid <= 0) { return }
    const kind = nGetKind(nid)

    if (kind == "BINARY" && nGetS1(nid) == "Eq") {
        const leftId = nGetI1(nid)
        const rightId = nGetI2(nid)
        if (isCallOfNGetS1(leftId) == 1 && rightId > 0 && nGetKind(rightId) == "STRING_LIT") {
            const mem = nGetS1(rightId)
            if (isReflectionMember(mem) == 1) {
                g1Count = g1Count + 1
                const hit = `${currentFile}:${nGetLine(nid)} nGetS1(x)=="${mem}"`
                if (g1Hits == "") { g1Hits = hit } else { g1Hits = `${g1Hits}\n${hit}` }
            }
        }
    }

    if (kind == "TMPL_FRAG_LIT") {
        const text = nGetS1(nid)
        if (text.contains(".__") == 1) {
            const suffix = extractSidecarSuffix(text)
            if (suffix != "" && isExcludedSidecar(suffix) == 0) {
                g3Suffixes = addToSet(g3Suffixes, suffix)
            }
        }
    }

    if (kind == "CALL" && nGetS1(nid) == "genForInUnrolled") {
        g4Count = g4Count + 1
        const hit = `${currentFile}:${nGetLine(nid)}`
        if (g4Hits == "") { g4Hits = hit } else { g4Hits = `${g4Hits}\n${hit}` }
    }

    if (kind == "NEW_EXPR") {
        const cls = nGetS1(nid)
        if (isMetaType(cls) == 1 && setContainsExact(g5Types, cls) != 1) {
            g5Count = g5Count + 1
            g5Types = addToSet(g5Types, cls)
        }
    }

    visitChildren(nid, kind)
}

function visitChildren(nid: int, kind: string) {
    if (kind == "IDENT" || kind == "STRING_LIT" || kind == "INT_LIT" || kind == "DOUBLE_LIT") { return }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT" || kind == "NULL_LIT") { return }
    if (kind == "THIS" || kind == "SUPER") { return }
    if (kind == "TMPL_FRAG_LIT") { return }

    if (kind == "BLOCK" || kind == "PROGRAM") { visitList(nGetList(nid)); return }
    if (kind == "CALL" || kind == "NEW_EXPR" || kind == "ARRAY_LIT") { visitList(nGetList(nid)); return }
    if (kind == "TEMPLATE_LIT" || kind == "OBJ_LITERAL" || kind == "ANNOTATION_LIST") { visitList(nGetList(nid)); return }

    if (kind == "METHOD_CALL") {
        visitNode(nGetI1(nid))
        visitList(nGetList(nid))
        return
    }

    if (kind == "BINARY" || kind == "INDEX_ACCESS" || kind == "WHILE" || kind == "FOR_IN" || kind == "FOR_OF" || kind == "ASSIGN" || kind == "COMPOUND_ASSIGN" || kind == "SWITCH_CASE" || kind == "DO_WHILE") {
        visitNode(nGetI1(nid))
        visitNode(nGetI2(nid))
        return
    }

    if (kind == "IF" || kind == "TERNARY" || kind == "TRY") {
        visitNode(nGetI1(nid))
        visitNode(nGetI2(nid))
        visitNode(nGetI3(nid))
        return
    }

    if (kind == "UNARY" || kind == "GROUPING" || kind == "RETURN" || kind == "MEMBER_ACCESS" || kind == "VAR_DECL" || kind == "COMPTIME_EXPR" || kind == "COMPTIME_EMIT" || kind == "TYPEINFO_EXPR" || kind == "EXPR_STMT" || kind == "THROW" || kind == "TMPL_FRAG_EXPR") {
        visitNode(nGetI1(nid))
        return
    }

    if (kind == "CATCH") { visitNode(nGetI2(nid)); return }

    if (kind == "SWITCH") {
        visitNode(nGetI1(nid))
        visitList(nGetList(nid))
        return
    }

    const i1 = nGetI1(nid)
    const i2 = nGetI2(nid)
    const i3 = nGetI3(nid)
    if (i1 > 0) { visitNode(i1) }
    if (i2 > 0) { visitNode(i2) }
    if (i3 > 0) { visitNode(i3) }
}

// ── G2: top-level VAR_DECL 扫描 ─────────────────────────────

function scanTopLevelVarDecls(rootId: int) {
    const topList = nGetList(rootId)
    if (topList == "") { return }
    const parts = topList.split(",")
    for (p in parts) {
        if (p == "") { continue }
        const sid = parseInt(p)
        if (sid <= 0) { continue }
        if (nGetKind(sid) != "VAR_DECL") { continue }
        const name = nGetS1(sid)
        if (name.startsWith("class") != 1) { continue }
        if (name.contains("Annotation") != 1) { continue }
        g2Count = g2Count + 1
        g2Names = addToSet(g2Names, name)
    }
}

// ── 文件扫描 ────────────────────────────────────────────────

function collectSSFiles(dir: string) {
    const entries = listDir(dir)
    if (entries == "") { return }
    const parts = entries.split("\n")
    for (entry in parts) {
        if (entry == "") { continue }
        if (entry.endsWith(".ss") == 1) {
            files.push(`${dir}/${entry}`)
        }
    }
}

function processFile(path: string) {
    currentFile = path
    const source = readFile(path)
    tokenize(source)
    const rootId = parse("done")
    scanTopLevelVarDecls(rootId)
    const topList = nGetList(rootId)
    if (topList == "") { return }
    const parts = topList.split(",")
    for (p in parts) {
        if (p == "") { continue }
        const sid = parseInt(p)
        if (sid <= 0) { continue }
        visitNode(sid)
    }
}

// ── Report ──────────────────────────────────────────────────

function verdict(name: string, cur: int, baseline: int, target: int, isMin: int): string {
    let status = ""
    if (isMin == 1) {
        if (cur < baseline) { status = "REGRESSION" }
        else if (cur >= target) { status = "TARGET" }
        else if (cur == baseline) { status = "BASELINE" }
        else { status = "PROGRESS" }
    } else {
        if (cur > baseline) { status = "REGRESSION" }
        else if (cur <= target) { status = "TARGET" }
        else if (cur == baseline) { status = "BASELINE" }
        else { status = "PROGRESS" }
    }
    const arrow = (isMin == 1) ? "≥" : "≤"
    return `${padRight(name, 4)} cur=${padRight(`${cur}`, 3)} baseline=${padRight(`${baseline}`, 3)} target ${arrow}${padRight(`${target}`, 2)} → ${status}`
}

function main() {
    collectSSFiles("bootstrap")
    let fi = 0
    while (fi < files.length()) { processFile(files[fi]); fi = fi + 1 }

    const g3Count = setSize(g3Suffixes)

    println("=== D097 反射根因指标 (Reflection Root-Cause Metrics) ===")
    println(`扫描 ${files.length()} 个 bootstrap 文件`)
    println("")
    println(verdict("G1", g1Count, BASELINE_G1, TARGET_G1, 0))
    println("     (hardcoded 反射 kind 分支: nGetS1(x)==fields/methods/annotations/args)")
    println(verdict("G2", g2Count, BASELINE_G2, TARGET_G2, 0))
    println(`     (反射 Annotation 全局 Map: ${g2Names})`)
    println(verdict("G3", g3Count, BASELINE_G3, TARGET_G3, 0))
    println(`     (distinct sidecar 后缀: ${g3Suffixes})`)
    println(verdict("G4", g4Count, BASELINE_G4, TARGET_G4, 0))
    println("     (genForInUnrolled 调用点)")
    println(verdict("G5", g5Count, BASELINE_G5, TARGET_G5, 1))
    println(`     (comptime Meta 构造 distinct 类型: ${g5Types})`)
    println("")

    let regressions = 0
    if (g1Count > BASELINE_G1) { regressions = regressions + 1 }
    if (g2Count > BASELINE_G2) { regressions = regressions + 1 }
    if (g3Count > BASELINE_G3) { regressions = regressions + 1 }
    if (g4Count > BASELINE_G4) { regressions = regressions + 1 }
    if (g5Count < BASELINE_G5) { regressions = regressions + 1 }

    let allTargets = 0
    if (g1Count <= TARGET_G1 && g2Count <= TARGET_G2 && g3Count <= TARGET_G3 && g4Count <= TARGET_G4 && g5Count >= TARGET_G5) { allTargets = 1 }

    println("=====================================")
    if (regressions > 0) {
        println(`GATE BLOCKED — ${regressions} metric(s) regressed`)
        if (g1Hits != "") {
            println("")
            println("G1 命中 (reflection branches):")
            const hits = g1Hits.split("\n")
            for (h in hits) { if (h != "") { println(`  ${h}`) } }
        }
        if (g4Hits != "") {
            println("")
            println("G4 命中 (genForInUnrolled call sites):")
            const hits = g4Hits.split("\n")
            for (h in hits) { if (h != "") { println(`  ${h}`) } }
        }
        exit(1)
    } else if (allTargets == 1) {
        println("ALL TARGETS MET — 根因解决达成,反射已走 Meta 对象路径")
    } else {
        println("GATE PASS — no regressions; 未完成 Zig SEMA 目标")
    }
}
