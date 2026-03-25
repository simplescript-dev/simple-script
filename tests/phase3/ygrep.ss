function main() {
    if (args() < 3) {
        println("usage: ygrep <pattern> <file>")
        exit(1)
    }

    const pattern = arg(1)
    const filename = arg(2)
    const content = readFile(filename)

    const len = content.length()
    let lineNum = 1
    let lineStart = 0
    let matchCount = 0

    for (let i = 0; i <= len; i++) {
        if (i == len || content.substring(i, 1) == "\n") {
            const line = content.substring(lineStart, i - lineStart)
            if (line.indexOf(pattern) >= 0) {
                println(lineNum + ": " + line)
                matchCount = matchCount + 1
            }
            lineNum = lineNum + 1
            lineStart = i + 1
        }
    }

    println(matchCount + " matches")
}
