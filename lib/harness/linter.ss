// harness/linter.ss — Base Linter class + shared verification primitives
// Subclass Linter and override verify/verifyAll for specific lifecycle types.
// Utility functions use IniData from lib/ini for field access.
//
// Usage:
//   import { Linter, parseReport, checkRequired, ... } from "@/lib/harness/linter"

import { Ini, IniData } from "@/lib/ini"

function parseReport(path: string): IniData {
    return Ini.parse(readFile(path))
}

function fieldGet(data: IniData, path: string): string {
    const dot = path.indexOf(".")
    if (dot < 0) { return data.get("", path) }
    const section = path.substring(0, dot)
    const key = path.substring(dot + 1, path.length() - dot - 1)
    return data.get(section, key)
}

function fieldFilled(data: IniData, path: string): int {
    const v = fieldGet(data, path)
    if (v == "" || v.startsWith("<") == 1) { return 0 }
    return 1
}

function checkRequired(fields: string, data: IniData): int {
    const parts = fields.split(",")
    let missing = 0
    let i = 0
    while (i < parts.length()) {
        const f = parts[i].trim()
        if (fieldFilled(data, f) == 0) {
            println(`  FAIL: '${f}' missing`)
            missing = missing + 1
        }
        i = i + 1
    }
    return missing
}

function checkEquals(path: string, expected: string, data: IniData): int {
    const val = fieldGet(data, path)
    if (val != expected) {
        println(`  FAIL: ${path}='${val}' (expected '${expected}')`)
        return 0
    }
    println(`  PASS: ${path}=${expected}`)
    return 1
}

function checkMinLength(path: string, min: int, data: IniData): int {
    const val = fieldGet(data, path)
    if (val.length() < min) {
        println(`  FAIL: '${path}' too short (${val.length()} < ${min})`)
        return 0
    }
    return 1
}

function checkNonzero(path: string, data: IniData): int {
    const val = fieldGet(data, path)
    if (val == "") { println(`  FAIL: ${path} empty`); return 0 }
    const n = parseInt(val)
    if (n == 0) {
        println(`  FAIL: ${path}=0`)
        return 0
    }
    println(`  PASS: ${path}=${n}`)
    return 1
}

function checkMax(path: string, max: int, data: IniData): int {
    const val = fieldGet(data, path)
    const actual = parseInt(val)
    if (actual > max) {
        println(`  WARN: ${path}=${actual} (>${max})`)
        return 0
    }
    println(`  PASS: ${path}=${actual}`)
    return 1
}

function checkFileExists(path: string, data: IniData): int {
    const val = fieldGet(data, path)
    if (val != "" && fileExists(val) != 1) {
        println(`  FAIL: file not found: ${val}`)
        return 0
    }
    return 1
}

function runBootstrap(): int {
    const ec = system("./build.sh bootstrap >/dev/null 2>&1")
    if (ec != 0) { println("  FAIL: bootstrap failed"); return 0 }
    println("  PASS: bootstrap passed")
    return 1
}

function runTestSuite(): string {
    const tmp = "/tmp/harness_test_out.txt"
    system(`bin/ss test tests/ 2>&1 > ${tmp}`)
    const out = readFile(tmp)
    const lines = out.split("\n")
    let summary = ""
    let si = 0
    while (si < lines.length()) {
        if (lines[si].indexOf("passed") >= 0 && lines[si].indexOf("failed") >= 0) {
            summary = lines[si].trim()
        }
        si = si + 1
    }
    return summary
}

class Linter {
    function verify(phase: string, data: IniData): int { return 0 }
    function verifyAll(data: IniData): int { return 0 }
}
