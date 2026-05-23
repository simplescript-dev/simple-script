// tools/sunset_linter.ss — D170 SUNSET marker 过渡债漂移机械 gate
//
// SUNSET(D170 §step 9): 长期可考虑与 d_doc_index_linter 共享 D 文档实存判 helper
//   (D170 §与现有机制关系 line 133 "留 Phase 2+ 优化");
//   归 step 9 工具实施轮 scope(D170 §决策 A.2 自循环示范)
//
// Usage:
//   bin/ss run tools/sunset_linter.ss                    # 默认扫(C1-C4 BLOCK + C5/C6/C8/C9 软警告汇总)
//   bin/ss run tools/sunset_linter.ss --audit            # 默认 + C5-C9 详情列出每 candidate file:line
//   bin/ss run tools/sunset_linter.ss <path>             # 扫单文件或单目录(测试用,C5-C9 关闭)
//   bin/ss run tools/sunset_linter.ss --phase "<X>"      # Phase Exit verify 模式 (D170 §决策 C)
//
// 默认模式 C1-C4 (D170 §决策 B,BLOCK gate):
//   C1 (collection): 收集所有 `// SUNSET(D<num> §<phase>): <reason>` markers,
//                    列 file:line + 解析 D 号 / phase 名 / reason
//   C2 (D 文档实存): 每 marker 的 D<num> 必实存于 docs/3-decisions/
//                    (沿用 d_doc_index_linter 模式),否则 BLOCK
//   C3 (phase 状态): 找该 D 文档 §下一步 列表 list-item 起首 50 字符内含 phase 名:
//                    [ ] Planned / [ ] Blocked / [~] In Progress  → PASS (marker 合法)
//                    [x] Done                                       → BLOCK (marker 需清理)
//                    全无                                           → 软警告 (verify phase 名)
//   C4 (reason 非空): `):` 后 trim 后 length > 0,否则 BLOCK
//
// 扩展模式 C5/C6/C8/C9 (D170 §决策 B C5-C9 spec — step 8 落档,step 9 实施,全软警告不 BLOCK):
//   C5 (D 文档反向锚): 扫 docs/3-decisions/D*.md 找 "留独立轮" / "留下轮" / "留 Phase "
//                       — D 文档 §下一步 / Done 注释里的 forward-looking commitment;
//                       承载 D170 §决策 A.3 (D 文档 ↔ 代码 双向锚)。
//                       v0.1 三主 substring pattern;复合正则(留 X+ / 留 N.N+)留 v0.2 升级
//   C6 (协议自循环):    扫 docs/3-decisions/D*.md 找 "长期可考虑" — 协议自身 forward-looking
//                       commitment 必有对应工具/代码侧 SUNSET 反向锚;承载 D170 §决策 A.2
//   C7 (接口默认参数哨兵): **未实施** — 见 D170 §决策 B C7 行 spec 升级路径段
//                       (v0.1 spike 实证 grep pattern 100% 假阳,需 callsite 判定升级)
//   C8 (英文模式):      扫 bootstrap/lib/tools .ss 找 "workaround" / "FIXME" / "TBD" /
//                       "deferred" / "not yet" 5 个高 signal keyword;
//                       案 v0.1 case-sensitive,case-insensitive 升级留 v0.2
//                       (实证 stub/placeholder 假阳率高排除)
//   C9 (IR-emit-side TODO): 扫 bootstrap/gen/ 找 `emitIR(...)` 内含 TODO/FIXME/XXX
//                       的运行时 IR 携带过渡件
//
//   C5-C9 全软警告 (audit reflection 后逐步升 hard BLOCK,对齐 D097 AUTO-DRIFT 升级路径):
//     默认输出汇总 (每 check N candidates 一行),`--audit` flag 输出详情 file:line
//
// `--phase X` 模式 (D170 §决策 C — Phase Exit Gate manual gate 触发,step 6 落地):
//   filter markers 至匹配 phase X 子集 + 报告 file:line + reason + 按 phase 在 D 文档
//   §下一步 状态判 verdict:
//     [x] Done → BLOCK (phase 完结但 markers 残留,须 clean / upgrade / // PERMANENT)
//     [ ] Planned / [ ] Blocked / [~] In Progress → PASS 软提示报告 (phase 未完结 OK)
//     missing → WARN (verify phase name)
//   触发方式 (D170 §决策 C 双轨):
//     auto-detect = 默认模式 commit-time 跑时附带提示 phase 是否 ready close (留 step 7+)
//     manual gate = commit message footer "Phase X exit verify" → 强制跑 --phase X 模式
//
// 任一 BLOCK → exit 1. 规则单一事实源 = D170 §决策 (本协议 commit f3a93bd 立项).
// sibling linter 模式对齐: tools/d_doc_index_linter.ss / tools/reflection_health_linter.ss
//   / tools/next_prompt_ultrathink_linter.ss (输出格式 + args 处理 + exit code).
//
// 实现注:
//   - SS 无 regex 完整支持,手写 indexOf + charCodeAt parse (sibling
//     d_doc_index_linter scanFile 模式)
//   - § UTF-8 编码 0xC2 0xA7 = 194 167 两字节,charCodeAt 按字节访问
//   - 避 Map<string,string>,用并行 Array<string> (memory project 惯例)

