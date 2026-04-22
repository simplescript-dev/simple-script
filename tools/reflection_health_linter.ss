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

import { tokenize } from "@/bootstrap/lexer/lexer"
import { parse, nGetKind, nGetS1, nGetI1, nGetI2, nGetI3, nGetI4, nGetList, nGetLine } from "@/bootstrap/parse/parser"

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
// D102 §决策 2 F1 GATE: 每个扫描文件的行数(charAt '\n' 计数,对齐 wc -l)。
let fileLineCounts: Map<string, string> = new Map()

// ── integer log2 (floor) ─────────────────────────────────────
function intLog2(n: int): int {
    if (n <= 1) { return 0 }
    let r = 0
    let k = n
    while (k > 1) { k = k / 2; r = r + 1 }
    return r
}

const BASELINE_PATH = "tools/linter_baseline.txt"
// D102 §规则 2.1: 单文件行数上限(R2/R3 硬阻新文件 > 600,最终目标所有 bootstrap 文件 ≤ 600)。
const F1_LIMIT = 600

// ── Map<string,string> → int 适配 ────────────────────────────
function mapGetInt(m: Map<string, string>, k: string): int {
    if (m.has(k) == 0) { return 0 }
    return parseInt(m.getString(k))
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
    indeg.set(target, `${now}`)
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
        else { collectSSFiles(`${dir}/${entry}`) }
    }
}

