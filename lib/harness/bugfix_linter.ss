// harness/bugfix_linter.ss — BugfixLinter: mechanical verification for bug fix reports
//
// Usage:
//   import { BugfixLinter } from "@/lib/harness/bugfix_linter"
//   import { parseReport } from "@/lib/harness/linter"
//   const data = parseReport("report.bugfix")
//   const linter = new BugfixLinter()
//   linter.verifyAll(data)

import { Linter, parseReport, fieldGet, fieldFilled, checkRequired, checkEquals, checkMinLength, checkNonzero, checkMax, checkFileExists, runBootstrap, runTestSuite } from "./linter"

function bfVerifyFound(data: IniData): int {
    println("-- Phase 1/5: FOUND")
    let ok = 1
    if (checkRequired("meta.title,meta.date,found.symptom", data) > 0) { ok = 0 }
    if (checkMinLength("found.symptom", 10, data) == 0) { ok = 0 }
    if (ok == 1) { println("  PASS") }
    return ok
}

function bfVerifyIsolate(data: IniData): int {
    println("")
    println("-- Phase 2/5: ISOLATE")
    let ok = 1
    if (checkRequired("isolate.test_file,isolate.stash_exit", data) > 0) { ok = 0 }
    if (checkFileExists("isolate.test_file", data) == 0) { ok = 0 }
    if (checkNonzero("isolate.stash_exit", data) == 0) { ok = 0 }
    if (ok == 1) { println("  PASS") }
    return ok
}

function bfVerifyAnalyze(data: IniData): int {
    println("")
    println("-- Phase 3/5: ANALYZE")
    let ok = 1
    if (checkRequired("analyze.broken,analyze.why,analyze.fix,analyze.same_pattern_count,analyze.root_or_workaround", data) > 0) { ok = 0 }
    if (checkMinLength("analyze.broken", 10, data) == 0) { ok = 0 }
    if (checkMinLength("analyze.why", 10, data) == 0) { ok = 0 }
    if (checkMinLength("analyze.fix", 10, data) == 0) { ok = 0 }
    if (checkEquals("analyze.same_pattern_count", "0", data) == 0) { ok = 0 }
    if (checkEquals("analyze.root_or_workaround", "root", data) == 0) { ok = 0 }
    if (ok == 1) { println("  PASS") }
    return ok
}

function bfVerifyResolve(data: IniData): int {
    println("")
    println("-- Phase 4/5: RESOLVE")
    let ok = 1
    if (checkRequired("resolve.fix_exit,resolve.net_new_ifs,resolve.net_new_fns", data) > 0) { ok = 0 }

    const testFile = fieldGet(data, "isolate.test_file")
    if (testFile != "" && fileExists(testFile) == 1) {
        const ec = system(`bin/ss run ${testFile} >/dev/null 2>&1`)
        if (ec == 0) {
            println("  PASS: test exit=0 (verified)")
        } else {
            println(`  FAIL: test exit=${ec}`)
            ok = 0
        }
    }

    if (checkEquals("resolve.fix_exit", "0", data) == 0) { ok = 0 }
    if (checkMax("resolve.net_new_ifs", 2, data) == 0) { ok = 0 }
    if (checkMax("resolve.net_new_fns", 1, data) == 0) { ok = 0 }
    if (ok == 1) { println("  PASS") }
    return ok
}

function bfVerifyFinal(data: IniData): int {
    println("")
    println("-- Phase 5/5: VERIFY")
    let ok = 1
    if (checkRequired("verify.bootstrap,verify.test_passed,verify.test_failed", data) > 0) { ok = 0 }
    if (runBootstrap() == 0) { ok = 0 }
    if (checkEquals("verify.bootstrap", "PASS", data) == 0) { ok = 0 }

    const summary = runTestSuite()
    println(`  actual: ${summary}`)

    const nfail = parseInt(fieldGet(data, "verify.test_failed"))
    let nknown = 0
    const kv = fieldGet(data, "verify.test_known_fail")
    if (kv != "") { nknown = parseInt(kv) }
    const effective = nfail - nknown
    if (effective > 0) {
        println(`  FAIL: ${nfail} failures, ${effective} non-known`)
        ok = 0
    } else {
        println(`  PASS: failures=${nfail}, known=${nknown}`)
    }

    if (ok == 1) { println("  PASS") }
    return ok
}

class BugfixLinter extends Linter {
    override function verify(phase: string, data: IniData): int {
        if (phase == "found") { return bfVerifyFound(data) }
        if (phase == "isolate") { return bfVerifyIsolate(data) }
        if (phase == "analyze") { return bfVerifyAnalyze(data) }
        if (phase == "resolve") { return bfVerifyResolve(data) }
        if (phase == "verify") { return bfVerifyFinal(data) }
        return 0
    }

    override function verifyAll(data: IniData): int {
        const p1 = bfVerifyFound(data)
        const p2 = bfVerifyIsolate(data)
        const p3 = bfVerifyAnalyze(data)
        const p4 = bfVerifyResolve(data)
        const p5 = bfVerifyFinal(data)
        const pass = p1 + p2 + p3 + p4 + p5
        const fail = 5 - pass

        println("")
        println("=======================================")
        println(`BUGFIX: ${pass}/5 PASS, ${fail}/5 FAIL`)
        if (fail > 0) {
            println(`BLOCKED - ${fail} phases incomplete`)
            return 0
        }
        println("ALL PHASES PASSED")
        return 1
    }
}