// Status marker (e.g., `[ ] Planned`) must appear at trimmed line position 4
// (after `- **`). Phase name must appear within first PHASE_PROXIMITY_THRESHOLD
// chars of trimmed line to ensure status applies to this phase, not a sibling
// phase mentioned in description text. Typical phase position: 17-30 chars; 50
// is safe upper bound (D093/D170 §下一步 实测 max ~32).
const PHASE_PROXIMITY_THRESHOLD = 50

let markerFiles: Array<string> = []
let markerLines: Array<string> = []
let markerDnums: Array<string> = []
let markerPhases: Array<string> = []
let markerReasons: Array<string> = []
let liveDocs: Array<string> = []

// C5-C9 软警告 parallel arrays (D170 §决策 B C5-C9 step 9 实施):
// 全软警告不 BLOCK,默认输出 N candidates 汇总,`--audit` flag 输出 file:line 详情
let c5Files: Array<string> = []
let c5Lines: Array<string> = []
let c5Matches: Array<string> = []
let c6Files: Array<string> = []
let c6Lines: Array<string> = []
let c6Matches: Array<string> = []
let c8Files: Array<string> = []
let c8Lines: Array<string> = []
let c8Matches: Array<string> = []
let c9Files: Array<string> = []
let c9Lines: Array<string> = []
let c9Matches: Array<string> = []

// 模式 flags:
// enableC5to9 = 1 → 默认 / --audit 跑 C5-C9 扫;= 0 → --phase / 单 target 不跑 C5-C9
// auditMode = 1 → C5-C9 输出详情 file:line;= 0 → 仅汇总 N candidates
let enableC5to9 = 0
let auditMode = 0

function isDigit(c: int): int {
    if (c >= 48) { if (c <= 57) { return 1 } }
    return 0
}

// ============ C5-C9 软警告 scan helpers (D170 §决策 B C5-C9 实施) ============

// C5: D 文档反向锚 — 扫 docs/3-decisions/D*.md §下一步 / Done 注释里
// "留独立轮" / "留下轮" / "留 Phase " 类 forward-looking commitment.
// 承载 D170 §决策 A.3 (D 文档 ↔ 代码 双向锚).
// v0.1 三主 substring pattern;复合正则 (留 X+ / 留 N.N+) 留 v0.2 升级路径.
function scanLineC5(file: string, lineNum: int, text: string) {
    let matched = ""
    if (text.indexOf("留独立轮") >= 0) { matched = "留独立轮" }
    else if (text.indexOf("留下轮") >= 0) { matched = "留下轮" }
    else if (text.indexOf("留 Phase ") >= 0) { matched = "留 Phase" }
    if (matched.length() > 0) {
        c5Files = c5Files.push(file)
        c5Lines = c5Lines.push(`${lineNum}`)
        c5Matches = c5Matches.push(matched)
    }
}

// C6: 协议自循环 — D 文档自身 forward-looking commitment "长期可考虑 X"
// → 关联工具/代码侧必有 SUNSET 反向锚. 承载 D170 §决策 A.2.
// v0.1 单 pattern "长期可考虑";"Phase X+ 优化" 等复合 pattern 与 C5 "留 Phase" 高重叠
// 留 v0.2 升级路径.
function scanLineC6(file: string, lineNum: int, text: string) {
    if (text.indexOf("长期可考虑") >= 0) {
        c6Files = c6Files.push(file)
        c6Lines = c6Lines.push(`${lineNum}`)
        c6Matches = c6Matches.push("长期可考虑")
    }
}

