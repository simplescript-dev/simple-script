// yreplace — Find and replace text in files
// Usage: yreplace <find> <replace> <file>

function main() {
    if (args() < 4) {
        println("yreplace — Find and replace text in files")
        println("")
        println("Usage: yreplace <find> <replace> <file>")
        println("")
        println("Example:")
        println("  yreplace foo bar myfile.txt")
        exit(1)
    }

    const find = arg(1)
    const replace = arg(2)
    const filename = arg(3)

    // Read file
    const content = readFile(filename)
    if (content.length() == 0) {
        println("error: cannot read " + filename)
        exit(1)
    }

    // Count matches
    let count = 0
    let pos = 0
    let searchContent = content
    while (searchContent.indexOf(find) >= 0) {
        count = count + 1
        const idx = searchContent.indexOf(find)
        searchContent = searchContent.substring(idx + find.length(), searchContent.length() - idx - find.length())
    }

    if (count == 0) {
        println("no matches for '" + find + "' in " + filename)
        exit(0)
    }

    // Replace
    const result = content.replace(find, replace)

    // Write back
    writeFile(filename, result)
    println("replaced " + count + " occurrences of '" + find + "' with '" + replace + "' in " + filename)
}
