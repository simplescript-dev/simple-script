// tools/commit_radius_linter.ss — 八股"远距离榨指标"形态的机械标注 gate
//
// Usage:
//   bin/ss run tools/commit_radius_linter.ss
//
// 扫 git diff --name-only HEAD 变动文件集,按前 2 段路径划子族。
// 散点跨 ≥3 无关子族 → FLAG "疑似远距离榨指标"软警告(soft gate, 不阻 commit)。
// 提示 commit message 独立 justify 跨族语义关联,或按任务拆 commit。
// 本 linter 只标注不阻断 —— 判据太粗无法机械判对错,留 human review 窗口。
//
// 规则来源:
//   docs/3-decisions/D126-bagu-process-gates.md §改进 B
//   memory/feedback_no_distant_offset.md
//
// 机械 gate 模式对称 tools/reflection_health_linter.ss / tools/next_prompt_ultrathink_linter.ss。

const RADIUS_THRESHOLD = 3

// SS stdlib substring(start, len) 第二参是长度;substringFrom 让"从 start 到尾"
// 语义一眼可见(对称 tools/reflection_health_linter.ss:70 约定)。
function substringFrom(s: string, start: int): string {
    return s.substring(start, s.length() - start)
}

// 子族 = 前 2 段路径(若存在),否则前 1 段,否则 "<root>"。
//   "bootstrap/gen/class.ss"            → "bootstrap/gen"
//   "tools/reflection_health_linter.ss" → "tools"
//   "docs/3-decisions/D126.md"          → "docs/3-decisions"
//   "README.md"                         → "<root>"
function familyOf(path: string): string {
    const slash1 = path.indexOf("/")
    if (slash1 < 0) { return "<root>" }
    const first = path.substring(0, slash1)
    const rest = substringFrom(path, slash1 + 1)
    if (rest.length() == 0) { return first }
    const slash2 = rest.indexOf("/")
    if (slash2 < 0) { return first }
    return first + "/" + rest.substring(0, slash2)
}

function main() {
    const raw = shell("git diff --name-only HEAD")
    println("[commit_radius_linter] scanning git diff --name-only HEAD ...")

    if (raw == "") {
        println("  no changes (or git not available) — nothing to check")
        println("GATE OK")
        return
    }

    let famSet: Map<string, string> = new Map()
    let totalFiles = 0
    const lines = raw.split("\n")
    let i = 0
    while (i < lines.length()) {
        const line = lines[i]
        if (line != "") {
            const fam = familyOf(line)
            famSet.set(fam, "1")
            totalFiles = totalFiles + 1
        }
        i = i + 1
    }

    const famKeys = famSet.keys()
    const famCount = famKeys.length()
    println(`  files: ${totalFiles} / distinct families: ${famCount}`)
    let j = 0
    while (j < famCount) {
        println(`    ${famKeys[j]}`)
        j = j + 1
    }

    println("")
    println("=======================================")
    if (famCount >= RADIUS_THRESHOLD) {
        println(`FLAG: suspected distant metric offset`)
        println(`  ${famCount} unrelated families >= threshold ${RADIUS_THRESHOLD}`)
        println(`  commit message 必须独立 justify 本次跨族语义关联,或按任务拆 commit。`)
        println(`  参考 feedback_no_distant_offset.md / D126 §改进 B。`)
        println("RADAR SOFT WARN — gate not blocking, human review required")
        return
    }
    println(`PASS: ${famCount} < ${RADIUS_THRESHOLD} families — within local radius`)
    println("GATE OK — no distant offset suspected")
}
