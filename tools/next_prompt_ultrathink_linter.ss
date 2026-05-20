// next_prompt_ultrathink_linter.ss — PFV 收尾 gate 的机械校验
//
// Usage:
//   bin/ss run tools/next_prompt_ultrathink_linter.ss
//   bin/ss run tools/next_prompt_ultrathink_linter.ss /tmp/fake_prompt.md
//
// 五检查:
//   C1: 目标文件存在
//   C2: 非空(trim 后长度 > 0)
//   C3: 内容含关键字 "ultrathink"(小写 exact)
//   C4: 标题(第一行 #)不得声明 "docs only" / "docs-only"
//       — 防止 self-recursive next_prompt 陷入 docs-only 空转循环
//       — 用户对话实证 D154 Phase 0-17 18 轮 zero LOC code 历史教训
//       — 真正的 docs-only 工作必须由用户手写 prompt,不走 self-recursive 接力
//   C5: 分支核心目标对齐(与 PSM §字段 13 联动)
//       — `git branch --show-current` 提取 doc-id 关键字段(去 feat/fix/refactor 前缀 + 按 - 切片)
//       — next_prompt 必须命中任一段(lowercase substring) **或** 含显式偏离声明
//         (`[偏离 ` / `⚠ 偏离` / `分支偏离` / `[⚠ 偏离`)
//       — trunk 分支(main/master/dev)或无 `/` 前缀(非 feature 命名)→ C5 SKIP
//       — 防止跨轮 inherit 偏离静悄悄传播:本次实测 2026-05-20 `feat/d092-sema-q1` 分支
//         5 个月内 SEMA Q1 主线 0 commit,next_prompt 继承 Tier 主线 tests cleanup 偏离链
//         (D113→D168→I023-31→Tier1-5),`comptimeDepth>0` 分岔从 40 涨到 54(+35% 反向倒退)
//
// 任一 FAIL → exit 1。默认目标 = .claude/next_prompt.md。
//
// 规则来源: docs/2-principles.md §收尾 gate §下一步提示词 (b) + memory/feedback_ultrathink_gate.md
//          + docs/3-MNK.md §M §字段 13 分支核心目标对齐 ultrathink。
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

    // C5: 分支核心目标对齐(与 PSM §字段 13 联动)
    let branch = shell("git branch --show-current").trim().toLowerCase()
    let c5Skip = 0
    let c5Reason = ""
    if (branch == "main") { c5Skip = 1; c5Reason = "trunk branch (main)" }
    if (branch == "master") { c5Skip = 1; c5Reason = "trunk branch (master)" }
    if (branch == "dev") { c5Skip = 1; c5Reason = "trunk branch (dev)" }
    if (c5Skip == 0 && branch.indexOf("/") < 0) {
        c5Skip = 1
        c5Reason = `branch '${branch}' has no '/' prefix (non-feature convention)`
    }
    if (c5Skip == 1) {
        println(`  C5 SKIP: ${c5Reason}`)
    } else {
        let c5Hit = 0
        let c5HitReason = ""
        // 显式偏离声明优先(中文 + ⚠ 无大小写,直接 content;canonical 形 `[⚠ 偏离 ...]` 由 `⚠ 偏离` 子串覆盖)
        if (content.indexOf("[偏离 ") >= 0) { c5Hit = 1; c5HitReason = "explicit deviation declared '[偏离 ...]'" }
        if (c5Hit == 0 && content.indexOf("⚠ 偏离") >= 0) { c5Hit = 1; c5HitReason = "explicit deviation declared '⚠ 偏离'" }
        if (c5Hit == 0 && content.indexOf("分支偏离") >= 0) { c5Hit = 1; c5HitReason = "explicit deviation declared '分支偏离'" }
        // 否则匹配分支 doc-id 关键字段(doc-id 可能 MixedCase 如 D092,需 lowercase 比较)
        if (c5Hit == 0) {
            let lowerContent = content.toLowerCase()
            let slashIdx = branch.indexOf("/")
            let suffix = branch.substring(slashIdx + 1, branch.length())
            let parts = suffix.split("-")
            let i = 0
            while (i < parts.length()) {
                let part = parts[i]
                if (part.length() >= 2 && lowerContent.indexOf(part) >= 0) {
                    c5Hit = 1
                    c5HitReason = `branch keyword '${part}' present`
                    break
                }
                i = i + 1
            }
        }
        if (c5Hit == 1) {
            println(`  C5 PASS: ${c5HitReason} (branch '${branch}')`)
        } else {
            println(`  C5 FAIL: branch '${branch}' core target keywords absent in next_prompt, and no explicit '[偏离 <target>]' / '⚠ 偏离' / '分支偏离' declaration — payload silently drifts from branch commitment (与 PSM §字段 13 联动 — 加显式标签或 stop 让用户授权)`)
            fails = fails + 1
        }
    }

    println("")
    println("=======================================")
    if (fails > 0) {
        println(`FAIL: ${fails}`)
        println("GATE BLOCKED — payload missing / empty / non-ultrathink / declares docs-only spin / drifts from branch core target")
        exit(1)
    }
    println("PASS: 5/5")
    println("GATE OK — next round will be invoked with ultrathink, points to code change tasks, and aligns with branch core target")
}
