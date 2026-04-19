// tools/send_next.ss
// 把下轮提示词注入当前 Claude Code 输入框。
// 流程：/clear → bracketed paste → 30s 观察窗口（看清文本，Ctrl+C 可中断） → Enter。
//
// 用法：bin/ss run tools/send_next.ss <prompt-file>
// 前置：必须在 terman session 内运行（读 $TERMAN_NAME）。
//
// bracketed paste（ESC[200~ ... ESC[201~）让 TUI 把 \n 当字面换行保留，不触发提交。

// shell 单引号安全转义：外层 '...'，内部每个 ' 替换为 '\''
function shellQuote(s: string): string {
    let out = "'"
    let i = 0
    while (i < s.length()) {
        const ch = s.charAt(i)
        if (ch == "'") {
            out = out + "'\\''"
        } else {
            out = out + ch
        }
        i = i + 1
    }
    return out + "'"
}

function main() {
    if (args() < 2) {
        println("usage: bin/ss run tools/send_next.ss <prompt-file>")
        exit(1)
    }

    const termName = getenv("TERMAN_NAME")
    if (termName == "") {
        println("error: TERMAN_NAME not set — must run inside a terman session")
        exit(1)
    }

    const promptFile = arg(1)
    if (fileExists(promptFile) != 1) {
        println(`error: prompt file not found: ${promptFile}`)
        exit(1)
    }
    const prompt = readFile(promptFile)
    const ESC = fromCharCode(27)
    const payload = ESC + "[200~" + prompt + ESC + "[201~"

    system(`terman send ${termName} '/clear'`)
    system(`terman send ${termName} --key Enter`)

    system(`terman send ${termName} ${shellQuote(payload)}`)

    println("prompt pasted — sleeping 30s before pressing Enter (Ctrl+C to abort)...")
    system("sleep 30")

    system(`terman send ${termName} --key Enter`)
}
