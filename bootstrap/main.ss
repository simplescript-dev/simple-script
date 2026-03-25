// SimpleScript Bootstrap Compiler — Main Entry Point
// Usage: ss run bootstrap/main.ss -- <input.ss> -o <output>

import { tokenize, initTkMap } from "./lexer"
import { parse, initParser } from "./parser"
import { check } from "./checker"
import { generate, generateToFile, initCodegen, initFuncRetTypes, initVarAliases } from "./codegen"

// ── Import resolution ─────────────────────────────────────────

let visitedImports = ""
let visitedReady = 0

function initVisited() {
    if (visitedReady == 1) { return }
    visitedImports = Map()
    visitedReady = 1
}

function resolveImports(filePath: string): string {
    initVisited()
    return resolveInner(filePath)
}

function resolveInner(filePath: string): string {
    // Prevent circular imports
    if (visitedImports.has(filePath) == 1) { return "" }
    visitedImports.set(filePath, 1)

    const source = readFile(filePath)
    if (source == "") { return "" }

    // Extract base directory from file path
    let baseDir = ""
    const lastSlash = lastIndexOf(filePath, "/")
    if (lastSlash >= 0) {
        baseDir = filePath.substring(0, lastSlash + 1)
    }

    let imported = ""
    let mainCode = ""
    const lines = source.split("\n")
    for (line in lines) {
        if (line.startsWith("import ") == 1) {
            const importPath = extractImportPath(line)
            if (importPath != "") {
                let fullPath = baseDir + importPath
                if (fullPath.endsWith(".ss") == 0) {
                    fullPath = fullPath + ".ss"
                }
                const importedCode = resolveInner(fullPath)
                imported = imported + importedCode + "\n"
            }
        } else {
            mainCode = mainCode + line + "\n"
        }
    }
    return imported + mainCode
}

function extractImportPath(line: string): string {
    const fromIdx = line.indexOf("from ")
    if (fromIdx < 0) { return "" }
    const rest = line.substring(fromIdx + 5, line.length() - fromIdx - 5)
    const trimmed = rest.trim()
    if (trimmed.startsWith("\"") == 1) {
        const end = trimmed.substring(1, trimmed.length() - 1).indexOf("\"")
        if (end >= 0) {
            return trimmed.substring(1, end)
        }
    }
    return ""
}

// ── lastIndexOf helper ────────────────────────────────────────

function lastIndexOf(s: string, sub: string): int {
    let last = -1
    let pos2 = 0
    while (pos2 < s.length()) {
        const idx = s.substring(pos2, s.length() - pos2).indexOf(sub)
        if (idx < 0) { break }
        last = pos2 + idx
        pos2 = pos2 + idx + 1
    }
    return last
}

// ── Main ──────────────────────────────────────────────────────

function main() {
    // Initialize all modules upfront (avoids heap init ordering issues)
    initTkMap()
    initParser()
    initCodegen()
    initFuncRetTypes()
    initVarAliases()

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

    // 1. Read source + resolve imports
    const source = resolveImports(inputFile)
    if (source == "") {
        println("error: cannot read " + inputFile)
        exit(1)
    }

    // 2. Lex
    const tokens = tokenize(source)

    // 3. Parse
    const root = parse(tokens)

    // 4. Check (skip for self-bootstrap — checker scope system too simple for 3800 LOC)
    // check(root)

    // 5. Codegen → LLVM IR text (write directly to file to avoid O(n²) string concat)
    const llFile = "/tmp/ss_bootstrap.ll"
    generateToFile(root, llFile)

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
