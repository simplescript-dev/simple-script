// next_prompt_ultrathink_linter.ss — PFV 收尾 gate 的机械校验
//
// Usage:
//   bin/ss run tools/next_prompt_ultrathink_linter.ss
//   bin/ss run tools/next_prompt_ultrathink_linter.ss /tmp/fake_prompt.md
//
// 三检查:
//   C1: 目标文件存在
//   C2: 非空(trim 后长度 > 0)
//   C3: 内容含关键字 "ultrathink"(小写 exact)
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

    println("")
    println("=======================================")
    if (fails > 0) {
        println(`FAIL: ${fails}`)
        println("GATE BLOCKED — missing / empty / non-ultrathink payload means the next round will run without deep reasoning")
        exit(1)
    }
    println("PASS: 3/3")
    println("GATE OK — next round will be invoked with ultrathink")
}
