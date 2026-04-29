// harness/bugfix.ss — BugfixLifecycle: 6-phase bug fix lifecycle
//
// Usage:
//   import { BugfixLifecycle } from "@/lib/harness/bugfix"
//   const lc = new BugfixLifecycle()
//   println(lc.goal("analyze"))
//   println(lc.hook("analyze"))

import { Lifecycle } from "./lifecycle"

class BugfixLifecycle extends Lifecycle {
    override function phases(): string {
        return "found,isolate,analyze,resolve,verify"
    }

    override function goal(phase: string): string {
        if (phase == "found") { return "Identify observable bug symptom" }
        if (phase == "isolate") { return "Create minimal reproduction with failing test" }
        if (phase == "analyze") { return "Identify root cause mechanism, not symptom" }
        if (phase == "resolve") { return "Implement fix, verify test passes" }
        if (phase == "verify") { return "Bootstrap fixed-point + full test suite green" }
        return ""
    }

    override function hook(phase: string): string {
        if (phase == "found") { return "Describe bug symptom precisely. Include error message or wrong output." }
        if (phase == "isolate") { return "Create minimal test. Stash fix, run test, record stash_exit (must != 0)." }
        if (phase == "analyze") { return "Root cause or workaround? Compare alternatives. Grep for same pattern." }
        if (phase == "resolve") { return "Implement fix. Run test. Record structural delta." }
        if (phase == "verify") { return "Run bootstrap + full test suite. Record results." }
        return ""
    }

    override function required(phase: string): string {
        if (phase == "found") { return "meta.title,meta.date,found.symptom" }
        if (phase == "isolate") { return "isolate.test_file,isolate.stash_exit" }
        if (phase == "analyze") { return "analyze.broken,analyze.why,analyze.fix,analyze.same_pattern_count,analyze.root_or_workaround" }
        if (phase == "resolve") { return "resolve.fix_exit,resolve.net_new_ifs,resolve.net_new_fns" }
        if (phase == "verify") { return "verify.bootstrap,verify.test_passed,verify.test_failed" }
        return ""
    }
}
