// SimpleScript Bootstrap Compiler — Main Entry Point
// Usage: ss run bootstrap/main.ss -- <input.ss> -o <output>

import { tokenize, initTkMap } from "./lexer"
import { parse, initParser } from "./parser"
import { check } from "./checker"
import { generate, generateToFile, initCodegen, initFuncRetTypes, initVarAliases } from "./codegen"
import { genStmt } from "./gen_stmts"
import { genExpr } from "./gen_exprs"
import { registerClass } from "./gen_class"
import { emitRuntimeDefs } from "./gen_runtime"

// ── Import resolution ─────────────────────────────────────────

let visitedImports = ""
let visitedReady = 0
let projectRoot = ""

function initVisited() {
    if (visitedReady == 1) { return }
    visitedImports = Map()
    visitedReady = 1
}

function findProjectRoot(startPath: string): string {
    // Walk up from startPath looking for ss.json or bootstrap/
    let dir = ""
    const slash = lastIndexOf(startPath, "/")
    if (slash >= 0) {
        dir = startPath.substring(0, slash)
    } else {
        dir = "."
    }
    // Check dir, then parent, grandparent, etc.
    let d = dir
    let tries = 0
    while (tries < 6) {
        if (fileExists(`${d}/ss.json`) == 1 || fileExists(`${d}/bootstrap`) == 1) {
            return d
        }
        // Go up one level
        const up = lastIndexOf(d, "/")
        if (up > 0) {
            d = d.substring(0, up)
        } else {
            // No more slashes — try "." (cwd) as last resort
            if (d != ".") {
                d = "."
            } else {
                break
            }
        }
        tries = tries + 1
    }
    return "."
}

function resolveImports(filePath: string): string {
    initVisited()
    projectRoot = findProjectRoot(filePath)
    return resolveInner(filePath)
}

function resolveInner(filePath: string): string {
    if (visitedImports.has(filePath) == 1) { return "" }
    visitedImports.set(filePath, 1)

    const source = readFile(filePath)
    if (source == "") { return "" }

    // Base directory for relative imports
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
                let fullPath = ""
                if (importPath.startsWith("@/") == 1) {
                    // @/ = project root
                    fullPath = projectRoot + "/" + importPath.substring(2, importPath.length() - 2)
                } else {
                    fullPath = baseDir + importPath
                }
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
    initTkMap()
    initParser()
    initCodegen()
    initFuncRetTypes()
    initVarAliases()

    if (args() < 2) { printUsage(); exit(1) }

    const cmd = arg(1)
    if (cmd == "build") { cmdBuild()
    } else if (cmd == "run") { cmdRun()
    } else if (cmd == "test") { cmdTest()
    } else if (cmd == "check") { cmdCheck()
    } else if (cmd == "new") { cmdNew()
    } else if (cmd == "clean") { cmdClean()
    } else if (cmd == "help" || cmd == "--help" || cmd == "-h") { printUsage()
    } else {
        // Legacy: ss file.ss -o output (no subcommand)
        cmdBuildLegacy()
    }
}

function printUsage() {
    println("SimpleScript Compiler")
    println("")
    println("Usage:")
    println("  ss build <file.ss> [-o output] [--release] [--emit-ir]")
    println("  ss run <file.ss> [--release]")
    println("  ss test [dir]")
    println("  ss check <file.ss>")
    println("  ss new <name>")
    println("  ss clean")
}

// ── ss build ──────────────────────────────────────────────────

function cmdBuild() {
    let inputFile = ""
    let outputFile = ""
    let release = 0
    let emitIr = 0
    let i = 2
    while (i < args()) {
        const a = arg(i)
        if (a == "-o") { i = i + 1; outputFile = arg(i)
        } else if (a == "--release") { release = 1
        } else if (a == "--emit-ir") { emitIr = 1
        } else { inputFile = a }
        i = i + 1
    }
    if (inputFile == "") { println("error: no input file"); exit(1) }
    if (outputFile == "") {
        // Default output name: strip .ss extension
        if (inputFile.endsWith(".ss") == 1) {
            outputFile = inputFile.substring(0, inputFile.length() - 3)
        } else {
            outputFile = inputFile + ".out"
        }
    }
    compile(inputFile, outputFile, release, emitIr)
}

function cmdBuildLegacy() {
    // Legacy: ss file.ss -o output (no subcommand)
    let inputFile = ""
    let outputFile = "a.out"
    let release = 0
    let emitIr = 0
    let i = 1
    while (i < args()) {
        const a = arg(i)
        if (a == "-o") { i = i + 1; outputFile = arg(i)
        } else if (a == "--release") { release = 1
        } else if (a == "--emit-ir") { emitIr = 1
        } else { inputFile = a }
        i = i + 1
    }
    if (inputFile == "") { printUsage(); exit(1) }
    compile(inputFile, outputFile, release, emitIr)
}

// ── ss run ────────────────────────────────────────────────────

