// tools/sunset_linter.ss — D170 SUNSET marker 过渡债漂移机械 gate
//
// Usage:
//   bin/ss run tools/sunset_linter.ss              # 默认扫 bootstrap/ lib/ tools/
//   bin/ss run tools/sunset_linter.ss <path>       # 扫单文件或单目录(测试用)
//
// 默认模式 C1-C4 (D170 §决策 B):
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
// C5 (`--phase X` Phase Exit Gate) 留 D170 §下一步 step 6 实施.
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

function isDigit(c: int): int {
    if (c >= 48) { if (c <= 57) { return 1 } }
    return 0
}

// Parse one line; if it contains a valid `// SUNSET(D<num> §<phase>): <reason>`
// marker, append to parallel arrays. Returns 1 if parsed, 0 otherwise.
function parseSunsetLine(file: string, lineNum: int, text: string): int {
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
    let li = 0
    while (li < lines.length()) {
        parseSunsetLine(path, li + 1, lines[li])
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

    if (args() >= 2) {
        target = arg(1)
        println(`[sunset_linter] target: ${target}`)
        if (target.endsWith(".ss") == 1 || target.endsWith(".md") == 1 || target.endsWith(".txt") == 1) {
            scanFile(target)
        } else {
            scanDir(target)
        }
    } else {
        println(`[sunset_linter] default scan: bootstrap/ lib/ tools/`)
        scanDir(`${root}/bootstrap`)
        scanDir(`${root}/lib`)
        scanDir(`${root}/tools`)
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

    println("")
    println("=======================================")
    if (fails > 0) {
        println(`FAIL: ${fails} issue(s)`)
        println("GATE BLOCKED — SUNSET marker references dead D doc / phase done / empty reason")
        exit(1)
    }
    if (total == 0) {
        println("GATE OK — 0 SUNSET markers found")
    } else {
        println(`GATE OK — ${total} SUNSET marker(s), all valid`)
    }
}
