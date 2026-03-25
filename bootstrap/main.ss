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
    let release = 0
    let emitIrOnly = 0
    let i = 1
    while (i < args()) {
        const a = arg(i)
        if (a == "-o") { i = i + 1; outputFile = arg(i) } else if (a == "--release") { release = 1 } else if (a == "--emit-ir") { emitIrOnly = 1 } else { inputFile = a }
        i = i + 1
    }
    if (inputFile == "") {
        println("SimpleScript Bootstrap Compiler")
        println("usage: ss <input.ss> [-o output] [--release] [--emit-ir]")
        exit(1)
    }

    // 1. Read source + resolve imports
    const source = resolveImports(inputFile)
    if (source == "") {
        println("error: cannot read " + inputFile)
        exit(1)
    }

    // 2. Lex → Parse → Codegen
    const tokens = tokenize(source)
    const root = parse(tokens)
    const llFile = "/tmp/ss_bootstrap.ll"
    generateToFile(root, llFile)

    if (emitIrOnly == 1) {
        println(readFile(llFile))
        exit(0)
    }

    // 3. LLC
    const objFile = "/tmp/ss_bootstrap.o"
    const llcRc = system("llc-18 -filetype=obj " + llFile + " -o " + objFile)
    if (llcRc != 0) {
        println("error: llc failed")
        exit(1)
    }

    // 4. Find and compile runtime
    let rtSrc = "runtime/runtime.c"
    if (fileExists(rtSrc) == 0) {
        rtSrc = "../runtime/runtime.c"
        if (fileExists(rtSrc) == 0) {
            rtSrc = getenv("SS_RUNTIME")
            if (rtSrc == "") {
                println("error: cannot find runtime.c (set SS_RUNTIME env var)")
                exit(1)
            }
        }
    }
    const runtimeO = "/tmp/ss_bootstrap_runtime.o"
    const rtRc = system("musl-gcc -c -O2 " + rtSrc + " -o " + runtimeO)
    if (rtRc != 0) { println("error: runtime compilation failed"); exit(1) }

    // 5. Link
    let linkFlags = "-static"
    if (release == 1) { linkFlags = "-static -O2 -s" }
    const linkRc = system("musl-gcc " + linkFlags + " " + objFile + " " + runtimeO + " -o " + outputFile + " -lm")
    if (linkRc != 0) { println("error: linking failed"); exit(1) }

    println("compiled: " + outputFile)
}
