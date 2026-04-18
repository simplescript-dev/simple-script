// tools/reflection_health_linter.ss
//
// 编译器结构物理指标守护 (reflection root-cause gate, D097 后续)。
// 指标全是 AST / 调用图的纯图论量。改名、拆 helper、藏深嵌套皆不可伪造。
//
// M1  CC 总和    每函数 (IF/WHILE/DO_WHILE/FOR/FOR_IN/FOR_OF/TERNARY/
//                       SWITCH_CASE/CATCH_CLAUSE/&&/||/NullCoalesce +1) 之和
// M2  节点总数   AST 节点访问总数
// M3a 调用边数   CALL + METHOD_CALL + NEW_EXPR 的 callsite 数
// M3b 最大入度   最"热"目标函数被引用次数
// M4  分发深度   所有 IF 的 else-chain 长度之和 + SWITCH case 总数
// M5  可变 state 顶层 VAR_DECL 数 + 所有赋值节点数 (ASSIGN/INDEX_ASSIGN/
//                MEMBER_ASSIGN/COMPOUND_ASSIGN/POSTFIX_INC/POSTFIX_DEC)
// M6  递归函数   函数 body 内直接调自身的函数数 (SCC proxy)
// M7a 最大 IF 深 单函数内最大 IF 嵌套深度 (对抗"藏到深嵌套")
// M7b 函数总数   FUNC_DECL + ARROW_FUNC 总数 (对抗"拆到 helper")
//
// ── 扩展防规避指标 (D097 V2) ─────────────────────────────────
// N1  kind 基数  不同 AST kind 的数量 (引入新节点类型必 +1)
// N2  Halstead   m2 × floor(log2(N1)) — 信息论总体积下界
// N3  深度总和   所有 AST 节点从根的深度累加 (对抗"藏进深嵌套")
// N4  最大出度   任一节点的 list 长度上限 (对抗"压成长序列")
// N5  成员写入   MEMBER_ASSIGN 节点数 (对抗"Map 搬到 class 字段")
//
// 基线: tools/linter_baseline.txt。任一指标 > baseline → exit(1)。
// record 模式: 任一指标上升则拒绝写入 (D097 L102 "累积方向严禁更新 baseline")。
// 用法: bin/ss run tools/reflection_health_linter.ss           # 对比基线
//       bin/ss run tools/reflection_health_linter.ss record    # 把当前值写为新基线

import { tokenize } from "@/bootstrap/lexer"
import { parse, nGetKind, nGetS1, nGetI1, nGetI2, nGetI3, nGetI4, nGetList, nGetLine } from "@/bootstrap/parser"

// ── 指标累加器 ─────────────────────────────────────────────────
let m1 = 0
let m2 = 0
let m3a = 0
let m3b = 0
let m4 = 0
let m5 = 0
let m6 = 0
let m7a = 0
let m7b = 0
let n1 = 0
let n2 = 0
let n3 = 0
let n4 = 0
let n5 = 0

// ── 辅助 state ────────────────────────────────────────────────
let indeg: Map<string, string> = new Map()
let recFuncs: Map<string, string> = new Map()
let kindSet: Map<string, string> = new Map()
let funcScope: Array<string> = []
let files: Array<string> = []

// ── integer log2 (floor) ─────────────────────────────────────
function intLog2(n: int): int {
    if (n <= 1) { return 0 }
    let r = 0
    let k = n
    while (k > 1) { k = k / 2; r = r + 1 }
    return r
}

const BASELINE_PATH = "tools/linter_baseline.txt"

// ── Map<string,string> → int 适配 ────────────────────────────
function mapGetInt(m: Map<string, string>, k: string): int {
    if (m.has(k) == 0) { return 0 }
    return parseInt(m.getString(k))
}

function mapSetInt(m: Map<string, string>, k: string, v: int) {
    m.set(k, `${v}`)
}

// ── 函数作用域栈 ───────────────────────────────────────────────
function pushFunc(name: string) { funcScope.push(name) }

function popFunc() {
    const n = funcScope.length()
    if (n <= 0) { return }
    let out: Array<string> = []
    let i = 0
    while (i < n - 1) { out.push(funcScope[i]); i = i + 1 }
    funcScope = out
}

function funcTop(): string {
    const n = funcScope.length()
    if (n == 0) { return "" }
    return funcScope[n - 1]
}

