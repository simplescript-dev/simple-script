import { parseReport, fieldGet, checkRequired, checkEquals, checkMinLength } from "@/lib/harness/linter"
import { BugfixLinter } from "@/lib/harness/bugfix_linter"
import { Ini, IniData } from "@/lib/ini"

function main() {
    const content = "[meta]\ntitle = test bug title\ndate = 2026-04-17\n\n[found]\nsymptom = the compiler crashes on class fields with bracket access\n"
    const data = Ini.parse(content)

    const linter = new BugfixLinter()

    println("=== Testing verify(found) ===")
    const r1 = linter.verify("found", data)
    if (r1 != 1) {
        println("FAIL: verify(found) should pass")
        exit(1)
    }

    println("")
    println("=== Testing verify(found) with bad data ===")
    const bad = Ini.parse("[meta]\ntitle = x\n\n[found]\nsymptom = short\n")
    const r2 = linter.verify("found", bad)
    if (r2 != 0) {
        println("FAIL: verify(found) with short symptom should fail")
        exit(1)
    }

    println("")
    println("=== Testing verify(unknown) ===")
    const r3 = linter.verify("unknown", data)
    if (r3 != 0) {
        println("FAIL: verify(unknown) should return 0")
        exit(1)
    }

    println("")
    println("All verify tests passed!")
}
