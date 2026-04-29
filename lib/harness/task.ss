import { Lifecycle } from "./lifecycle"

class TaskLifecycle extends Lifecycle {
    override function phases(): string {
        return "scope,design,implement,verify"
    }

    override function goal(phase: string): string {
        if (phase == "scope") { return "Define boundaries, dependencies, and prerequisites" }
        if (phase == "design") { return "Design approach, validate feasibility" }
        if (phase == "implement") { return "Execute implementation with bootstrap verification" }
        if (phase == "verify") { return "Full bootstrap + test suite green" }
        return ""
    }

    override function hook(phase: string): string {
        if (phase == "scope") { return "List what changes, what doesn't. Identify blocking dependencies." }
        if (phase == "design") { return "Design from principles, not from existing code. Produce D-doc if needed." }
        if (phase == "implement") { return "Bootstrap after each meaningful change. No dual-track allowed." }
        if (phase == "verify") { return "Run bootstrap + full test suite. Record results." }
        return ""
    }

    override function required(phase: string): string {
        if (phase == "scope") { return "meta.title,meta.date,scope.depends_on,scope.changes" }
        if (phase == "design") { return "design.approach,design.rejected" }
        if (phase == "implement") { return "implement.bootstrap,implement.files_changed" }
        if (phase == "verify") { return "verify.bootstrap,verify.test_passed,verify.test_failed" }
        return ""
    }
}
