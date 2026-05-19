// bug_options_linter.ss - mechanical verification of bug-fix options comparison table
// Usage: bin/ss build tools/bug_options_linter.ss -o /tmp/bug_options_linter
//        /tmp/bug_options_linter <bug-name>.options.md
//
// 校验 bug 修复方案对比表的形式合规(MNK §特定领域 §Bug 修复 Harness §轨 1):
//   C1 文件存在
//   C2 候选数 ≥ 3(标识:行首 `| A |` / `| B |` / `| C |` 或 `**A**:` / `**B**:` / `**C**:`)
//   C3 含 ≥ 3 个层次标识(数据 / 接口 / 架构 任一字面值)
//   C4 含决策行(`选 [A-Z]` + `因` 关键字共存)
//   C5 含"假设破裂"标识(消除 假设 X 在 Y 状态下破裂 / 假设破裂入口 等表述)
//   C6 含 §实证 段(MNK §字段 12):根因定位 grep 证据 + 最危险假设的最小 spike 结果
//
// linter 仅查"形式存在",不查"内容深度";内容深度由用户抽查兜底(轨 2 留下轮)。

function countCandidatesByPipe(content: string): int {
    const lines = content.split("\n")
    let n = 0
    let i = 0
    while (i < lines.length()) {
        const line = lines[i].trim()
        if (line.startsWith("| A |") == 1) { n = n + 1 }
        else if (line.startsWith("| B |") == 1) { n = n + 1 }
        else if (line.startsWith("| C |") == 1) { n = n + 1 }
        else if (line.startsWith("| D |") == 1) { n = n + 1 }
        else if (line.startsWith("| E |") == 1) { n = n + 1 }
        i = i + 1
    }
    return n
}

function countCandidatesByBold(content: string): int {
    let n = 0
    if (content.indexOf("**A**") >= 0) { n = n + 1 }
    if (content.indexOf("**B**") >= 0) { n = n + 1 }
    if (content.indexOf("**C**") >= 0) { n = n + 1 }
    if (content.indexOf("**D**") >= 0) { n = n + 1 }
    if (content.indexOf("**E**") >= 0) { n = n + 1 }
    return n
}

function countSubstr(content: string, sub: string): int {
    let n = 0
    let cur = content
    let guard = 0
    while (guard < 1000) {
        const idx = cur.indexOf(sub)
        if (idx < 0) { return n }
        n = n + 1
        cur = cur.substring(idx + sub.length(), cur.length())
        guard = guard + 1
    }
    return n
}

function countLayerTokens(content: string): int {
    return countSubstr(content, "数据") + countSubstr(content, "接口") + countSubstr(content, "架构")
}

function hasDecisionLine(content: string): int {
    // 决策行 pattern: "选 X 因 Y" 或 "选 <X> 因 <Y>"
    const lines = content.split("\n")
    let i = 0
    while (i < lines.length()) {
        const line = lines[i]
        if (line.indexOf("选") >= 0 && line.indexOf("因") >= 0) { return 1 }
        i = i + 1
    }
    return 0
}

function hasAssumptionBreak(content: string): int {
    if (content.indexOf("假设破裂") >= 0) { return 1 }
    if (content.indexOf("假设") >= 0 && content.indexOf("破裂") >= 0) { return 1 }
    return 0
}

// C6 — §实证 段:根因定位 grep 证据 + 最危险假设的最小 spike 结果(MNK §字段 12)。
// 机械查"字样存在":实证段标记 + grep 证据 + spike/试切。
function hasEvidenceSection(content: string): int {
    if (content.indexOf("实证") < 0) { return 0 }
    if (content.indexOf("grep") < 0) { return 0 }
    if (content.indexOf("spike") < 0 && content.indexOf("试切") < 0) { return 0 }
    return 1
}

function main() {
    if (args() < 2) {
        println("usage: bin/ss build tools/bug_options_linter.ss -o /tmp/bug_options_linter")
        println("       /tmp/bug_options_linter <bug>.options.md")
        exit(1)
    }
    const path = arg(1)
    if (fileExists(path) != 1) {
        println(`FAIL C1: file not found: ${path}`)
        exit(1)
    }
    println(`[bug_options_linter] target: ${path}`)
    println("  C1 PASS: file exists")

    const content = readFile(path)
    let pass = 1

    const nByPipe = countCandidatesByPipe(content)
    const nByBold = countCandidatesByBold(content)
    const nCand = nByPipe > nByBold ? nByPipe : nByBold
    if (nCand >= 3) {
        println(`  C2 PASS: candidates=${nCand} (>= 3)`)
    } else {
        println(`  C2 FAIL: candidates=${nCand} (must be >= 3, use \`| A | ... |\` rows or \`**A**:\` markers)`)
        pass = 0
    }

    const nLayer = countLayerTokens(content)
    if (nLayer >= 3) {
        println(`  C3 PASS: layer-tokens=${nLayer} (数据/接口/架构 出现 >= 3 次)`)
    } else {
        println(`  C3 FAIL: layer-tokens=${nLayer} (must include 数据/接口/架构 across candidates >= 3 times)`)
        pass = 0
    }

    if (hasDecisionLine(content) == 1) {
        println("  C4 PASS: decision line present (选 X 因 Y)")
    } else {
        println("  C4 FAIL: decision line missing (must contain '选 ... 因 ...' phrase)")
        pass = 0
    }

    if (hasAssumptionBreak(content) == 1) {
        println("  C5 PASS: assumption-break marker present (假设破裂)")
    } else {
        println("  C5 FAIL: assumption-break marker missing (must contain '假设破裂' or '假设' + '破裂')")
        pass = 0
    }

    if (hasEvidenceSection(content) == 1) {
        println("  C6 PASS: evidence section present (实证 + grep + spike/试切)")
    } else {
        println("  C6 FAIL: evidence section missing (MNK §字段 12 — need '实证' section + 'grep' proof + 'spike'/'试切')")
        pass = 0
    }

    println("")
    println("=======================================")
    if (pass == 1) {
        println("PASS: 6/6")
        println("GATE OK — bug-fix Execute 可启动")
    } else {
        println("GATE BLOCKED — options.md 形式不合规,补全后重跑")
        exit(1)
    }
}
