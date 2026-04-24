// tools/commit_footer_bagu_linter.ss — 八股沉积复盘外化到 commit footer 的机械校验
//
// Usage:
//   bin/ss run tools/commit_footer_bagu_linter.ss             # 校验 HEAD
//   bin/ss run tools/commit_footer_bagu_linter.ss <rev>       # 校验指定 commit
//
// VCM §第 5 条 (d) "八股沉积复盘" 要求每项改动过"去掉少什么"元规则。
// 本 linter 外化该要求到 commit footer 格式:
//   每个 diff 涉及的文件 → commit message 必须含一行
//   <file>:<function> — 去掉少什么: <一句话>
//   或对纯文档/配置改动 <file> — 去掉少什么: <一句话>
//
// 匹配判据: commit body 含 "去掉少什么:" 字串 ≥ 1 次。不校验答案质量,
// 只校验**格式强制产出** —— 提高写假答案成本,不负责真假辨别。
//
// 规则来源:
//   docs/3-decisions/D126-bagu-process-gates.md §改进 C
//   memory/feedback_bagu_self_check.md
//   docs/2-principles.md §VCM §第 5 条 (d)
//
// 机械 gate 模式对称 tools/next_prompt_ultrathink_linter.ss。

const SELF_CHECK_MARKER = "去掉少什么:"

function main() {
    let target = "HEAD"
    if (args() >= 2) { target = arg(1) }

    println(`[commit_footer_bagu_linter] target: ${target}`)

    const body = shell(`git log -1 --format=%B ${target}`)
    const diffRaw = shell(`git diff-tree --no-commit-id --name-only -r ${target}`)

    let fileSet: Map<string, string> = new Map()
    const lines = diffRaw.split("\n")
    let i = 0
    while (i < lines.length()) {
        const line = lines[i]
        if (line != "") { fileSet.set(line, "1") }
        i = i + 1
    }
    const fileCount = fileSet.keys().length()
    const hitPos = body.indexOf(SELF_CHECK_MARKER)

    println(`  changed files: ${fileCount}`)
    if (hitPos >= 0) {
        println(`  '${SELF_CHECK_MARKER}' present at pos ${hitPos}`)
    } else {
        println(`  '${SELF_CHECK_MARKER}' ABSENT`)
    }

    println("")
    println("=======================================")
    if (hitPos < 0 && fileCount > 0) {
        println(`FAIL: commit message 缺失 '${SELF_CHECK_MARKER}' 答案行`)
        println("  按 VCM §第 5 条 (d) + MNK §K commit_footer rule 库,每项改动需在 commit footer 写入")
        println(`  <file>:<function> — ${SELF_CHECK_MARKER} <一句话>`)
        println(`  或对纯文档/配置改动 <file> — ${SELF_CHECK_MARKER} <一句话>`)
        println("GATE BLOCKED")
        exit(1)
    }
    println("PASS: commit footer 含八股自检答案行")
    println("GATE OK")
}
