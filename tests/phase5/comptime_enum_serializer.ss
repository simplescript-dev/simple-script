// Test: comptime-driven enum serializer — auto-generate nameOf/fromString

import { assertEqual } from "@/lib/test"

enum Color { Red = 1, Green = 2, Blue = 3 }
enum Direction { Up = "up", Down = "down", Left = "left", Right = "right" }
enum Status { Active, Inactive, Pending }

comptime {
    // Generate nameOf: value → variant name string
    function genNameOf(enumName: string): string {
        const info = getTypeInfo(enumName)
        let body = ""
        let i = 0
        while (i < info.variants.length()) {
            const v = info.variants[i]
            if (info.isString == 1) {
                body = body + `    if (value == "${v.value}") { return "${v.name}" }\n`
            } else {
                body = body + `    if (value == ${v.value}) { return "${v.name}" }\n`
            }
            i = i + 1
        }
        let paramType = "int"
        if (info.isString == 1) { paramType = "string" }
        return `function ${enumName}_nameOf(value: ${paramType}): string {\n${body}    return "unknown"\n}`
    }

    // Generate fromString: name string → value
    function genFromString(enumName: string): string {
        const info = getTypeInfo(enumName)
        let body = ""
        let i = 0
        while (i < info.variants.length()) {
            const v = info.variants[i]
            if (info.isString == 1) {
                body = body + `    if (name == "${v.name}") { return "${v.value}" }\n`
            } else {
                body = body + `    if (name == "${v.name}") { return ${v.value} }\n`
            }
            i = i + 1
        }
        let retType = "int"
        if (info.isString == 1) { retType = "string" }
        return `function ${enumName}_fromString(name: string): ${retType} {\n${body}    return ${info.isString == 1 ? "\"\"" : "-1"}\n}`
    }

    // Generate for all three enums
    const code = genNameOf("Color") + "\n" + genFromString("Color") + "\n" + genNameOf("Direction") + "\n" + genFromString("Direction") + "\n" + genNameOf("Status") + "\n" + genFromString("Status")
    @comptimeEmit(code)
}

function main() {
    test("Color nameOf", () => {
        assertEqual(Color_nameOf(1), "Red")
        assertEqual(Color_nameOf(2), "Green")
        assertEqual(Color_nameOf(3), "Blue")
        assertEqual(Color_nameOf(99), "unknown")
    })
    test("Color fromString", () => {
        assertEqual(Color_fromString("Red"), 1)
        assertEqual(Color_fromString("Blue"), 3)
        assertEqual(Color_fromString("invalid"), -1)
    })
    test("Direction nameOf (string enum)", () => {
        assertEqual(Direction_nameOf("up"), "Up")
        assertEqual(Direction_nameOf("right"), "Right")
        assertEqual(Direction_nameOf("???"), "unknown")
    })
    test("Direction fromString (string enum)", () => {
        assertEqual(Direction_fromString("Up"), "up")
        assertEqual(Direction_fromString("Right"), "right")
        assertEqual(Direction_fromString("invalid"), "")
    })
    test("Status nameOf (auto-increment)", () => {
        assertEqual(Status_nameOf(0), "Active")
        assertEqual(Status_nameOf(1), "Inactive")
        assertEqual(Status_nameOf(2), "Pending")
    })
    test("Status fromString (auto-increment)", () => {
        assertEqual(Status_fromString("Active"), 0)
        assertEqual(Status_fromString("Pending"), 2)
    })
}
