function padLeft(s: string, width: int, pad: string): string {
    let result = s
    let len = s.length()
    while (len < width) {
        result = pad + result
        len = len + 1
    }
    return result
}

function formatLine(label: string, value: int): string {
    return `${label}: ${value}`
}

function main() {
    // Test string concatenation in loop
    let csv = "id,name,score"
    csv = csv + "\n" + "1,Alice,95"
    csv = csv + "\n" + "2,Bob,87"
    csv = csv + "\n" + "3,Charlie,92"
    println(csv)

    println("")

    // Test multiple function calls in expression
    println(formatLine("Total", 274))
    println(formatLine("Average", 91))

    // Nested string building
    let table = ""
    for (let i = 1; i <= 5; i++) {
        const line = `${i} x 7 = ${i * 7}`
        table = table + line + "\n"
    }
    println(table)
}
