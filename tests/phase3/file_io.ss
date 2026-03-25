function main() {
    // Write a file
    writeFile("/tmp/ss_test.txt", "Hello from SimpleScript!\nLine 2\nLine 3")
    println("wrote /tmp/ss_test.txt")

    // Read it back
    const content = readFile("/tmp/ss_test.txt")
    println(`content: ${content}`)

    // String operations
    const s = "Hello, World!"
    println(`length: ${s.length()}`)
    println(`substring(0,5): ${s.substring(0, 5)}`)
    println(`indexOf("World"): ${s.indexOf("World")}`)
    println(`indexOf("xyz"): ${s.indexOf("xyz")}`)

    // Write CSV and read back
    let csv = "name,age,city\n"
    csv = csv + "Alice,30,Beijing\n"
    csv = csv + "Bob,25,Shanghai\n"
    writeFile("/tmp/ss_data.csv", csv)

    const data = readFile("/tmp/ss_data.csv")
    println(`CSV data:\n${data}`)
}
