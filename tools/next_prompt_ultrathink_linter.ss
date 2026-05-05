// next_prompt_ultrathink_linter.ss — PFV 收尾 gate 的机械校验
//
// Usage:
//   bin/ss run tools/next_prompt_ultrathink_linter.ss
//   bin/ss run tools/next_prompt_ultrathink_linter.ss /tmp/fake_prompt.md
//
// 四检查:
//   C1: 目标文件存在
//   C2: 非空(trim 后长度 > 0)
//   C3: 内容含关键字 "ultrathink"(小写 exact)
//   C4: 标题(第一行 #)不得声明 "docs only" / "docs-only"
//       — 防止 self-recursive next_prompt 陷入 docs-only 空转循环
//       — 用户对话实证 D154 Phase 0-17 18 轮 zero LOC code 历史教训
//       — 真正的 docs-only 工作必须由用户手写 prompt,不走 self-recursive 接力
//
// 任一 FAIL → exit 1。默认目标 = .claude/next_prompt.md。
//
// 规则来源: docs/2-principles.md §收尾 gate §下一步提示词 (b) + memory/feedback_ultrathink_gate.md。
// 机械 gate 模式对称 tools/bugfix_linter.ss / tools/reflection_health_linter.ss。

function main() {
    let path = ".claude/next_prompt.md"
    if (args() >= 2) { path = arg(1) }

    println(`[next_prompt_ultrathink_linter] target: ${path}`)

    let fails = 0
    let content = ""

    if (fileExists(path) != 1) {
        println("  C1 FAIL: file does not exist")
        fails = fails + 1
    } else {
        println("  C1 PASS: file exists")
        content = readFile(path)
    }

    if (content.trim().length() == 0) {
        println("  C2 FAIL: file is empty or whitespace-only")
        fails = fails + 1
    } else {
        println(`  C2 PASS: non-empty (${content.length()} chars)`)
    }

    if (content.indexOf("ultrathink") < 0) {
        println("  C3 FAIL: keyword 'ultrathink' not found")
        fails = fails + 1
    } else {
        println("  C3 PASS: keyword 'ultrathink' present")
    }

    let firstNewline = content.indexOf("\n")
    let firstLine = content
    if (firstNewline >= 0) {
        firstLine = content.substring(0, firstNewline)
    }
    let firstLineLower = firstLine.toLowerCase()
    let c4Hit = 0
    if (firstLineLower.indexOf("docs only") >= 0) { c4Hit = 1 }
    if (firstLineLower.indexOf("docs-only") >= 0) { c4Hit = 1 }
    if (c4Hit == 1) {
        println("  C4 FAIL: title declares 'docs only' / 'docs-only' — self-recursive next_prompt must point to code change tasks, not docs-only spin (see D154 Phase 0-17 18-round zero-LOC history)")
        fails = fails + 1
    } else {
        println("  C4 PASS: title does not declare docs-only")
    }

    println("")
    println("=======================================")
    if (fails > 0) {
        println(`FAIL: ${fails}`)
        println("GATE BLOCKED — payload missing / empty / non-ultrathink / declares docs-only spin")
        exit(1)
    }
    println("PASS: 4/4")
    println("GATE OK — next round will be invoked with ultrathink and points to code change tasks")
}