function processFile(path: string) {
    const source = readFile(path)
    let lc = 0
    let sp = 0
    while (sp < source.length()) {
        if (source.charAt(sp) == "\n") { lc = lc + 1 }
        sp = sp + 1
    }
    fileLineCounts.set(path, `${lc}`)
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

// ── baseline IO (D124 §决策 1-3: 2 列制 baseline_value:budget_max) ────
// 两个 Map 分别承载语义清晰的两列:baseline_value(历史证据)+ budget_max(gate 阈值)。
// 不合成单 Map<string,"bv:bm"> — 自内部数据不二次序列化(`feedback_human_readable_code` #1)。
let baselineMap: Map<string, string> = new Map()
let budgetMap: Map<string, string> = new Map()
let baselineLoaded: int = 0

const TODAY_DATE = "2026-04-22"

function mapGetIntOrNeg(m: Map<string, string>, k: string): int {
    if (m.has(k) == 0) { return -1 }
    return parseInt(m.getString(k))
}

// 解析 "<prefix><bv>:<bm>"(2 列)或 legacy "<prefix><v>"(视作 bv==bm)。baseline.txt 是 IO 边界,
// 手工 edit 的格式畸形必须拒(D124 §决策 3.3 不可伪造)。返 [bv, bm] 前缀不匹配返 []。
function parseRow(line: string, prefix: string): Array<int> {
    let out: Array<int> = []
    if (line.startsWith(prefix) == 0) { return out }
    const rest = line.substring(prefix.length(), line.length() - prefix.length())
    if (rest == "") {
        println(`  格式错误: ${prefix} 后无值`)
        exit(1)
    }
    const colonIdx = rest.indexOf(":")
    if (colonIdx < 0) {
        const v = parseInt(rest)
        out.push(v); out.push(v)
        return out
    }
    const left = rest.substring(0, colonIdx)
    const right = rest.substring(colonIdx + 1, rest.length() - (colonIdx + 1))
    if (right.indexOf(":") >= 0) {
        println(`  格式错误: ${prefix}${rest} 多冒号 (不允许)`)
        exit(1)
    }
    if (left == "" || right == "") {
        println(`  格式错误: ${prefix}${rest} 空值`)
        exit(1)
    }
    out.push(parseInt(left))
    out.push(parseInt(right))
    return out
}

function loadBaseline() {
    if (baselineLoaded == 1) { return }
    baselineLoaded = 1
    if (fileExists(BASELINE_PATH) == 0) { return }
    const text = readFile(BASELINE_PATH)
    for (line in text.split("\n")) {
        if (line == "" || line.startsWith("#") == 1) { continue }
        const eqIdx = line.indexOf("=")
        if (eqIdx < 0) { continue }
        const key = line.substring(0, eqIdx)
        const row = parseRow(line, `${key}=`)
        if (row.length() == 2) {
            const bv = row[0]; const bm = row[1]
            baselineMap.set(key, `${bv}`)
            budgetMap.set(key, `${bm}`)
        }
    }
}

// D124 §决策 2.1 四终态 record 行为:
//   首次 (bv_old<0):          [cur, cur]
//   PROGRESS (cur < bv_old):  bv=cur; 若 bv_old==bm_old 同降,否则 stamp 保持
//   OK       (cur == bv_old): 不变
//   DRIFT    (bv_old < cur ≤ bm_old): bv=cur 消耗扩容预算, bm 保持(§决策 3.2 Execute 后同步语义)
//   REGRESSION (cur > bm_old):由调用方 gate 阻 record,本函数不感知
// 返 [new_bv, new_bm];调用方立即解包到命名变量。
function computeRecord(cur: int, bv_old: int, bm_old: int): Array<int> {
    let out: Array<int> = []
    if (bv_old < 0) { out.push(cur); out.push(cur); return out }
    if (cur == bv_old) { out.push(bv_old); out.push(bm_old); return out }
    out.push(cur)
    if (cur < bv_old && bv_old == bm_old) { out.push(cur) } else { out.push(bm_old) }
    return out
}

function isRegression(key: string, cur: int): int {
    loadBaseline()
    const bm = mapGetIntOrNeg(budgetMap, key)
    if (bm < 0) { return 0 }
    if (cur > bm) { return 1 }
    return 0
}

function writeBaseline() {
    loadBaseline()
    const labels: Array<string> = ["M1", "M2", "M3a", "M3b", "M4", "M5", "M6", "M7a", "M7b", "N1", "N2", "N3", "N4", "N5"]
    const curs: Array<int> = [m1, m2, m3a, m3b, m4, m5, m6, m7a, m7b, n1, n2, n3, n4, n5]

    let blocked = 0
    let j = 0
    while (j < curs.length()) {
        if (isRegression(labels[j], curs[j]) == 1) {
            const bm_old = mapGetIntOrNeg(budgetMap, labels[j])
            println(`  record 拒绝: ${labels[j]} cur=${curs[j]} > budget_max=${bm_old} (REGRESSION,需走 bump CLI)`)
            blocked = 1
        }
        j = j + 1
    }
    let fi = 0
    while (fi < files.length()) {
        const path = files[fi]
        const cur = parseInt(fileLineCounts.getString(path))
        const f1key = `F1:${path}`
        if (isRegression(f1key, cur) == 1) {
            const bm_old = mapGetIntOrNeg(budgetMap, f1key)
            println(`  record 拒绝: ${f1key} cur=${cur} > budget_max=${bm_old} (REGRESSION,需拆文件或 bump)`)
            blocked = 1
        }
        fi = fi + 1
    }
    if (blocked == 1) {
        println("")
        println("D097 §累积方向严禁更新 + D124 §决策 2.1: cur > budget_max 拒 record。")
        println("  要么回退 cur,要么 `bin/ss run tools/reflection_health_linter.ss bump <metric> <new_budget> <doc_anchor>` 升 budget_max。")
        exit(1)
    }

    const header = "# auto-generated by tools/reflection_health_linter.ss — do not edit"
    let text = `${header}\n`
    const oldText = readFile(BASELINE_PATH)
    for (line in oldText.split("\n")) {
        if (line.startsWith("#") == 1 && line != header) {
            text = `${text}${line}\n`
        }
    }

    j = 0
    while (j < curs.length()) {
        const bv_old = mapGetIntOrNeg(baselineMap, labels[j])
        const bm_old = mapGetIntOrNeg(budgetMap, labels[j])
        const rec = computeRecord(curs[j], bv_old, bm_old)
        const new_bv = rec[0]; const new_bm = rec[1]
        text = `${text}${labels[j]}=${new_bv}:${new_bm}\n`
        j = j + 1
    }
    fi = 0
    while (fi < files.length()) {
        const path = files[fi]
        const cur = parseInt(fileLineCounts.getString(path))
        if (cur > F1_LIMIT) {
            const f1key = `F1:${path}`
            const bv_old = mapGetIntOrNeg(baselineMap, f1key)
            const bm_old = mapGetIntOrNeg(budgetMap, f1key)
            const rec = computeRecord(cur, bv_old, bm_old)
            const new_bv = rec[0]; const new_bm = rec[1]
            text = `${text}${f1key}=${new_bv}:${new_bm}\n`
        }
        fi = fi + 1
    }
    writeFile(BASELINE_PATH, text)
}

function checkF1(): int {
    let regs = 0
    println("--- F1 文件行数 GATE (cur > budget_max → BLOCKED) ---")
    let fi = 0
    while (fi < files.length()) {
        const path = files[fi]
        const cur = parseInt(fileLineCounts.getString(path))
        const f1key = `F1:${path}`
        const bv = mapGetIntOrNeg(baselineMap, f1key)
        const bm = mapGetIntOrNeg(budgetMap, f1key)
        let tag = "OK"
        if (bm >= 0) {
            if (cur > bm) { tag = "REGRESSION"; regs = regs + 1 }
            else if (cur > bv) { tag = "DRIFT" }
            else if (cur < bv) { tag = "PROGRESS" }
            println(`  F1 ${path} cur=${cur} bv=${bv} bm=${bm} → ${tag}`)
        } else if (cur > F1_LIMIT) {
            tag = "REGRESSION (> 600 新文件 R3)"; regs = regs + 1
            println(`  F1 ${path} cur=${cur} bv=-1 bm=-1 → ${tag}`)
        }
        fi = fi + 1
    }
    return regs
}

function compareAndReport(): int {
    if (fileExists(BASELINE_PATH) == 0) {
        println("(no baseline found — will not gate)")
        println(`  (to record current as baseline: bin/ss run ${"tools/reflection_health_linter.ss"} record)`)
        return 0
    }
    loadBaseline()
    println("--- 基线对比 (cur > budget_max → BLOCKED) ---")
    const labels: Array<string> = ["M1 ", "M2 ", "M3a", "M3b", "M4 ", "M5 ", "M6 ", "M7a", "M7b", "N1 ", "N2 ", "N3 ", "N4 ", "N5 "]
    const keys: Array<string> = ["M1", "M2", "M3a", "M3b", "M4", "M5", "M6", "M7a", "M7b", "N1", "N2", "N3", "N4", "N5"]
    const curs: Array<int> = [m1, m2, m3a, m3b, m4, m5, m6, m7a, m7b, n1, n2, n3, n4, n5]
    let regressions = 0
    let j = 0
    while (j < curs.length()) {
        regressions = regressions + reportDelta(labels[j], curs[j], keys[j])
        j = j + 1
    }
    regressions = regressions + checkF1()
    return regressions
}

// D124 §决策 2.1 四终态 (tol 由 budget_max - baseline_value 显式表达,旧 tol=baseline/200 废):
//   cur < baseline_value              → PROGRESS
//   cur == baseline_value             → OK
//   baseline_value < cur ≤ budget_max → DRIFT (gate 不阻,扩容预算内浮动)
//   cur > budget_max                  → REGRESSION (gate 阻)
function reportDelta(label: string, cur: int, key: string): int {
    const bv = mapGetIntOrNeg(baselineMap, key)
    const bm = mapGetIntOrNeg(budgetMap, key)
    if (bv < 0) {
        println(`  ${label} cur=${cur} baseline=(missing)`)
        return 0
    }
    const delta = cur - bv
    let tag = "OK"
    let isReg = 0
    if (cur > bm) { tag = "REGRESSION"; isReg = 1 }
    else if (cur > bv) { tag = "DRIFT" }
    else if (cur < bv) { tag = "PROGRESS" }
    println(`  ${label} cur=${cur} bv=${bv} bm=${bm} delta=${delta} → ${tag}`)
    return isReg
}

// D124 §决策 3.2 bump <metric> <new_budget_max> <doc_anchor>:
// 只上不下; doc_anchor 形如 D<num>#<section>, 文件需存在 docs/3-decisions/, section 需命中。
// 写入:改 metric 行 budget_max, baseline_value 不变, 注释块前追加 audit trail。
function bumpCmd(metric: string, newBudgetStr: string, docAnchor: string) {
    const newBudget = parseInt(newBudgetStr)
    if (newBudget <= 0) {
        println(`  bump 拒绝: new_budget "${newBudgetStr}" 非正整数`)
        exit(1)
    }
    loadBaseline()
    const bv_old = mapGetIntOrNeg(baselineMap, metric)
    const bm_old = mapGetIntOrNeg(budgetMap, metric)
    if (bv_old < 0) {
        println(`  bump 拒绝: metric "${metric}" 未在 baseline 中 (legacy 首轮先跑 record 升 2 列格式)`)
        exit(1)
    }
    if (newBudget < bm_old) {
        println(`  bump 拒绝: new_budget=${newBudget} < old_budget=${bm_old} (bump 只上不下,下压走 record)`)
        exit(1)
    }
    const hashIdx = docAnchor.indexOf("#")
    if (hashIdx < 0) {
        println(`  bump 拒绝: doc_anchor "${docAnchor}" 无 # 分隔符 (期望 D<num>#<section>)`)
        exit(1)
    }
    const docNum = docAnchor.substring(0, hashIdx)
    const section = docAnchor.substring(hashIdx + 1, docAnchor.length() - (hashIdx + 1))
    const entries = listDir("docs/3-decisions")
    let docFilePath = ""
    if (entries != "") {
        for (ent in entries.split("\n")) {
            if (ent == "") { continue }
            if (ent.startsWith(`${docNum}-`) == 1 && ent.endsWith(".md") == 1) {
                docFilePath = `docs/3-decisions/${ent}`
            }
        }
    }
    if (docFilePath == "") {
        println(`  bump 拒绝: D 文档 "${docNum}-*.md" 不存在于 docs/3-decisions/`)
        exit(1)
    }
    const docText = readFile(docFilePath)
    if (docText.indexOf(section) < 0) {
        println(`  bump 拒绝: section "${section}" 在 ${docFilePath} 中未命中 (强制文档落段)`)
        exit(1)
    }
    const oldText = readFile(BASELINE_PATH)
    const auditTrail = `# bump ${metric} ${bm_old}→${newBudget} trail=${docAnchor} date=${TODAY_DATE}`
    let newText = ""
    let trailInserted = 0
    for (line in oldText.split("\n")) {
        if (line == "") { continue }
        if (line.startsWith("#") == 1) {
            newText = `${newText}${line}\n`
            continue
        }
        if (trailInserted == 0) {
            newText = `${newText}${auditTrail}\n`
            trailInserted = 1
        }
        if (line.startsWith(`${metric}=`) == 1) {
            newText = `${newText}${metric}=${bv_old}:${newBudget}\n`
        } else {
            newText = `${newText}${line}\n`
        }
    }
    writeFile(BASELINE_PATH, newText)
    println(`✓ bump ${metric} ${bm_old}→${newBudget} trail=${docAnchor} date=${TODAY_DATE}`)
    println(`  baseline_value=${bv_old} (不变) / budget_max=${newBudget} (升)`)
    println(`  Execute 后跑 \`bin/ss run tools/reflection_health_linter.ss record\` 把 baseline_value 同步到 cur`)
}

// ── main ──────────────────────────────────────────────────────
function main() {
    let mode = ""
    let scanDir = "bootstrap"
    let bumpMetric = ""
    let bumpNewBudget = ""
    let bumpDocAnchor = ""
    let i = 1
    while (i < args()) {
        const a = arg(i)
        if (a == "record") { mode = "record" }
        else if (a == "bump") {
            mode = "bump"
            if (i + 3 >= args()) {
                println("用法: bump <metric> <new_budget> <doc_anchor>")
                exit(1)
            }
            bumpMetric = arg(i + 1)
            bumpNewBudget = arg(i + 2)
            bumpDocAnchor = arg(i + 3)
            i = i + 3
        }
        else if (a == "--dir" && i + 1 < args()) { scanDir = arg(i + 1); i = i + 1 }
        i = i + 1
    }

    if (mode == "bump") {
        bumpCmd(bumpMetric, bumpNewBudget, bumpDocAnchor)
        return
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
        println("  cur > budget_max 且未 bump 扩容申报,或触碰反射路径未伴随根因削减,请回头想清楚再提交。")
        exit(1)
    } else {
        println("GATE PASS — no regressions")
    }
}
