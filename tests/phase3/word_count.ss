function countLines(content: string): int {
    let count = 1
    const len = content.length()
    for (let i = 0; i < len; i++) {
        const ch = content.substring(i, 1)
        if (ch == "\n") {
            count = count + 1
        }
    }
    return count
}

function countWords(content: string): int {
    let count = 0
    let inWord = 0
    const len = content.length()
    for (let i = 0; i < len; i++) {
        const ch = content.substring(i, 1)
        if (ch == " " || ch == "\n" || ch == "\t") {
            if (inWord == 1) {
                count = count + 1
                inWord = 0
            }
        } else {
            inWord = 1
        }
    }
    if (inWord == 1) {
        count = count + 1
    }
    return count
}

function main() {
    // Create a test file
    const text = "The quick brown fox\njumps over the lazy dog.\nSimpleScript is awesome!"
    writeFile("/tmp/ym_wc_test.txt", text)

    // Read and analyze
    const content = readFile("/tmp/ym_wc_test.txt")
    const lines = countLines(content)
    const words = countWords(content)
    const chars = content.length()

    println(`File: /tmp/ym_wc_test.txt`)
    println(`  Lines: ${lines}`)
    println(`  Words: ${words}`)
    println(`  Chars: ${chars}`)
}