function markRecursive(f: string) {
    if (recFuncs.has(f) == 1) { return }
    recFuncs.set(f, "1")
    m6 = m6 + 1
}

function countEdge(target: string) {
    if (target == "") { return }
    m3a = m3a + 1
    const now = mapGetInt(indeg, target) + 1
    mapSetInt(indeg, target, now)
    if (now > m3b) { m3b = now }
    const top = funcTop()
    if (top != "" && target == top) { markRecursive(top) }
}

// ── children 枚举 (沿用原 linter 结构,扩展 FUNC_DECL/ARROW_FUNC/CLASS_DECL) ─
function appendListIds(out: Array<int>, listStr: string): Array<int> {
    if (listStr == "") { return out }
    for (p in listStr.split(",")) {
        if (p == "") { continue }
        const cid = parseInt(p)
        if (cid > 0) { out.push(cid) }
    }
    return out
}

function collectChildren(id: int, kind: string): Array<int> {
    let out: Array<int> = []
    if (kind == "IDENT" || kind == "STRING_LIT" || kind == "INT_LIT" || kind == "DOUBLE_LIT") { return out }
    if (kind == "TRUE_LIT" || kind == "FALSE_LIT" || kind == "NULL_LIT") { return out }
    if (kind == "THIS" || kind == "SUPER" || kind == "TMPL_FRAG_LIT") { return out }
    if (kind == "BREAK" || kind == "CONTINUE") { return out }

    if (kind == "BLOCK" || kind == "PROGRAM" || kind == "CALL" || kind == "NEW_EXPR" || kind == "ARRAY_LIT" || kind == "TEMPLATE_LIT" || kind == "OBJ_LITERAL" || kind == "ANNOTATION_LIST") {
        out = appendListIds(out, nGetList(id))
        return out
    }
    if (kind == "METHOD_CALL") {
        const i1 = nGetI1(id); if (i1 > 0) { out.push(i1) }
        out = appendListIds(out, nGetList(id))
        return out
    }
    if (kind == "BINARY" || kind == "INDEX_ACCESS" || kind == "WHILE" || kind == "FOR_IN" || kind == "FOR_OF" || kind == "ASSIGN" || kind == "COMPOUND_ASSIGN" || kind == "SWITCH_CASE" || kind == "DO_WHILE") {
        const i1 = nGetI1(id); if (i1 > 0) { out.push(i1) }
        const i2 = nGetI2(id); if (i2 > 0) { out.push(i2) }
        return out
    }
    if (kind == "IF" || kind == "TERNARY" || kind == "TRY" || kind == "FOR") {
        const i1 = nGetI1(id); if (i1 > 0) { out.push(i1) }
        const i2 = nGetI2(id); if (i2 > 0) { out.push(i2) }
        const i3 = nGetI3(id); if (i3 > 0) { out.push(i3) }
        return out
    }
    if (kind == "UNARY" || kind == "GROUPING" || kind == "RETURN" || kind == "MEMBER_ACCESS" || kind == "VAR_DECL" || kind == "COMPTIME_EXPR" || kind == "COMPTIME_EMIT" || kind == "TYPEINFO_EXPR" || kind == "EXPR_STMT" || kind == "THROW" || kind == "TMPL_FRAG_EXPR" || kind == "POSTFIX_INC" || kind == "POSTFIX_DEC" || kind == "COMPTIME_BLOCK") {
        const i1 = nGetI1(id); if (i1 > 0) { out.push(i1) }
        return out
    }
    if (kind == "CATCH_CLAUSE" || kind == "CATCH") {
        const i2 = nGetI2(id); if (i2 > 0) { out.push(i2) }
        return out
    }
    if (kind == "SWITCH") {
        const i1 = nGetI1(id); if (i1 > 0) { out.push(i1) }
        out = appendListIds(out, nGetList(id))
        return out
    }
    if (kind == "INDEX_ASSIGN" || kind == "MEMBER_ASSIGN") {
        const i1 = nGetI1(id); if (i1 > 0) { out.push(i1) }
        const i2 = nGetI2(id); if (i2 > 0) { out.push(i2) }
        const i3 = nGetI3(id); if (i3 > 0) { out.push(i3) }
        return out
    }
    if (kind == "CLASS_DECL") {
        out = appendListIds(out, nGetList(id))
        const mb = nGetI2(id); if (mb > 0) { out.push(mb) }
        return out
    }
    if (kind == "FUNC_DECL" || kind == "ARROW_FUNC") {
        const body = nGetI1(id); if (body > 0) { out.push(body) }
        return out
    }
    const i1 = nGetI1(id); if (i1 > 0) { out.push(i1) }
    const i2 = nGetI2(id); if (i2 > 0) { out.push(i2) }
    const i3 = nGetI3(id); if (i3 > 0) { out.push(i3) }
    return out
}

