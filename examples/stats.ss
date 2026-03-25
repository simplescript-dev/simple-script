// ystats — File statistics tool
// Usage: ystats <file>

function main() {
    if (args() < 2) {
        println("Usage: ystats <file>")
        exit(1)
    }

    const filename = arg(1)
    const content = readFile(filename)
    if (content.length() == 0) {
        println("error: cannot read " + filename)
        exit(1)
    }

    const totalLen = content.length()
    let lines = 1
    let words = 0
    let inWord = 0
    let maxLineLen = 0
    let currentLineLen = 0
    let emptyLines = 0

    for (let i = 0; i < totalLen; i++) {
        const ch = content.charAt(i)
        if (ch == "\n") {
            lines = lines + 1
            if (currentLineLen == 0) {
                emptyLines = emptyLines + 1
            }
            if (currentLineLen > maxLineLen) {
                maxLineLen = currentLineLen
            }
            currentLineLen = 0
            if (inWord == 1) {
                words = words + 1
                inWord = 0
            }
        } else if (ch == " " || ch == "\t") {
            if (inWord == 1) {
                words = words + 1
                inWord = 0
            }
            currentLineLen = currentLineLen + 1
        } else {
            inWord = 1
            currentLineLen = currentLineLen + 1
        }
    }
    if (inWord == 1) { words = words + 1 }
    if (currentLineLen > maxLineLen) { maxLineLen = currentLineLen }

    println("File: " + filename)
    println("  Lines:         " + lines)
    println("  Words:         " + words)
    println("  Characters:    " + totalLen)
    println("  Empty lines:   " + emptyLines)
    println("  Max line len:  " + maxLineLen)
}
