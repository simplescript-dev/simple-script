import { Bug } from "@/lib/harness/bug"

let detectedLog = ""
let fixedLog = ""

function main() {
    let bug = new Bug("test-bug")

    bug.onDetected(() => {
        if (bug.importance >= 4 && bug.urgency >= 4) {
            detectedLog = "critical"
        } else {
            detectedLog = "normal"
        }
    })

    bug.onFixed(() => {
        if (bug.certainty < 50) {
            fixedLog = "low"
        } else if (bug.certainty >= 80) {
            fixedLog = "high"
        } else {
            fixedLog = "medium"
        }
    })

    bug.detected(5, 5)
    if (detectedLog != "critical") { exit(1) }

    bug.detected(2, 1)
    if (detectedLog != "normal") { exit(1) }

    bug.fixed(1, 90)
    if (fixedLog != "high") { exit(1) }

    bug.fixed(2, 30)
    if (fixedLog != "low") { exit(1) }

    bug.fixed(1, 60)
    if (fixedLog != "medium") { exit(1) }

    let bug2 = new Bug("no-callbacks")
    bug2.detected(3, 3)
    bug2.fixed(1, 100)

    println("harness_bug: all passed")
}