// C8: 英文模式 — 扫 .ss 源码注释 5 个高 signal keyword.
// 案 v0.1 case-sensitive (workaround/FIXME/TBD/deferred/not yet);
// case-insensitive + "stub" / "placeholder" 等高假阳 keyword 升级留 v0.2
// (spike 实证 stub 31 / placeholder 18 大量是普通词义噪声 — 见 D170 §audit 续段 #3).
function scanLineC8(file: string, lineNum: int, text: string) {
    let matched = ""
    if (text.indexOf("workaround") >= 0) { matched = "workaround" }
    else if (text.indexOf("FIXME") >= 0) { matched = "FIXME" }
    else if (text.indexOf("TBD") >= 0) { matched = "TBD" }
    else if (text.indexOf("deferred") >= 0) { matched = "deferred" }
    else if (text.indexOf("not yet") >= 0) { matched = "not yet" }
    if (matched.length() > 0) {
        c8Files = c8Files.push(file)
        c8Lines = c8Lines.push(`${lineNum}`)
        c8Matches = c8Matches.push(matched)
    }
}

// C9: IR-emit-side TODO — 扫 bootstrap/gen/ codegen 输出端
// `emitIR("... TODO/FIXME/XXX ...")` 类运行时 IR 携带过渡件.
// 承载 D170 §audit 续段 #4 (立项 scope 只看源码注释漏 emitIR 输出端).
function scanLineC9(file: string, lineNum: int, text: string) {
    const emitIdx = text.indexOf("emitIR(")
    if (emitIdx < 0) { return }
    // `text.indexOf(X) > emitIdx` = X 在 emitIR( 之后(原子 substring 替代,免 alloc)
    let matched = ""
    if (text.indexOf("TODO") > emitIdx) { matched = "emitIR + TODO" }
    else if (text.indexOf("FIXME") > emitIdx) { matched = "emitIR + FIXME" }
    else if (text.indexOf("XXX") > emitIdx) { matched = "emitIR + XXX" }
    if (matched.length() > 0) {
        c9Files = c9Files.push(file)
        c9Lines = c9Lines.push(`${lineNum}`)
        c9Matches = c9Matches.push(matched)
    }
}

// Parse one line; if it contains a valid `// SUNSET(D<num> §<phase>): <reason>`
// marker, append to parallel arrays. Returns 1 if parsed, 0 otherwise.
//
// D 文档 (docs/3-decisions/D*.md) self-policing skip:不作 SUNSET marker 携带方
// (D170 §决策 A.2 — SUNSET marker 在代码/工具/测试侧;D 文档是 SSoT 仅承载 spec /
// 示范文本不当 real marker).内置 guard 防 future call site re-introduce spec
// 段 false positives (sibling D097 §决策 防漂移自身 hardening).
function parseSunsetLine(file: string, lineNum: int, text: string): int {
    if (file.indexOf("/docs/3-decisions/D") >= 0) {
        if (file.endsWith(".md") == 1) { return 0 }
    }
    const sunsetIdx = text.indexOf("SUNSET(")
    if (sunsetIdx < 0) { return 0 }

    // Require `//` comment prefix before SUNSET on the same line (canonical D170 §A form)
    const commentIdx = text.indexOf("//")
    if (commentIdx < 0) { return 0 }
    if (commentIdx >= sunsetIdx) { return 0 }

    const innerStart = sunsetIdx + 7  // skip "SUNSET("
    const rest = text.substring(innerStart, text.length() - innerStart)
    const closeRelIdx = rest.indexOf(")")
    if (closeRelIdx < 0) { return 0 }  // malformed: unclosed paren

    const innerLen = closeRelIdx
    const inner = text.substring(innerStart, innerLen)

    // Parse `D<NNN>` — D + 3 digits
    if (inner.length() < 5) { return 0 }
    if (inner.charCodeAt(0) != 68) { return 0 }  // 'D'
    const c1 = inner.charCodeAt(1)
    const c2 = inner.charCodeAt(2)
    const c3 = inner.charCodeAt(3)
    if (isDigit(c1) == 0) { return 0 }
    if (isDigit(c2) == 0) { return 0 }
    if (isDigit(c3) == 0) { return 0 }
    const dnum = `D${inner.substring(1, 3)}`

    // After "DNNN", expect " §" (space + UTF-8 § two-byte 194 167)
    if (inner.length() < 7) { return 0 }
    if (inner.charCodeAt(4) != 32 || inner.charCodeAt(5) != 194 || inner.charCodeAt(6) != 167) { return 0 }

    // Phase part starts at inner[7]; ends at next " §" sub-task delim or end of inner
    const phaseStart = 7
    let phaseEnd = inner.length()
    let i = phaseStart
    while (i + 2 < inner.length()) {
        if (inner.charCodeAt(i) == 32 && inner.charCodeAt(i + 1) == 194 && inner.charCodeAt(i + 2) == 167) {
            phaseEnd = i
            break
        }
        i = i + 1
    }
    const phase = inner.substring(phaseStart, phaseEnd - phaseStart)

    // Reason: text after `)`, optionally skip `:`, trim
    let afterCloseIdx = innerStart + innerLen + 1
    if (afterCloseIdx < text.length()) {
        if (text.charCodeAt(afterCloseIdx) == 58) {  // ':'
            afterCloseIdx = afterCloseIdx + 1
        }
    }
    const rawReason = text.substring(afterCloseIdx, text.length() - afterCloseIdx)
    const reason = rawReason.trim()

    markerFiles = markerFiles.push(file)
    markerLines = markerLines.push(`${lineNum}`)
    markerDnums = markerDnums.push(dnum)
    markerPhases = markerPhases.push(phase)
    markerReasons = markerReasons.push(reason)
    return 1
}

