// SimpleScript Bootstrap Compiler — Main Entry Point
// Usage: ss run bootstrap/main.ss -- <input.ss> -o <output>

import { tokenize } from "./lexer"
import { parse, initParser } from "./parser"
import { check } from "./checker"
import { generate, generateToFile, initCodegen, initVarAliases } from "./codegen"
import { initFuncRegistry } from "./gen_registry"
import { initRcState, detectCyclicOwnership } from "./gen_rc"
import { genStmt } from "./gen_stmts"
import { genExpr, genVal } from "./gen_exprs"
import { inferType, ssTypeToLLVM } from "./gen_types"
import { registerClass, initClassState } from "./gen_class"
import { emitRuntimeDefs } from "./gen_runtime"
import { initPir, pirAnalyzeFunc, pirEmitScheduled, pirEmitReturnCleanup, pirIsManaged, pirMarkManaged, pirIsClass, pirIsMoveStmt, pirActive } from "./gen_pir"
import { pirLivenessPass, pirMoveAnalysis } from "./pir_opt"
import { JSON_parse, JsonNode } from "@/lib/json"

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

function normalizePath(path: string): string {
    const isAbs = path.startsWith("/")
    const parts = path.split("/")
    let stack = ""
    let stackCount = 0
    for (p in parts) {
        if (p == "" || p == ".") { continue }
        if (p == "..") {
            if (stackCount > 0) {
                const lc = lastIndexOf(stack, ",")
                if (lc >= 0) { stack = stack.substring(0, lc) } else { stack = "" }
                stackCount = stackCount - 1
            }
            continue
        }
        stack = listAppendStr(stack, p)
        stackCount = stackCount + 1
    }
    if (stack == "") {
        if (isAbs == 1) { return "/" }
        return "."
    }
    const components = stack.split(",")
    let result = ""
    for (c in components) {
        result = `${result}/${c}`
    }
    if (isAbs == 1) { return result }
    return result.substring(1, result.length() - 1)
}

// D085: Package dependency cache — loaded once per compilation from ss.json
let depCache = ""
let depCacheReady = 0

function loadDeps() {
    if (depCacheReady == 1) { return }
    depCache = new Map()
    depCacheReady = 1
    const jsonPath = `${projectRoot}/ss.json`
    if (fileExists(jsonPath) == 0) { return }
    const root = JSON.parse(readFile(jsonPath))
    if (root.has("dependencies") == 0) { return }
    const deps = root.get("dependencies")
    const keys = deps.keys()
    let i = 0
    while (i < keys.length()) {
        const key = keys[i]
        depCache.set(key, deps.getString(key))
        i = i + 1
    }
}

function resolvePackageEntry(pkgDir: string): string {
    // Try ss.json main field
    const jsonPath = `${pkgDir}/ss.json`
    if (fileExists(jsonPath) == 1) {
        const pkgJson = JSON.parse(readFile(jsonPath))
        const mainFile = pkgJson.getString("main")
        if (mainFile != "") {
            const fullMain = `${pkgDir}/${mainFile}`
            if (fileExists(fullMain) == 1) { return fullMain }
        }
    }
    // Convention: src/index.ss or index.ss
    if (fileExists(`${pkgDir}/src/index.ss`) == 1) { return `${pkgDir}/src/index.ss` }
    if (fileExists(`${pkgDir}/index.ss`) == 1) { return `${pkgDir}/index.ss` }
    return ""
}