// ── 圈复杂度 per-function (不穿透 nested function) ─────────
function countDecisions(id: int): int {
    if (id <= 0) { return 0 }
    const kind = nGetKind(id)
    if (kind == "FUNC_DECL" || kind == "ARROW_FUNC") { return 0 }
    let inc = 0
    if (kind == "IF" || kind == "WHILE" || kind == "DO_WHILE" || kind == "FOR" || kind == "FOR_IN" || kind == "FOR_OF" || kind == "TERNARY" || kind == "SWITCH_CASE" || kind == "CATCH_CLAUSE") {
        inc = 1
    } else if (kind == "BINARY") {
        const op = nGetS1(id)
        if (op == "And" || op == "Or" || op == "NullCoalesce") { inc = 1 }
    }
    let total = inc
    const kids = collectChildren(id, kind)
    for (c in kids) { total = total + countDecisions(c) }
    return total
}

// ── 主 visit (计 m2/m3/m4/m5/m6/m7a/m7b + n1/n3/n4/n5) ───────
function visit(id: int, ifDepth: int, nodeDepth: int) {
    if (id <= 0) { return }
    const kind = nGetKind(id)
    m2 = m2 + 1
    if (kindSet.has(kind) == 0) {
        kindSet.set(kind, "1")
        n1 = n1 + 1
    }
    n3 = n3 + nodeDepth
    const listStr = nGetList(id)
    if (listStr != "") {
        let fanout = 0
        for (fp in listStr.split(",")) { if (fp != "") { fanout = fanout + 1 } }
        if (fanout > n4) { n4 = fanout }
    }

    if (kind == "FUNC_DECL") {
        m7b = m7b + 1
        const name = nGetS1(id)
        pushFunc(name)
        const body = nGetI1(id)
        m1 = m1 + 1 + countDecisions(body)
        visit(body, 0, nodeDepth + 1)
        popFunc()
        return
    }
    if (kind == "ARROW_FUNC") {
        m7b = m7b + 1
        pushFunc(`__arrow_${id}`)
        const body = nGetI1(id)
        m1 = m1 + 1 + countDecisions(body)
        visit(body, 0, nodeDepth + 1)
        popFunc()
        return
    }

    if (kind == "IF") {
        const ifd = ifDepth + 1
        if (ifd > m7a) { m7a = ifd }
        let chain = 1
        let el = nGetI3(id)
        while (el > 0 && nGetKind(el) == "IF") {
            chain = chain + 1
            el = nGetI3(el)
        }
        m4 = m4 + chain
        visit(nGetI1(id), ifDepth, nodeDepth + 1)
        visit(nGetI2(id), ifd, nodeDepth + 1)
        const e2 = nGetI3(id); if (e2 > 0) { visit(e2, ifd, nodeDepth + 1) }
        return
    }

    if (kind == "SWITCH") {
        const cases = nGetList(id)
        if (cases != "") { m4 = m4 + cases.split(",").length() }
        visit(nGetI1(id), ifDepth, nodeDepth + 1)
        if (cases != "") {
            for (p in cases.split(",")) {
                if (p == "") { continue }
                const cid = parseInt(p)
                if (cid > 0) { visit(cid, ifDepth, nodeDepth + 1) }
            }
        }
        return
    }

    if (kind == "CALL") { countEdge(nGetS1(id)) }
    else if (kind == "METHOD_CALL") { countEdge(nGetS1(id)) }
    else if (kind == "NEW_EXPR") { countEdge(nGetS1(id)) }

    if (kind == "ASSIGN" || kind == "INDEX_ASSIGN" || kind == "MEMBER_ASSIGN" || kind == "COMPOUND_ASSIGN" || kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") {
        m5 = m5 + 1
    }
    if (kind == "MEMBER_ASSIGN") { n5 = n5 + 1 }

    const kids = collectChildren(id, kind)
    for (c in kids) { visit(c, ifDepth, nodeDepth + 1) }
}

