import { Lifecycle } from "@/lib/harness/lifecycle"
import { BugfixLifecycle } from "@/lib/harness/bugfix"

function main() {
    const lc = new BugfixLifecycle()

    const phases = lc.phases()
    if (phases != "found,isolate,analyze,resolve,verify") {
        println("FAIL: phases=" + phases)
        exit(1)
    }

    if (lc.goal("found") != "Identify observable bug symptom") {
        println("FAIL: goal(found)")
        exit(1)
    }
    if (lc.goal("isolate") != "Create minimal reproduction with failing test") {
        println("FAIL: goal(isolate)")
        exit(1)
    }
    if (lc.goal("unknown") != "") {
        println("FAIL: goal(unknown) should be empty")
        exit(1)
    }

    if (lc.hook("found") == "") {
        println("FAIL: hook(found) empty")
        exit(1)
    }

    if (lc.required("found") != "meta.title,meta.date,found.symptom") {
        println("FAIL: required(found)")
        exit(1)
    }

    println("All harness tests passed!")
}