function resolvePackage(importPath: string): string {
    loadDeps()
    // Check ss.json dependencies
    if (depCache.has(importPath) == 1) {
        const depVal = depCache.getString(importPath)
        let pkgDir = ""
        if (depVal.startsWith("./") == 1 || depVal.startsWith("../") == 1) {
            // Local path reference (relative to project root)
            pkgDir = normalizePath(`${projectRoot}/${depVal}`)
        } else {
            // Version string → ~/.ss/packages/
            const home = getenv("HOME")
            pkgDir = `${home}/.ss/packages/${importPath}/${depVal}`
        }
        // Package is a directory → find entry point
        if (fileExists(pkgDir) == 1) {
            const entry = resolvePackageEntry(pkgDir)
            if (entry != "") { return entry }
        }
        // Maybe it's a direct .ss file
        if (fileExists(`${pkgDir}.ss`) == 1) { return `${pkgDir}.ss` }
        println(`error: cannot resolve package '${importPath}' at '${pkgDir}'`)
        exit(1)
    }
    // Fallback: check ~/.ss/packages/ directly
    const home = getenv("HOME")
    const globalDir = `${home}/.ss/packages/${importPath}`
    if (fileExists(globalDir) == 1) {
        const entry = resolvePackageEntry(globalDir)
        if (entry != "") { return entry }
    }
    println(`error: package '${importPath}' not found (add to ss.json dependencies)`)
    exit(1)
    return ""
}

