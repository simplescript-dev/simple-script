function main() {
    const files = "bootstrap/lexer.ss,bootstrap/parser.ss,bootstrap/checker.ss,bootstrap/codegen.ss,bootstrap/main.ss"
    const parts = files.split(",")
    let output = "// SimpleScript Bootstrap Compiler — bundled\n\n"
    for (f in parts) {
        const src = readFile(f)
        const lines = src.split("\n")
        output = output + "// ── " + f + " ──\n"
        for (line in lines) {
            if (line.startsWith("import ") == 0) {
                output = output + line + "\n"
            }
        }
        output = output + "\n"
    }
    writeFile("/tmp/ss_bootstrap_bundle.ss", output)
    println("bundled: " + output.length() + " chars")
}
