// tools/derived_issue_linter.ss — 衍生 issue 归档 gate 的机械校验
//
// Usage:
//   bin/ss run tools/derived_issue_linter.ss
//
// 扫 commit msg(HEAD~3..)、staged diff、.claude/next_prompt.md、current git diff
// 找形如 IXXX / IXXXa / IXXXb 的 issue 引用(3 位数字 + 可选 1 位字母后缀),
// 对照 docs/4-issues/ 下 .md 文件存在性。
//
// 失败条件:
//   F1: 文本出现 IXXX 但 docs/4-issues/IXXX-*.md 不存在
//   F2(soft): 文本出现"衍生问题/后续 issue/下轮修/下轮处理"但未跟 IXXX 编号
//
// 规则来源: docs/3-MNK.md §特定领域 §衍生 issue 归档。
// 机械 gate 模式对称 tools/next_prompt_ultrathink_linter.ss / tools/commit_radius_linter.ss。
//
// 引用 pattern 限制: I + 3 位数字 + 可选单字母后缀,前后必须是非字母数字边界
// (避免误触 "ICXXX"、"InnerX"、"Issue3"、"I003b_value" 前缀的识别)。

function isDigit(code: int): int {
    if (code >= 48 && code <= 57) { return 1 }
    return 0
}

function isLower(code: int): int {
    if (code >= 97 && code <= 122) { return 1 }
    return 0
}

function isWordChar(code: int): int {
    if (isDigit(code) == 1) { return 1 }
    if (isLower(code) == 1) { return 1 }
    if (code >= 65 && code <= 90) { return 1 }  // A-Z
    if (code == 95) { return 1 }                 // _
    return 0
}

// 扫字符串里所有合法 IXXX 引用,加入 Map(key = "I003" / "I003b", val = "1")
function collectIssueRefs(src: string, seen: Map<string, string>) {
    const n = src.length()
    let i = 0
    while (i < n) {
        const c = charCodeAt(src, i)
        // 'I' = 73
        if (c == 73) {
            // 前边界 = 字符串头 或 非 word char
            let leftOk = 1
            if (i > 0) {
                const prev = charCodeAt(src, i - 1)
                if (isWordChar(prev) == 1) { leftOk = 0 }
            }
            if (leftOk == 1 && i + 3 < n) {
                const d1 = charCodeAt(src, i + 1)
                const d2 = charCodeAt(src, i + 2)
                const d3 = charCodeAt(src, i + 3)
                if (isDigit(d1) == 1 && isDigit(d2) == 1 && isDigit(d3) == 1) {
                    let endIdx = i + 4
                    let suffix = ""
                    if (endIdx < n) {
                        const sc = charCodeAt(src, endIdx)
                        if (isLower(sc) == 1) {
                            // 检后一位不是 word char(单字母后缀才算)
                            if (endIdx + 1 >= n || isWordChar(charCodeAt(src, endIdx + 1)) == 0) {
                                suffix = src.substring(endIdx, 1)
                                endIdx = endIdx + 1
                            }
                        }
                    }
                    // 后边界 = 字符串尾 或 非 word char
                    let rightOk = 1
                    if (endIdx < n) {
                        const next = charCodeAt(src, endIdx)
                        if (isWordChar(next) == 1) { rightOk = 0 }
                    }
                    if (rightOk == 1) {
                        const ref = `I${src.substring(i + 1, 3)}${suffix}`
                        seen.set(ref, "1")
                        i = endIdx
                        continue
                    }
                }
            }
        }
        i = i + 1
    }
}

// 扫 docs/4-issues/ 目录,把存在的 IXXX 编号收进 Map
function collectArchivedIssues(archived: Map<string, string>) {
    const dir = "docs/4-issues"
    if (fileExists(dir) == 0) { return }
    const entries = listDir(dir)
    if (entries == "") { return }
    for (entry in entries.split("\n")) {
        if (entry == "") { continue }
        if (entry.endsWith(".md") == 0) { continue }
        // 形如 "I003-xxx.md" / "I003b-xxx.md";取第一段 hyphen 前
        const dash = entry.indexOf("-")
        if (dash < 0) { continue }
        const idPart = entry.substring(0, dash)
        archived.set(idPart, "1")
    }
}

function main() {
    println("[derived_issue_linter] scanning issue refs ...")

    let seen: Map<string, string> = new Map()

    // 源 1: 近 3 commit message
    const logOut = shell("git log --format=%B HEAD~3..HEAD 2>/dev/null")
    collectIssueRefs(logOut, seen)

    // 源 2: staged diff(准备 commit 的)+ 限制 ≤ 2MB 防 SS 扫描 OOM
    const stagedOut = shell("git diff --cached 2>/dev/null")
    if (stagedOut.length() < 2097152) { collectIssueRefs(stagedOut, seen) }

    // 源 3: .claude/next_prompt.md
    const nextPath = ".claude/next_prompt.md"
    if (fileExists(nextPath) == 1) {
        collectIssueRefs(readFile(nextPath), seen)
    }

    // 注: 不扫 `git diff`(unstaged) —— 大范围删除噪音易推高到 MB 级,
    // linter 设计是 "commit 前跑",此时 staged 已含将提交内容。

    let archived: Map<string, string> = new Map()
    collectArchivedIssues(archived)

    const seenKeys = seen.keys()
    println(`  issue refs found: ${seenKeys.length()}`)
    println(`  archived issues:  ${archived.size()}`)

    let missing: Array<string> = []
    let k = 0
    while (k < seenKeys.length()) {
        const ref = seenKeys[k]
        if (archived.has(ref) == 0) { missing = missing.push(ref) }
        k = k + 1
    }

    // soft hint: 衍生问题关键词无 IXXX 邻接
    const hintSrc = `${logOut}\n${stagedOut}`
    let hitHint = 0
    if (hintSrc.indexOf("衍生问题") >= 0) { hitHint = 1 }
    if (hintSrc.indexOf("后续 issue") >= 0) { hitHint = 1 }
    if (hintSrc.indexOf("下轮修") >= 0) { hitHint = 1 }
    if (hintSrc.indexOf("下轮处理") >= 0) { hitHint = 1 }
    let softWarn = 0
    if (hitHint == 1 && seenKeys.length() == 0) { softWarn = 1 }

    println("")
    println("=======================================")
    if (missing.length() > 0) {
        println(`FAIL: ${missing.length()} issue ref(s) without archived file`)
        let m = 0
        while (m < missing.length()) {
            println(`  missing: docs/4-issues/${missing[m]}-*.md`)
            m = m + 1
        }
        println("GATE BLOCKED — derived issue text reference without archive file")
        println("  补写 docs/4-issues/IXXX-*.md 再 commit,或删文本里的 IXXX 引用")
        exit(1)
    }
    if (softWarn == 1) {
        println("SOFT WARN: 文本出现'衍生/后续/下轮处理'但无 IXXX 编号")
        println("  若真有衍生问题,请显式编号并开 issue 文件(§MNK 衍生 issue 归档)")
    }
    println(`PASS: ${seenKeys.length()} issue ref(s), all archived`)
    println("GATE OK — all derived issue refs are properly archived")
}
