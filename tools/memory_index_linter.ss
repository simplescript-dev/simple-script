// tools/memory_index_linter.ss — MEMORY.md 索引 vs feedback_*.md 文件一一对应校验
//
// Usage:
//   bin/ss run tools/memory_index_linter.ss
//   bin/ss run tools/memory_index_linter.ss /custom/memory/dir
//
// 失败条件:
//   F1: MEMORY.md 索引行 [feedback_X.md] 但 feedback_X.md 不存在(索引漂移)
//   F2(soft): feedback_X.md 存在但 MEMORY.md 无索引行(孤立文件)
//
// 规则来源: docs/3-MNK.md §特定领域 §memory 治理 gate(2026-04-24 反思候选 3 落位)。
// 机械 gate 模式对称 tools/derived_issue_linter.ss(IXXX 引用 vs docs/4-issues/ 存在)。

function getDefaultDir(): string {
    const home = shell("echo -n $HOME").trim()
    return `${home}/.claude/projects/-root-code-simplescript-dev-simple-script/memory`
}

// 解析 MEMORY.md 内 [feedback_X.md](feedback_X.md) pattern 收集索引引用
function collectIndexRefs(content: string, seen: Map<string, string>) {
    const n = content.length()
    let i = 0
    while (i < n) {
        if (i + 10 < n && content.substring(i, 10) == "[feedback_") {
            const rest = content.substring(i, n - i)
            const offset = rest.indexOf(".md]")
            if (offset >= 0) {
                const tail = i + offset
                const name = content.substring(i + 1, tail - i - 1) + ".md"
                seen.set(name, "1")
                i = tail + 4
                continue
            }
        }
        i = i + 1
    }
}

// 列 dir 内所有 feedback_*.md 文件名
function collectFiles(dir: string, files: Map<string, string>) {
    if (fileExists(dir) == 0) { return }
    const entries = listDir(dir)
    if (entries == "") { return }
    for (entry in entries.split("\n")) {
        if (entry == "") { continue }
        if (entry.startsWith("feedback_") == 0) { continue }
        if (entry.endsWith(".md") == 0) { continue }
        files.set(entry, "1")
    }
}

function main() {
    let dir = getDefaultDir()
    if (args() >= 2) { dir = arg(1) }
    const memPath = `${dir}/MEMORY.md`

    println(`[memory_index_linter] memory dir: ${dir}`)

    if (fileExists(memPath) == 0) {
        println(`  C0 FAIL: MEMORY.md not found at ${memPath}`)
        exit(1)
    }

    let indexed: Map<string, string> = new Map()
    collectIndexRefs(readFile(memPath), indexed)

    let files: Map<string, string> = new Map()
    collectFiles(dir, files)

    const indexedKeys = indexed.keys()
    const fileKeys = files.keys()
    println(`  indexed refs:   ${indexedKeys.length()}`)
    println(`  feedback files: ${fileKeys.length()}`)

    let missing: Array<string> = []
    let i = 0
    while (i < indexedKeys.length()) {
        const name = indexedKeys[i]
        if (files.has(name) == 0) { missing = missing.push(name) }
        i = i + 1
    }

    let orphan: Array<string> = []
    let j = 0
    while (j < fileKeys.length()) {
        const name = fileKeys[j]
        if (indexed.has(name) == 0) { orphan = orphan.push(name) }
        j = j + 1
    }

    println("")
    println("=======================================")
    if (missing.length() > 0) {
        println(`FAIL: ${missing.length()} indexed ref(s) without file`)
        let m = 0
        while (m < missing.length()) {
            println(`  missing file: ${missing[m]}`)
            m = m + 1
        }
        println("GATE BLOCKED — MEMORY.md 索引漂移(指针指向不存在的文件)")
        println("  当轮修 MEMORY.md 删该索引行,或恢复对应 memory 文件")
        exit(1)
    }
    if (orphan.length() > 0) {
        println(`SOFT WARN: ${orphan.length()} feedback file(s) without index`)
        let o = 0
        while (o < orphan.length()) {
            println(`  orphan: ${orphan[o]}`)
            o = o + 1
        }
        println("  这些文件存在但 MEMORY.md 无索引行 — 跨 session 不会被自动加载")
    }
    println(`PASS: ${indexedKeys.length()} indexed = ${fileKeys.length() - orphan.length()} matched files`)
    println("GATE OK — MEMORY.md 索引与 feedback files 一一对应")
}