function scanFile(path: string) {
    if (fileExists(path) == 0) { return }
    const content = readFile(path)
    if (content == "") { return }
    const lines = content.split("\n")
    // C5-C9 路径分流(enableC5to9 == 1 才跑):
    //   isDoc = docs/3-decisions/D*.md → C5 / C6 (D 文档反向锚 + 协议自循环)
    //   isCode = bootstrap/lib/tools 下 .ss 排除 /tests/ → C8 / C9 (英文模式 + IR-emit TODO)
    // (parseSunsetLine 内部 self-policing 跳 D 文档,无需外部 wrap)
    let isDoc = 0
    let isCode = 0
    if (enableC5to9 == 1) {
        if (path.indexOf("/docs/3-decisions/D") >= 0) {
            if (path.endsWith(".md") == 1) { isDoc = 1 }
        }
        if (path.endsWith(".ss") == 1) {
            if (path.indexOf("/tests/") < 0) { isCode = 1 }
        }
    }
    let li = 0
    while (li < lines.length()) {
        const text = lines[li]
        parseSunsetLine(path, li + 1, text)
        if (isDoc == 1) {
            scanLineC5(path, li + 1, text)
            scanLineC6(path, li + 1, text)
        }
        if (isCode == 1) {
            scanLineC8(path, li + 1, text)
            scanLineC9(path, li + 1, text)
        }
        li = li + 1
    }
}

// Recursive scan; only .ss / .md / .txt (sibling d_doc_index_linter scanDir)
function scanDir(dir: string) {
    if (fileExists(dir) == 0) { return }
    const entries = listDir(dir)
    if (entries == "") { return }
    for (entry in entries.split("\n")) {
        if (entry == "") { continue }
        if (entry.startsWith(".") == 1) { continue }
        const full = `${dir}/${entry}`
        if (entry.endsWith(".ss") == 1) { scanFile(full) }
        else if (entry.endsWith(".md") == 1) { scanFile(full) }
        else if (entry.endsWith(".txt") == 1) { scanFile(full) }
        else if (entry.indexOf(".") < 0) { scanDir(full) }
    }
}

function collectLiveDocs(dir: string) {
    if (fileExists(dir) == 0) { return }
    const entries = listDir(dir)
    if (entries == "") { return }
    for (entry in entries.split("\n")) {
        if (entry == "") { continue }
        if (entry.startsWith("D") == 0) { continue }
        if (entry.endsWith(".md") == 0) { continue }
        if (entry.length() < 4) { continue }
        const c1 = entry.charCodeAt(1)
        const c2 = entry.charCodeAt(2)
        const c3 = entry.charCodeAt(3)
        if (isDigit(c1) == 0) { continue }
        if (isDigit(c2) == 0) { continue }
        if (isDigit(c3) == 0) { continue }
        const num = `D${entry.substring(1, 3)}`
        if (liveDocs.indexOf(num) < 0) { liveDocs = liveDocs.push(num) }
    }
}

