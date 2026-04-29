import { Linter, parseReport, fieldGet, fieldFilled, checkRequired } from "@/lib/harness/linter"
import { BugfixLinter } from "@/lib/harness/bugfix_linter"
import { Ini, IniData } from "@/lib/ini"

function main() {
    const content = "[meta]\ntitle = test bug\ndate = 2026-04-17\n\n[found]\nsymptom = something is broken here badly\n"
    const data = Ini.parse(content)

    const title = fieldGet(data, "meta.title")
    if (title != "test bug") {
        println("FAIL: fieldGet meta.title=" + title)
        exit(1)
    }

    const symptom = fieldGet(data, "found.symptom")
    if (symptom != "something is broken here badly") {
        println("FAIL: fieldGet found.symptom=" + symptom)
        exit(1)
    }

    if (fieldFilled(data, "meta.title") != 1) {
        println("FAIL: fieldFilled meta.title")
        exit(1)
    }
    if (fieldFilled(data, "nonexist.key") != 0) {
        println("FAIL: fieldFilled nonexist.key should be 0")
        exit(1)
    }

    const linter = new BugfixLinter()
    println("BugfixLinter created successfully")
    println("All linter tests passed!")
}