function cmdRun() {
    let inputFile = ""
    let release = 0
    let i = 2
    while (i < args()) {
        const a = arg(i)
        if (a == "--release") { release = 1 } else { inputFile = a }
        i = i + 1
    }
    if (inputFile == "") { println("error: no input file"); exit(1) }
    const outBin = "/tmp/ss_run_output"
    compile(inputFile, outBin, release, 0)
    // Run the compiled binary, forwarding remaining args
    const rc = system(outBin)
    exit(rc)
}

// ── ss test ───────────────────────────────────────────────────

function cmdTest() {
    let testDir = "tests"
    if (args() > 2) { testDir = arg(2) }

    const files = listDir(testDir)
    if (files == "") { println("no test files found in " + testDir); exit(1) }

    let passed = 0
    let failed = 0
    let total = 0
    const startTime = timeMs()

    // Recursively find .ss files
    runTestDir(testDir, passed, failed, total)

    println("")
    const elapsed = timeMs() - startTime
    println("done in " + elapsed + "ms")
}

let testPassed = 0
let testFailed = 0

function runTestDir(dir: string, p: int, f: int, t: int) {
    const entries = listDir(dir)
    if (entries == "") { return }
    const parts = entries.split("\n")
    for (entry in parts) {
        const path = dir + "/" + entry
        if (entry.endsWith(".ss") == 1) {
            // Skip interactive tests and library-only files
            if (entry == "guess_game.ss" || entry == "ygrep.ss") { continue }
            if (entry != "main.ss" && dir.endsWith("/import") == 1) { continue }
            const outBin = "/tmp/ss_test_bin"
            const rc1 = system(`bin/ss build ${path} -o ${outBin} 2>/dev/null`)
            if (rc1 != 0) {
                println("FAIL (compile): " + path)
                testFailed = testFailed + 1
                continue
            }
            const rc2 = system(`timeout 5 ${outBin} >/dev/null 2>&1`)
            if (rc2 == 0) {
                testPassed = testPassed + 1
            } else {
                println("FAIL (run): " + path)
                testFailed = testFailed + 1
            }
        } else if (entry.contains(".") == 0) {
            // Directory — recurse
            runTestDir(path, p, f, t)
        }
    }
}

// ── ss check ──────────────────────────────────────────────────

function cmdCheck() {
    if (args() < 3) { println("error: no input file"); exit(1) }
    const inputFile = arg(2)
    const source = resolveImports(inputFile)
    if (source == "") { println(`error: cannot read ${inputFile}`); exit(1) }
    const tokens = tokenize(source)
    const root = parse(tokens)
    check(root)
    println("check OK: " + inputFile)
}

// ── ss new ────────────────────────────────────────────────────

function cmdNew() {
    if (args() < 3) { println("error: no project name"); exit(1) }
    const name = arg(2)
    mkdirp(name + "/src")
    writeFile(name + "/src/main.ss", `function main() {\n    println("Hello from ${name}!")\n}\n`)
    writeFile(name + "/ss.json", `{\n    "name": "${name}",\n    "version": "0.1.0",\n    "main": "src/main.ss"\n}\n`)
    println("created project: " + name)
    println("  cd " + name)
    println("  ss run src/main.ss")
}

// ── ss clean ──────────────────────────────────────────────────

function cmdClean() {
    system("rm -f /tmp/ss_*.o /tmp/ss_*.ll /tmp/ss_*.ll.str /tmp/ss_run_output /tmp/ss_test_bin")
    println("cleaned /tmp/ss_* build artifacts")
}

// ── Compile pipeline ──────────────────────────────────────────

function compile(inputFile: string, outputFile: string, release: int, emitIr: int) {
    const userSource = resolveImports(inputFile)
    if (userSource == "") { println(`error: cannot read ${inputFile}`); exit(1) }
    const prelude = readFile(findPrelude())
    const source = prelude + "\n" + userSource

    const tokens = tokenize(source)
    const root = parse(tokens)
    const llFile = "/tmp/ss_bootstrap.ll"
    generateToFile(root, llFile)

    if (emitIr == 1) { println(readFile(llFile)); exit(0) }

    const objFile = "/tmp/ss_bootstrap.o"
    if (system(`llc-18 -filetype=obj ${llFile} -o ${objFile}`) != 0) {
        println("error: llc failed")
        exit(1)
    }

    let linkFlags = "-static"
    if (release == 1) { linkFlags = "-static -O2 -s" }
    if (system(`musl-gcc ${linkFlags} ${objFile} -o ${outputFile} -lm`) != 0) {
        println("error: linking failed")
        exit(1)
    }

    println("compiled: " + outputFile)
}

function findPrelude(): string {
    if (fileExists("bootstrap/prelude.ss") == 1) { return "bootstrap/prelude.ss" }
    if (fileExists("../bootstrap/prelude.ss") == 1) { return "../bootstrap/prelude.ss" }
    return ""
}