function resolveImports(filePath: string): string {
    initVisited()
    projectRoot = findProjectRoot(filePath)
    // Ensure projectRoot is absolute for correct relative dependency resolution
    if (projectRoot.startsWith("/") == 0) {
        const cwd = getenv("PWD")
        if (projectRoot == ".") {
            projectRoot = cwd
        } else {
            projectRoot = `${cwd}/${projectRoot}`
        }
    }
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
                    fullPath = projectRoot + "/" + importPath.substring(2, importPath.length() - 2)
                } else if (importPath.startsWith("./") == 1 || importPath.startsWith("../") == 1) {
                    fullPath = baseDir + importPath
                } else {
                    // Package import: resolve via ss.json dependencies or ~/.ss/packages/
                    fullPath = resolvePackage(importPath)
                }
                if (fullPath.endsWith(".ss") == 0) {
                    fullPath = fullPath + ".ss"
                }
                fullPath = normalizePath(fullPath)
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
    initParser()
    initCodegen()
    initClassState()
    initFuncRegistry()
    initVarAliases()

    if (args() < 2) { printUsage(); exit(1) }

    const cmd = arg(1)
    if (cmd == "build") { cmdBuild()
    } else if (cmd == "run") { cmdRun()
    } else if (cmd == "test") { cmdTest()
    } else if (cmd == "check") { cmdCheck()
    } else if (cmd == "new") { cmdNew()
    } else if (cmd == "clean") { cmdClean()
    } else if (cmd == "init") { cmdInit()
    } else if (cmd == "add") { cmdAdd()
    } else if (cmd == "publish") { cmdPublish()
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
    println("  ss init")
    println("  ss add <@scope/name> <path>")
    println("  ss publish")
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

let testFileList = ""
let testFileCount = 0

function collectTestFiles(dir: string) {
    const entries = listDir(dir)
    if (entries == "") { return }
    const parts = entries.split("\n")
    for (entry in parts) {
        if (entry == "") { continue }
        const path = dir + "/" + entry
        if (entry.endsWith(".ss") == 1) {
            if (entry == "guess_game.ss" || entry == "ygrep.ss") { continue }
            if (entry != "main.ss" && dir.endsWith("/import") == 1) { continue }
            if (testFileList == "") { testFileList = path }
            else { testFileList = testFileList + "\n" + path }
            testFileCount = testFileCount + 1
        } else if (entry.contains(".") == 0) {
            collectTestFiles(path)
        }
    }
}

function cmdTest() {
    let testDir = "tests"
    if (args() > 2) { testDir = arg(2) }

    collectTestFiles(testDir)
    if (testFileCount == 0) { println("no test files found in " + testDir); exit(1) }

    // Build runtime cache for faster compilation
    if (fileExists(runtimeCacheObj) == 0) { buildRuntimeCache() }
    useRuntimeCache = 1

    const selfBin = arg(0)
    const startTime = timeMs()

    // Generate parallel test script — limit concurrency to nproc
    let script = "#!/bin/bash\nMAX_JOBS=$(nproc)\nRUNNING=0\n"
    const files = testFileList.split("\n")
    let idx = 0
    for (f in files) {
        if (f == "") { continue }
        const outBin = `/tmp/ss_test_${idx}`
        const resFile = `/tmp/ss_res_${idx}`
        script = script + `(${selfBin} build ${f} -o ${outBin} >/dev/null 2>&1 && timeout 5 ${outBin} >/dev/null 2>&1; echo $? > ${resFile}) &\n`
        script = script + "RUNNING=$((RUNNING+1)); if [ $RUNNING -ge $MAX_JOBS ]; then wait -n; RUNNING=$((RUNNING-1)); fi\n"
        idx = idx + 1
    }
    script = script + "wait\n"

    writeFile("/tmp/ss_test_par.sh", script)
    system("bash /tmp/ss_test_par.sh")

    // Collect results
    let passed = 0
    let failed = 0
    let i = 0
    for (tf in files) {
        if (tf == "") { continue }
        const resFile = `/tmp/ss_res_${i}`
        const res = readFile(resFile).trim()
        if (res == "0") {
            passed = passed + 1
        } else {
            println("FAIL: " + tf)
            failed = failed + 1
        }
        i = i + 1
    }

    // Cleanup
    system(`rm -f /tmp/ss_test_par.sh /tmp/ss_test_* /tmp/ss_res_*`)

    println("")
    const elapsed = timeMs() - startTime
    println(`${passed} passed, ${failed} failed, ${passed + failed} total`)
    println(`done in ${elapsed}ms`)
    if (failed > 0) { exit(1) }
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

// ── ss init ──────────────────────────────────────────────────

function cmdInit() {
    if (fileExists("ss.json") == 1) {
        println("ss.json already exists")
        exit(1)
    }
    writeFile("ss.json", `{\n    "name": "my-app",\n    "version": "0.1.0",\n    "main": "src/main.ss",\n    "dependencies": {}\n}\n`)
    println("created ss.json")
}

// ── ss add ───────────────────────────────────────────────────

function cmdAdd() {
    if (args() < 4) {
        println("usage: ss add <@scope/name> <path>")
        println("  e.g. ss add @van/tailwindcss ../van-ss/tailwindcss")
        exit(1)
    }
    const pkgName = arg(2)
    const pkgPath = arg(3)
    if (fileExists("ss.json") == 0) {
        println("error: ss.json not found (run 'ss init' first)")
        exit(1)
    }
    // Read and update ss.json — replace empty deps {} or insert before closing }
    const json = readFile("ss.json")
    const entry = `"${pkgName}": "${pkgPath}"`
    if (json.contains(`"dependencies"`) == 0) {
        // No dependencies block — add one before the last }
        const lastBrace = lastIndexOf(json, "}")
        if (lastBrace >= 0) {
            const before = json.substring(0, lastBrace)
            writeFile("ss.json", `${before},\n    "dependencies": {\n        ${entry}\n    }\n}\n`)
        }
    } else if (json.contains(`"dependencies": {}`) == 1) {
        // Empty dependencies — replace {}
        const newJson = json.replace(`"dependencies": {}`, `"dependencies": {\n        ${entry}\n    }`)
        writeFile("ss.json", newJson)
    } else {
        // Has deps — find last " before closing } of dependencies, append comma + new entry
        const depIdx = json.indexOf(`"dependencies"`)
        const afterDep = json.substring(depIdx, json.length() - depIdx)
        const braceStart = afterDep.indexOf("{")
        const searchFrom = depIdx + braceStart + 1
        const rest = json.substring(searchFrom, json.length() - searchFrom)
        const braceEnd = rest.indexOf("}")
        // Find last quote inside deps block
        const depsBlock = rest.substring(0, braceEnd)
        const lastQuote = lastIndexOf(depsBlock, "\"")
        const insertAt = searchFrom + lastQuote + 1
        const before = json.substring(0, insertAt)
        const after = json.substring(insertAt, json.length() - insertAt)
        writeFile("ss.json", `${before},\n        ${entry}${after}`)
    }
    println(`added: ${pkgName} → ${pkgPath}`)
}

// ── ss publish ──────────────────────────────────────────────

function cmdPublish() {
    if (fileExists("ss.json") == 0) {
        println("error: ss.json not found")
        exit(1)
    }
    // Read name and version from ss.json
    const root = JSON.parse(readFile("ss.json"))
    let pkgName = root.getString("name")
    let pkgVersion = root.getString("version")
    if (pkgName == "") { println("error: 'name' not found in ss.json"); exit(1) }
    if (pkgVersion == "") { pkgVersion = "0.1.0" }

    const home = getenv("HOME")
    const destDir = `${home}/.ss/packages/${pkgName}/${pkgVersion}`
    mkdirp(destDir)

    // Copy ss.json and all .ss source files
    system(`cp ss.json "${destDir}/"`)
    if (fileExists("src") == 1) {
        system(`cp -r src "${destDir}/"`)
    }
    if (fileExists("lib") == 1) {
        system(`cp -r lib "${destDir}/"`)
    }
    println(`published: ${pkgName}@${pkgVersion} → ${destDir}`)
}


// ── ss clean ──────────────────────────────────────────────────

function cmdClean() {
    system("rm -f /tmp/ss_*.o /tmp/ss_*.ll /tmp/ss_*.ll.str /tmp/ss_run_output /tmp/ss_test_* /tmp/ss_res_* /tmp/ss_test_par.sh /tmp/ss_rt_cache.*")
    println("cleaned /tmp/ss_* build artifacts")
}

// ── Compile pipeline ──────────────────────────────────────────

function compile(inputFile: string, outputFile: string, release: int, emitIr: int) {
    const userSource = resolveImports(inputFile)
    if (userSource == "") { println(`error: cannot read ${inputFile}`); exit(1) }
    const prelude = readFile(findPrelude())
    const source = prelude + "\n" + userSource
    // Count prelude lines for error reporting offset
    let preludeLines = 0
    let pi = 0
    while (pi < prelude.length()) {
        if (charCodeAt(prelude, pi) == 10) { preludeLines = preludeLines + 1 }
        pi = pi + 1
    }

    const tokens = tokenize(source)
    setLineOffset(preludeLines + 1)
    const root = parse(tokens)
    check(root)
    comptimeReleaseMode = release
    const llFile = outputFile + ".ll"
    generateToFile(root, llFile)

    if (emitIr == 1) { println(readFile(llFile)); exit(0) }

    const objFile = outputFile + ".o"
    if (system(`llc-18 -filetype=obj ${llFile} -o ${objFile}`) != 0) {
        println("error: llc failed")
        exit(1)
    }

    let linkFlags = "-static"
    if (release == 1) { linkFlags = "-static -O2 -s" }
    let mimallocObj = ""
    if (fileExists("vendor/mimalloc.o") == 1) { mimallocObj = "vendor/mimalloc.o" }
    if (fileExists("../vendor/mimalloc.o") == 1) { mimallocObj = "../vendor/mimalloc.o" }
    let sqliteObj = ""
    if (fileExists("vendor/sqlite3.o") == 1) { sqliteObj = "vendor/sqlite3.o" }
    if (fileExists("../vendor/sqlite3.o") == 1) { sqliteObj = "../vendor/sqlite3.o" }
    let rtObj = ""
    if (useRuntimeCache == 1) { rtObj = runtimeCacheObj }
    if (system(`musl-gcc ${linkFlags} ${objFile} ${rtObj} ${mimallocObj} ${sqliteObj} -o ${outputFile} -lm`) != 0) {
        println("error: linking failed")
        exit(1)
    }
    system(`rm -f ${llFile} ${llFile}.str ${objFile}`)

    println("compiled: " + outputFile)
}

function findPrelude(): string {
    if (fileExists("bootstrap/prelude.ss") == 1) { return "bootstrap/prelude.ss" }
    if (fileExists("../bootstrap/prelude.ss") == 1) { return "../bootstrap/prelude.ss" }
    return ""
}
