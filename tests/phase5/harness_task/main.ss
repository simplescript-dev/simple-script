import { Lifecycle } from "@/lib/harness/lifecycle"
import { TaskLifecycle } from "@/lib/harness/task"
import { D093Lifecycle } from "@/.harness/D093-sema-single-dispatch"

function main() {
    const task = new TaskLifecycle()
    if (task.phases() != "scope,design,implement,verify") {
        println("FAIL: task phases=" + task.phases())
        exit(1)
    }
    if (task.goal("scope") == "") {
        println("FAIL: task goal(scope) empty")
        exit(1)
    }

    const d093 = new D093Lifecycle()
    if (d093.phases() != "design,lang_gaps,eliminate_branches,merge_genvalct,split_typedvalue,intern_pool,comptime_flag") {
        println("FAIL: d093 phases=" + d093.phases())
        exit(1)
    }

    if (d093.goal("design") != "Validate MaybeVal/InternPool/Type-as-Value encoding decisions, produce D094") {
        println("FAIL: d093 goal(design)")
        exit(1)
    }
    if (d093.goal("comptime_flag") == "") {
        println("FAIL: d093 goal(comptime_flag) empty")
        exit(1)
    }
    if (d093.hook("eliminate_branches") == "") {
        println("FAIL: d093 hook(eliminate_branches) empty")
        exit(1)
    }
    if (d093.required("intern_pool") != "intern_pool.implemented,intern_pool.bootstrap") {
        println("FAIL: d093 required(intern_pool)")
        exit(1)
    }
    if (d093.goal("nonexistent") != "") {
        println("FAIL: d093 goal(nonexistent) should be empty")
        exit(1)
    }

    println("All task+D093 harness tests passed!")
}
