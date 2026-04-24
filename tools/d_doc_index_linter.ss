// tools/d_doc_index_linter.ss — bootstrap/tools/CLAUDE.md/docs/3-MNK.md 的 D 引用 vs docs/3-decisions/ 实存校验
//
// Usage:
//   bin/ss run tools/d_doc_index_linter.ss
//   bin/ss run tools/d_doc_index_linter.ss /custom/project/root
//
// 失败条件:
//   C0: CLAUDE.md / docs/3-MNK.md 不存在(路径错或文件缺失,硬 FAIL)
//   F1: 扫描路径里出现 `D\d{3}\s*§` 引用但 docs/3-decisions/D\d{3}*.md 不存在(死指针 BLOCK)
//   F2(soft): docs/3-decisions/D\d{3}*.md 存在但 4 路径扫描无任何 §-form 引用(孤立 D 文档)
//
// 规则来源: docs/3-MNK.md §特定领域 §D 文档治理 gate(对称 §memory 治理 gate)。
// 机械 gate 模式对称 tools/memory_index_linter.ss(MEMORY.md 索引 vs feedback_*.md 存在)。
//
// 扫描 scope 刻意不含 docs/3-decisions/ 自身:D 文档互引是历史演进痕迹,合法保留。
// pattern 刻意限 § 后缀:`DNNN#` 形态(linter_baseline.txt bump trail)是 commit footer 式溯源戳,非规则引用。
//
// 实现注: 避开 Map<string,string>(simplescript 运行时 Map.get string value 返指针非字符串 bug),
// 改用全局两个平行 Array<string>:foundNums 记 D 号,foundLocs 同 index 记 `file:line` 首见位置。

let live: Array<string> = []
let foundNums: Array<string> = []
let foundLocs: Array<string> = []

function getDefaultRoot(): string {
    return shell("pwd").trim()
}

function isDigit(c: int): int {
    if (c >= 48) { if (c <= 57) { return 1 } }
    return 0
}

// § 的 UTF-8 编码:0xC2 0xA7 = 194, 167(两字节)。simplescript 字符串按字节索引。
// 扫一个文件里 D\d{3}\s*§ pattern,新 D 号 append 到全局 foundNums + foundLocs(并行)。
function scanFile(path: string) {
    const content = readFile(path)
    const n = content.length()
    let i = 0
    let line = 1
    while (i < n) {
        const code = content.charCodeAt(i)
        if (code == 10) {
            line = line + 1
            i = i + 1
            continue
        }
        if (code == 68 && i + 5 <= n) {
            const c1 = content.charCodeAt(i + 1)
            const c2 = content.charCodeAt(i + 2)
            const c3 = content.charCodeAt(i + 3)
            if (isDigit(c1) == 1 && isDigit(c2) == 1 && isDigit(c3) == 1) {
                let j = i + 4
                while (j < n) {
                    if (content.charCodeAt(j) == 32) { j = j + 1 } else { break }
                }
                if (j + 1 < n && content.charCodeAt(j) == 194 && content.charCodeAt(j + 1) == 167) {
                    const num = `D${content.substring(i + 1, 3)}`
                    if (foundNums.indexOf(num) < 0) {
                        foundNums = foundNums.push(num)
                        foundLocs = foundLocs.push(`${path}:${line}`)
                    }
                    i = j + 2
                    continue
                }
            }
        }
        i = i + 1
    }
}

// 递归扫目录下 .ss / .md / .txt 文件(参考 reflection_health_linter.ss collectSSFiles 惯例:
// listDir 对非目录返空串;按后缀判文件,否则递归当子目录)
function scanDir(dir: string) {
    const entries = listDir(dir)
    if (entries == "") { return }
    for (entry in entries.split("\n")) {
        if (entry == "") { continue }
        if (entry.startsWith(".") == 1) { continue }
        const full = `${dir}/${entry}`
        if (entry.endsWith(".ss") == 1) { scanFile(full) }
        else if (entry.endsWith(".md") == 1) { scanFile(full) }
        else if (entry.endsWith(".txt") == 1) { scanFile(full) }
        else { scanDir(full) }
    }
}

// 列 docs/3-decisions/ 下的 D\d{3} 号到全局 live
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
        if (live.indexOf(num) < 0) { live = live.push(num) }
    }
}

function assertFileExists(path: string) {
    if (fileExists(path) == 0) {
        println(`  C0 FAIL: required file missing at ${path}`)
        exit(1)
    }
}

function main() {
    let root = getDefaultRoot()
    if (args() >= 2) { root = arg(1) }

    println(`[d_doc_index_linter] project root: ${root}`)

    collectLiveDocs(`${root}/docs/3-decisions`)

    const claudeMd = `${root}/CLAUDE.md`
    const mnkMd = `${root}/docs/3-MNK.md`
    assertFileExists(claudeMd)
    assertFileExists(mnkMd)

    scanDir(`${root}/bootstrap`)
    scanDir(`${root}/tools`)
    scanFile(claudeMd)
    scanFile(mnkMd)

    println(`  live D docs:    ${live.length()}`)
    println(`  referenced Ds:  ${foundNums.length()}`)

    let deadNums: Array<string> = []
    let deadLocs: Array<string> = []
    let f = 0
    while (f < foundNums.length()) {
        const num = foundNums[f]
        if (live.indexOf(num) < 0) {
            deadNums = deadNums.push(num)
            deadLocs = deadLocs.push(foundLocs[f])
        }
        f = f + 1
    }

    let orphan: Array<string> = []
    let l = 0
    while (l < live.length()) {
        const num = live[l]
        if (foundNums.indexOf(num) < 0) { orphan = orphan.push(num) }
        l = l + 1
    }

    println("")
    println("=======================================")
    if (deadNums.length() > 0) {
        println(`FAIL: ${deadNums.length()} dead D-doc reference(s)`)
        let d = 0
        while (d < deadNums.length()) {
            println(`  dead ref: ${deadNums[d]} §  first seen at ${deadLocs[d]}`)
            d = d + 1
        }
        println("GATE BLOCKED — D 文档死指针(§-form 引用指向不存在的 docs/3-decisions/DNNN*.md)")
        println("  当轮修源码注释:删该 D 引用,或改指向合并目标(活 D 文档 / MNK §XX 段)")
        exit(1)
    }
    if (orphan.length() > 0) {
        println(`SOFT WARN: ${orphan.length()} live D doc(s) without §-form citation`)
        let o = 0
        while (o < orphan.length()) {
            println(`  orphan: ${orphan[o]}-*.md`)
            o = o + 1
        }
        println("  这些 D 文档存在但 4 路径(bootstrap/tools/CLAUDE.md/docs/3-MNK.md)无 §-form 引用 — 可能纯 Plan/业务 D 文档,不一定是 bug")
    }
    println(`PASS: ${foundNums.length()} referenced Ds all live`)
    println("GATE OK — D 文档引用与 docs/3-decisions/ 实存一一对应")
}
