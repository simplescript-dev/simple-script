// SimpleScript Bootstrap Compiler — Main Entry Point
// Usage: ss run bootstrap/main.ss -- <input.ss> -o <output>

import { tokenize } from "./lexer"
import { parse } from "./parser"
import { check } from "./checker"
import { generate } from "./codegen"

function main() {
    // Parse CLI args
    let inputFile = ""
    let outputFile = "a.out"
    let i = 1
    while (i < args()) {
        const a = arg(i)
        if (a == "-o") {
            i = i + 1
            outputFile = arg(i)
        } else {
            inputFile = a
        }
        i = i + 1
    }
    if (inputFile == "") {
        println("usage: ss-bootstrap <input.ss> [-o output]")
        exit(1)
    }

    // 1. Read source
    const source = readFile(inputFile)
    if (source == "") {
        println("error: cannot read " + inputFile)
        exit(1)
    }

    // 2. Lex
    const tokens = tokenize(source)

    // 3. Parse
    const root = parse(tokens)

    // 4. Check
    check(root)

    // 5. Codegen → LLVM IR text
    const ir = generate(root)

    // 6. Write .ll file
    const llFile = "/tmp/ss_bootstrap.ll"
    writeFile(llFile, ir)

    // 7. Compile with llc
    const objFile = "/tmp/ss_bootstrap.o"
    const llcCmd = "llc-18 -filetype=obj " + llFile + " -o " + objFile
    const llcRc = system(llcCmd)
    if (llcRc != 0) {
        println("error: llc failed (exit " + llcRc + ")")
        println("IR written to: " + llFile)
        exit(1)
    }

    // 8. Compile runtime.c
    const runtimeO = "/tmp/ss_bootstrap_runtime.o"
    const rtCmd = "musl-gcc -c -O2 runtime/runtime.c -o " + runtimeO
    const rtRc = system(rtCmd)
    if (rtRc != 0) {
        println("error: runtime compilation failed")
        exit(1)
    }

    // 9. Link
    const linkCmd = "musl-gcc -static " + objFile + " " + runtimeO + " -o " + outputFile + " -lm"
    const linkRc = system(linkCmd)
    if (linkRc != 0) {
        println("error: linking failed")
        exit(1)
    }

    println("compiled: " + outputFile)
}