function findDDocPath(dnum: string, decisionsDir: string): string {
    if (fileExists(decisionsDir) == 0) { return "" }
    const entries = listDir(decisionsDir)
    if (entries == "") { return "" }
    for (entry in entries.split("\n")) {
        if (entry == "") { continue }
        if (entry.startsWith(dnum) == 0) { continue }
        if (entry.endsWith(".md") == 0) { continue }
        return `${decisionsDir}/${entry}`
    }
    return ""
}

// 状态判: planned > blocked > in_progress > done > missing
// 只看 list-item 起首 50 字符内含 phase 名的行 (status marker 仅对该 phase 适用)
function dDocPhaseStatus(dDocPath: string, phaseName: string): string {
    if (fileExists(dDocPath) == 0) { return "no-d-doc" }
    const content = readFile(dDocPath)
    const lines = content.split("\n")
    let hasPlanned = 0
    let hasBlocked = 0
    let hasInProgress = 0
    let hasDone = 0
    let li = 0
    while (li < lines.length()) {
        const line = lines[li]
        const trimmed = line.trim()
        // Only consider list-item status lines
        if (trimmed.startsWith("- **[") == 1) {
            const phaseIdxLocal = trimmed.indexOf(phaseName)
            if (phaseIdxLocal >= 0) {
                if (phaseIdxLocal < PHASE_PROXIMITY_THRESHOLD) {
                    // Status marker prefix is at chars 4-X of trimmed (right after `- **`)
                    if (trimmed.indexOf("[ ] Planned") == 4) { hasPlanned = 1 }
                    if (trimmed.indexOf("[ ] Blocked") == 4) { hasBlocked = 1 }
                    if (trimmed.indexOf("[~] In Progress") == 4) { hasInProgress = 1 }
                    if (trimmed.indexOf("[x] Done") == 4) { hasDone = 1 }
                }
            }
        }
        li = li + 1
    }
    if (hasPlanned == 1) { return "planned" }
    if (hasBlocked == 1) { return "blocked" }
    if (hasInProgress == 1) { return "in_progress" }
    if (hasDone == 1) { return "done" }
    return "missing"
}