// ── 文件扫描 ──────────────────────────────────────────────────
function collectSSFiles(dir: string) {
    const entries = listDir(dir)
    if (entries == "") { return }
    for (entry in entries.split("\n")) {
        if (entry == "") { continue }
        if (entry.endsWith(".ss") == 1) { files.push(`${dir}/${entry}`) }
    }
}

function processFile(path: string) {
    const source = readFile(path)
    tokenize(source)
    const rootId = parse("done")
    visit(rootId, 0, 0)
    const topList = nGetList(rootId)
    if (topList == "") { return }
    for (p in topList.split(",")) {
        if (p == "") { continue }
        const sid = parseInt(p)
        if (sid > 0 && nGetKind(sid) == "VAR_DECL") { m5 = m5 + 1 }
    }
}

// ── baseline IO ───────────────────────────────────────────────
function parseKV(line: string, prefix: string): int {
    if (line.startsWith(prefix) == 0) { return -1 }
    const rest = line.substring(prefix.length(), line.length() - prefix.length())
    return parseInt(rest)
}

function readBaselineVal(prefix: string): int {
    if (fileExists(BASELINE_PATH) == 0) { return -1 }
    const text = readFile(BASELINE_PATH)
    for (line in text.split("\n")) {
        if (line == "" || line.startsWith("#") == 1) { continue }
        const v = parseKV(line, prefix)
        if (v >= 0) { return v }
    }
    return -1
}

function writeBaseline() {
    const labels: Array<string> = ["M1", "M2", "M3a", "M3b", "M4", "M5", "M6", "M7a", "M7b", "N1", "N2", "N3", "N4", "N5"]
    const curs: Array<int> = [m1, m2, m3a, m3b, m4, m5, m6, m7a, m7b, n1, n2, n3, n4, n5]
    let blocked = 0
    let j = 0
    while (j < curs.length()) {
        const old = readBaselineVal(`${labels[j]}=`)
        if (old >= 0 && curs[j] > old) {
            println(`  record 拒绝: ${labels[j]} ${old} → ${curs[j]} 累积方向`)
            blocked = 1
        }
        j = j + 1
    }
    if (blocked == 1) {
        println("")
        println("D097 L102: 累积方向严禁更新 baseline。")
        println("  只有削减路径(所有指标不升)才允许 record。")
        exit(1)
    }
    const text = `# auto-generated by tools/reflection_health_linter.ss — do not edit\nM1=${m1}\nM2=${m2}\nM3a=${m3a}\nM3b=${m3b}\nM4=${m4}\nM5=${m5}\nM6=${m6}\nM7a=${m7a}\nM7b=${m7b}\nN1=${n1}\nN2=${n2}\nN3=${n3}\nN4=${n4}\nN5=${n5}\n`
    writeFile(BASELINE_PATH, text)
}

