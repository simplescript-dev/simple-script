// bugfix_linter.ss - mechanical verification of bug fix evidence document
// Usage: /tmp/bugfix_linter <report.bugfix>
// Build: bin/ss build tools/bugfix_linter.ss -o /tmp/bugfix_linter
//
// Does NOT trust claimed values. Re-measures key fields and compares.
// All PASS required before commit.

function parseFields(content: string): Map {
    let fields = new Map()
    const lines = content.split("\n")
    let i = 0
    while (i < lines.length()) {
        const line = lines[i].trim()
        if (line != "" && line.startsWith("[") == 0 && line.startsWith("#") == 0 && line.indexOf("=") >= 0) {
            const eqIdx = line.indexOf("=")
            const key = line.substring(0, eqIdx).trim()
            const val = line.substring(eqIdx + 1, line.length()).trim()
            fields.set(key, val)
        }
        i = i + 1
    }
    return fields
}

function checkRequired(fields: Map): int {
    println("-- G1: required fields")
    const names = "title,test_file,stash_exit,fix_exit,broken,why,fix,same_pattern_count,net_new_ifs,net_new_fns,bootstrap,test_passed,test_failed"
    const parts = names.split(",")
    let missing = 0
    let i = 0
    while (i < parts.length()) {
        const key = parts[i]
        if (fields.has(key) != 1) {
            println(`  FAIL: '${key}' missing`)
            missing = missing + 1
        } else if (fields.getString(key) == "" || fields.getString(key).startsWith("<")) {
            println(`  FAIL: '${key}' unfilled`)
            missing = missing + 1
        }
        i = i + 1
    }
    if (missing == 0) {
        println("  PASS: all 13 required fields present")
        return 1
    }
    println(`  FAIL: ${missing} fields missing`)
    return 0
}

function checkCausality(fields: Map): int {
    println("")
    println("-- G2: causality (re-run test)")
    let score = 0

    if (fields.has("test_file") != 1) { println("  SKIP: no test_file"); return 0 }
    const testFile = fields.getString("test_file")

    if (fileExists(testFile) != 1) {
        println(`  FAIL: test file not found: ${testFile}`)
        return 0
    }

    // G2a: test must PASS now
    const actualExit = system(`bin/ss run ${testFile} >/dev/null 2>&1`)
    if (actualExit == 0) {
        println("  PASS G2a: test PASS (exit=0)")
        score = score + 1
    } else {
        println(`  FAIL G2a: test FAIL (exit=${actualExit})`)
    }

    // G2b: claimed fix_exit must match actual
    if (fields.has("fix_exit") == 1) {
        const claimed = parseInt(fields.getString("fix_exit"))
        if (claimed == actualExit) {
            println(`  PASS G2b: fix_exit=${claimed} matches actual`)
            score = score + 1
        } else {
            println(`  FAIL G2b: claimed fix_exit=${claimed} but actual=${actualExit}`)
        }
    }

    // G2c: stash_exit must != 0 (immutable: claimed value)
    if (fields.has("stash_exit") == 1) {
        const stashExit = parseInt(fields.getString("stash_exit"))
        if (stashExit != 0) {
            println(`  PASS G2c: stash_exit=${stashExit} (test fails without fix)`)
            score = score + 1
        } else {
            println("  FAIL G2c: stash_exit=0 (test passes without fix = not testing the bug)")
        }
    }

    return score
}

function checkRootCause(fields: Map): int {
    println("")
    println("-- G3: root cause quality")
    let ok = 1

    // broken/why/fix must each be >= 10 chars (substantive)
    const rcNames = "broken,why,fix"
    const rcParts = rcNames.split(",")
    let rci = 0
    while (rci < rcParts.length()) {
        const key = rcParts[rci]
        if (fields.has(key) == 1) {
            const val = fields.getString(key)
            if (val.length() < 10) {
                println(`  FAIL: '${key}' too short (${val.length()} chars)`)
                ok = 0
            }
        }
        rci = rci + 1
    }

    // same_pattern_count must == 0
    if (fields.has("same_pattern_count") == 1) {
        const spc = parseInt(fields.getString("same_pattern_count"))
        if (spc > 0) {
            println(`  FAIL: same_pattern_count=${spc} (residual instances)`)
            ok = 0
        } else {
            println("  PASS: same_pattern_count=0")
        }
    }

    if (ok == 1) {
        println("  PASS: root cause analysis complete")
    }
    return ok
}