function main() {
    const root = shell("pwd").trim()
    let target = ""
    let phaseFilter = ""

    // `--phase X` mode (D170 §决策 C Phase Exit Gate manual gate 触发):
    //   args 1 == "--phase" + args 2.. = phase name (concat,绕 bin/ss run 拆 quoted
    //   多 token args 限制) → 仅列匹配 phase 的 markers,按该 phase 在 D 文档 §下一步
    //   状态判 (done → BLOCK, planned/blocked/in_progress → PASS 软提示报告,
    //   missing → 软警告)
    if (args() >= 3 && arg(1) == "--phase") {
        phaseFilter = arg(2)
        let pi = 3
        while (pi < args()) {
            phaseFilter = phaseFilter + " " + arg(pi)
            pi = pi + 1
        }
        // phase exit mode 不开 C5-C9(聚焦 phase verdict,避免输出 noise 干扰)
        println(`[sunset_linter] phase exit verify mode — phase: ${phaseFilter}`)
        scanDir(`${root}/bootstrap`)
        scanDir(`${root}/lib`)
        scanDir(`${root}/tools`)
    } else if (args() >= 2 && arg(1) == "--audit") {
        enableC5to9 = 1
        auditMode = 1
        println(`[sunset_linter] audit mode — C1-C4 + C5/C6/C8/C9 详情`)
        scanDir(`${root}/bootstrap`)
        scanDir(`${root}/lib`)
        scanDir(`${root}/tools`)
        scanDir(`${root}/docs/3-decisions`)
    } else if (args() >= 2) {
        // 单 target 不开 C5-C9 — 避免单文件 scope 内 C5-C9 触发本不相关的噪声
        target = arg(1)
        println(`[sunset_linter] target: ${target}`)
        if (target.endsWith(".ss") == 1 || target.endsWith(".md") == 1 || target.endsWith(".txt") == 1) {
            scanFile(target)
        } else {
            scanDir(target)
        }
    } else {
        enableC5to9 = 1
        println(`[sunset_linter] default scan: bootstrap/ lib/ tools/ + docs/3-decisions/ (C5-C9 软警告汇总)`)
        scanDir(`${root}/bootstrap`)
        scanDir(`${root}/lib`)
        scanDir(`${root}/tools`)
        scanDir(`${root}/docs/3-decisions`)
    }

    collectLiveDocs(`${root}/docs/3-decisions`)

    let fails = 0
    const total = markerFiles.length()

    // C1: collection
    println(`  C1: ${total} SUNSET marker(s) found`)
    if (total > 0) {
        let mi = 0
        while (mi < total) {
            println(`    [${markerDnums[mi]} §${markerPhases[mi]}] ${markerFiles[mi]}:${markerLines[mi]}`)
            mi = mi + 1
        }
    }

    // C2: D 文档实存
    let c2Fail = 0
    let mi2 = 0
    while (mi2 < total) {
        const dnum = markerDnums[mi2]
        if (liveDocs.indexOf(dnum) < 0) {
            println(`  C2 FAIL: ${markerFiles[mi2]}:${markerLines[mi2]} references non-existent ${dnum}`)
            c2Fail = c2Fail + 1
        }
        mi2 = mi2 + 1
    }
    if (c2Fail == 0) {
        println(`  C2 PASS: all D docs referenced by SUNSET markers exist`)
    } else {
        fails = fails + c2Fail
    }

    // C3: phase 状态
    let c3Fail = 0
    let c3Warn = 0
    let mi3 = 0
    while (mi3 < total) {
        const dnum = markerDnums[mi3]
        const phase = markerPhases[mi3]
        if (liveDocs.indexOf(dnum) < 0) {
            mi3 = mi3 + 1
            continue
        }
        const dDocPath = findDDocPath(dnum, `${root}/docs/3-decisions`)
        const status = dDocPhaseStatus(dDocPath, phase)
        if (status == "done") {
            println(`  C3 FAIL: ${markerFiles[mi3]}:${markerLines[mi3]} references ${dnum} §${phase} which is [x] Done — marker must be cleaned (or upgraded to a later phase, or replaced with // PERMANENT(...) if永久保留)`)
            c3Fail = c3Fail + 1
        } else if (status == "missing") {
            println(`  C3 WARN: ${markerFiles[mi3]}:${markerLines[mi3]} references ${dnum} §${phase} not found in §下一步 list-item — verify phase name spelling (soft warning, not BLOCK)`)
            c3Warn = c3Warn + 1
        }
        mi3 = mi3 + 1
    }
    if (c3Fail == 0) {
        if (c3Warn == 0) {
            println(`  C3 PASS: all phase references are [ ] Planned / Blocked / [~] In Progress (live)`)
        } else {
            println(`  C3 PASS: all phase references live (${c3Warn} soft warning(s))`)
        }
    } else {
        fails = fails + c3Fail
    }

    // C4: reason 非空
    let c4Fail = 0
    let mi4 = 0
    while (mi4 < total) {
        if (markerReasons[mi4].length() == 0) {
            println(`  C4 FAIL: ${markerFiles[mi4]}:${markerLines[mi4]} has empty reason after \`):\` (D170 §决策 A reason 必填)`)
            c4Fail = c4Fail + 1
        }
        mi4 = mi4 + 1
    }
    if (c4Fail == 0) {
        println(`  C4 PASS: all SUNSET markers have non-empty reason`)
    } else {
        fails = fails + c4Fail
    }

    if (enableC5to9 == 1) {
        println("")
        println("--- C5-C9 软警告(audit 详情用 --audit;C7 见 D170 §决策 B C7 行 spec 升级路径)---")
        const c5N = c5Files.length()
        println(`  C5 (D 文档反向锚 留独立轮/留下轮/留 Phase): ${c5N} candidate(s)`)
        if (auditMode == 1 && c5N > 0) {
            let i5 = 0
            while (i5 < c5N) {
                println(`    ${c5Files[i5]}:${c5Lines[i5]} [${c5Matches[i5]}]`)
                i5 = i5 + 1
            }
        }
        const c6N = c6Files.length()
        println(`  C6 (协议自循环 长期可考虑): ${c6N} candidate(s)`)
        if (auditMode == 1 && c6N > 0) {
            let i6 = 0
            while (i6 < c6N) {
                println(`    ${c6Files[i6]}:${c6Lines[i6]} [${c6Matches[i6]}]`)
                i6 = i6 + 1
            }
        }
        const c8N = c8Files.length()
        println(`  C8 (英文模式 workaround/FIXME/TBD/deferred/not yet): ${c8N} candidate(s)`)
        if (auditMode == 1 && c8N > 0) {
            let i8 = 0
            while (i8 < c8N) {
                println(`    ${c8Files[i8]}:${c8Lines[i8]} [${c8Matches[i8]}]`)
                i8 = i8 + 1
            }
        }
        const c9N = c9Files.length()
        println(`  C9 (IR-emit-side TODO/FIXME/XXX): ${c9N} candidate(s)`)
        if (auditMode == 1 && c9N > 0) {
            let i9 = 0
            while (i9 < c9N) {
                println(`    ${c9Files[i9]}:${c9Lines[i9]} [${c9Matches[i9]}]`)
                i9 = i9 + 1
            }
        }
    }

    // Phase Exit verify (D170 §决策 C — manual gate via --phase X)
    if (phaseFilter != "") {
        println("")
        println(`=== Phase Exit verify — phase: ${phaseFilter} ===`)
        let phaseMatchCount = 0
        let phaseDnum = ""
        let mp = 0
        while (mp < total) {
            if (markerPhases[mp] == phaseFilter) {
                if (phaseDnum == "") { phaseDnum = markerDnums[mp] }
                println(`  marker: ${markerFiles[mp]}:${markerLines[mp]} [${markerDnums[mp]}]`)
                println(`    reason: ${markerReasons[mp]}`)
                phaseMatchCount = phaseMatchCount + 1
            }
            mp = mp + 1
        }
        if (phaseMatchCount == 0) {
            println(`  Phase has 0 SUNSET markers (already clean or no markers for this phase)`)
            println(`Phase Exit verdict: PASS — no cleanup needed for phase '${phaseFilter}'`)
        } else {
            const phaseDDocPath = findDDocPath(phaseDnum, `${root}/docs/3-decisions`)
            const status = dDocPhaseStatus(phaseDDocPath, phaseFilter)
            println("")
            println(`  phase status in ${phaseDnum} §下一步: ${status}`)
            if (status == "done") {
                println(`Phase Exit verdict: BLOCK — phase is [x] Done but ${phaseMatchCount} marker(s) remain — clean / upgrade to later phase / replace with // PERMANENT(<reason>) each marker before declaring phase exit`)
                fails = fails + 1
            } else if (status == "planned") {
                println(`Phase Exit verdict: PASS (phase active [ ] Planned, ${phaseMatchCount} marker(s) awaiting future cleanup) — auto-detect 软提示报告,phase 未完结故 markers OK to remain`)
            } else if (status == "blocked") {
                println(`Phase Exit verdict: PASS (phase active [ ] Blocked, ${phaseMatchCount} marker(s) awaiting future cleanup) — phase blocked but markers tracked`)
            } else if (status == "in_progress") {
                println(`Phase Exit verdict: PASS (phase active [~] In Progress, ${phaseMatchCount} marker(s) awaiting future cleanup) — phase in progress, markers tracked`)
            } else {
                println(`Phase Exit verdict: WARN — phase '${phaseFilter}' not found in ${phaseDnum} §下一步 list-item — verify phase name spelling (soft warning, not BLOCK)`)
            }
        }
    }

    println("")
    println("=======================================")
    if (fails > 0) {
        println(`FAIL: ${fails} issue(s)`)
        if (phaseFilter != "") {
            println(`GATE BLOCKED — Phase Exit verify failed for phase '${phaseFilter}' (or baseline C1-C4 BLOCK)`)
        } else {
            println("GATE BLOCKED — SUNSET marker references dead D doc / phase done / empty reason")
        }
        exit(1)
    }
    if (total == 0) {
        println("GATE OK — 0 SUNSET markers found")
    } else if (phaseFilter != "") {
        println(`GATE OK — Phase Exit verify '${phaseFilter}' passed + baseline ${total} markers all valid`)
    } else {
        println(`GATE OK — ${total} SUNSET marker(s), all valid`)
    }
}