function compareAndReport(): int {
    if (fileExists(BASELINE_PATH) == 0) {
        println("(no baseline found — will not gate)")
        println(`  (to record current as baseline: bin/ss run ${"tools/reflection_health_linter.ss"} record)`)
        return 0
    }
    const text = readFile(BASELINE_PATH)
    let bm1 = -1
    let bm2 = -1
    let bm3a = -1
    let bm3b = -1
    let bm4 = -1
    let bm5 = -1
    let bm6 = -1
    let bm7a = -1
    let bm7b = -1
    let bn1 = -1
    let bn2 = -1
    let bn3 = -1
    let bn4 = -1
    let bn5 = -1
    for (line in text.split("\n")) {
        if (line == "" || line.startsWith("#") == 1) { continue }
        const v1 = parseKV(line, "M1="); if (v1 >= 0) { bm1 = v1 }
        const v2 = parseKV(line, "M2="); if (v2 >= 0) { bm2 = v2 }
        const v3a = parseKV(line, "M3a="); if (v3a >= 0) { bm3a = v3a }
        const v3b = parseKV(line, "M3b="); if (v3b >= 0) { bm3b = v3b }
        const v4 = parseKV(line, "M4="); if (v4 >= 0) { bm4 = v4 }
        const v5 = parseKV(line, "M5="); if (v5 >= 0) { bm5 = v5 }
        const v6 = parseKV(line, "M6="); if (v6 >= 0) { bm6 = v6 }
        const v7a = parseKV(line, "M7a="); if (v7a >= 0) { bm7a = v7a }
        const v7b = parseKV(line, "M7b="); if (v7b >= 0) { bm7b = v7b }
        const vn1 = parseKV(line, "N1="); if (vn1 >= 0) { bn1 = vn1 }
        const vn2 = parseKV(line, "N2="); if (vn2 >= 0) { bn2 = vn2 }
        const vn3 = parseKV(line, "N3="); if (vn3 >= 0) { bn3 = vn3 }
        const vn4 = parseKV(line, "N4="); if (vn4 >= 0) { bn4 = vn4 }
        const vn5 = parseKV(line, "N5="); if (vn5 >= 0) { bn5 = vn5 }
    }
    println("--- 基线对比 (任一指标 > baseline → exit(1)) ---")
    let regressions = 0
    regressions = regressions + reportDelta("M1 ", m1, bm1)
    regressions = regressions + reportDelta("M2 ", m2, bm2)
    regressions = regressions + reportDelta("M3a", m3a, bm3a)
    regressions = regressions + reportDelta("M3b", m3b, bm3b)
    regressions = regressions + reportDelta("M4 ", m4, bm4)
    regressions = regressions + reportDelta("M5 ", m5, bm5)
    regressions = regressions + reportDelta("M6 ", m6, bm6)
    regressions = regressions + reportDelta("M7a", m7a, bm7a)
    regressions = regressions + reportDelta("M7b", m7b, bm7b)
    regressions = regressions + reportDelta("N1 ", n1, bn1)
    regressions = regressions + reportDelta("N2 ", n2, bn2)
    regressions = regressions + reportDelta("N3 ", n3, bn3)
    regressions = regressions + reportDelta("N4 ", n4, bn4)
    regressions = regressions + reportDelta("N5 ", n5, bn5)
    return regressions
}

function reportDelta(label: string, cur: int, baseline: int): int {
    if (baseline < 0) {
        println(`  ${label} cur=${cur} baseline=(missing)`)
        return 0
    }
    const delta = cur - baseline
    let tag = "OK"
    let isReg = 0
    if (cur > baseline) { tag = "REGRESSION"; isReg = 1 }
    else if (cur < baseline) { tag = "PROGRESS" }
    println(`  ${label} cur=${cur} baseline=${baseline} delta=${delta} → ${tag}`)
    return isReg
}

// ── main ──────────────────────────────────────────────────────
function main() {
    let mode = ""
    let scanDir = "bootstrap"
    let i = 1
    while (i < args()) {
        const a = arg(i)
        if (a == "record") { mode = "record" }
        else if (a == "--dir" && i + 1 < args()) { scanDir = arg(i + 1); i = i + 1 }
        i = i + 1
    }
    collectSSFiles(scanDir)
    let fi = 0
    while (fi < files.length()) { processFile(files[fi]); fi = fi + 1 }

    n2 = m2 * intLog2(n1)

    println("=== 编译器结构物理指标 (pure graph-theoretic, unforgeable) ===")
    println(`扫描 ${files.length()} 个 bootstrap 文件`)
    println("")
    println(`M1  (CC 总和)          = ${m1}`)
    println(`M2  (AST 节点总数)     = ${m2}`)
    println(`M3a (调用边数)         = ${m3a}`)
    println(`M3b (最大入度)         = ${m3b}`)
    println(`M4  (Dispatch 深度和)  = ${m4}`)
    println(`M5  (可变 state 点数)  = ${m5}`)
    println(`M6  (递归函数数)       = ${m6}`)
    println(`M7a (最大 IF 嵌套深)   = ${m7a}`)
    println(`M7b (函数总数)         = ${m7b}`)
    println(`N1  (kind 基数)        = ${n1}`)
    println(`N2  (Halstead 体积)    = ${n2}`)
    println(`N3  (AST 深度总和)     = ${n3}`)
    println(`N4  (最大节点出度)     = ${n4}`)
    println(`N5  (MEMBER_ASSIGN 数) = ${n5}`)
    println("")

    if (mode == "record") {
        writeBaseline()
        println(`✓ 基线已写入 ${BASELINE_PATH}`)
        return
    }

    const regressions = compareAndReport()
    println("")
    if (regressions > 0) {
        println(`GATE BLOCKED — ${regressions} metric(s) regressed`)
        println("  改动触及反射路径且未伴随根因削减,请回头想清楚再提交。")
        exit(1)
    } else {
        println("GATE PASS — no regressions")
    }
}