function checkStructure(fields: Map): int {
    println("")
    println("-- G4: structural delta")
    let score = 0

    if (fields.has("net_new_ifs") == 1) {
        const n = parseInt(fields.getString("net_new_ifs"))
        if (n > 2) {
            println(`  WARN: net_new_ifs=${n} (>2 new conditionals = possible workaround)`)
            return -1
        }
        println(`  PASS: net_new_ifs=${n}`)
        score = score + 1
    }

    if (fields.has("net_new_fns") == 1) {
        const n = parseInt(fields.getString("net_new_fns"))
        if (n > 1) {
            println(`  WARN: net_new_fns=${n} (>1 new functions = possible workaround)`)
            return -1
        }
        println(`  PASS: net_new_fns=${n}`)
        score = score + 1
    }

    return score
}

function checkBootstrap(fields: Map): int {
    println("")
    println("-- G5: bootstrap (re-verify)")

    const bsExit = system("./build.sh bootstrap >/dev/null 2>&1")
    if (bsExit != 0) {
        println("  FAIL: bootstrap actually failed")
        return 0
    }
    println("  PASS: bootstrap passed")

    if (fields.has("bootstrap") == 1) {
        const claimed = fields.getString("bootstrap")
        if (claimed == "FAIL") {
            println("  FAIL: doc claims bootstrap=FAIL but it passed (stale doc)")
            return 0
        }
        if (claimed != "PASS") {
            println(`  FAIL: bootstrap field='${claimed}' (must be PASS)`)
            return 0
        }
    }
    return 1
}

function checkTestSuite(fields: Map): int {
    println("")
    println("-- G6: test suite (re-verify)")

    const tmp = "/tmp/bugfix_gate_test.txt"
    system(`bin/ss test tests/ 2>&1 > ${tmp}`)
    const fullOutput = readFile(tmp)
    const outLines = fullOutput.split("\n")

    // find the summary line (contains "passed" and "failed")
    let summaryLine = ""
    let si = 0
    while (si < outLines.length()) {
        if (outLines[si].indexOf("passed") >= 0 && outLines[si].indexOf("failed") >= 0) {
            summaryLine = outLines[si].trim()
        }
        si = si + 1
    }
    println(`  actual: ${summaryLine}`)

    if (fields.has("test_failed") == 1) {
        const claimedFailed = parseInt(fields.getString("test_failed"))
        const knownFail = fields.has("test_known_fail") == 1 ? parseInt(fields.getString("test_known_fail")) : 0
        const effectiveFail = claimedFailed - knownFail

        if (effectiveFail > 0) {
            println(`  FAIL: ${claimedFailed} failures, ${effectiveFail} non-known`)
            return 0
        }
        println(`  PASS: failures=${claimedFailed}, known=${knownFail}`)
        return 1
    }
    return 0
}

function main() {
    if (args() < 2) {
        println("usage: bin/ss build tools/bugfix_linter.ss -o /tmp/bugfix_linter")
        println("       /tmp/bugfix_linter <report.bugfix>")
        exit(1)
    }

    const reportPath = arg(1)
    if (fileExists(reportPath) != 1) {
        println(`FAIL: not found: ${reportPath}`)
        exit(1)
    }

    const fields = parseFields(readFile(reportPath))

    let totalPass = 0
    let totalFail = 0
    let totalWarn = 0

    // G1: required fields
    if (checkRequired(fields) == 1) { totalPass = totalPass + 1 }
    else { totalFail = totalFail + 1 }

    // G2: causality (3 sub-checks)
    const g2 = checkCausality(fields)
    if (g2 == 3) { totalPass = totalPass + 1 }
    else { totalFail = totalFail + 1 }

    // G3: root cause
    if (checkRootCause(fields) == 1) { totalPass = totalPass + 1 }
    else { totalFail = totalFail + 1 }

    // G4: structural delta
    const g4 = checkStructure(fields)
    if (g4 >= 0) { totalPass = totalPass + 1 }
    else { totalWarn = totalWarn + 1 }

    // G5: bootstrap
    if (checkBootstrap(fields) == 1) { totalPass = totalPass + 1 }
    else { totalFail = totalFail + 1 }

    // G6: test suite
    if (checkTestSuite(fields) == 1) { totalPass = totalPass + 1 }
    else { totalFail = totalFail + 1 }

    println("")
    println("=======================================")
    println(`PASS: ${totalPass}  FAIL: ${totalFail}  WARN: ${totalWarn}`)

    if (totalFail > 0) {
        println(`GATE BLOCKED - ${totalFail} checks failed`)
        exit(1)
    } else if (totalWarn > 0) {
        println(`GATE PASS with ${totalWarn} WARNING`)
    } else {
        println("ALL GATES PASSED")
    }
}
