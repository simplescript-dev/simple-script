// Test: enum reflection via getTypeInfo() in comptime

import { assertEqual } from "@/lib/test"

enum Color { Red = 1, Green = 2, Blue = 3 }
enum Direction { Up = "up", Down = "down", Left = "left", Right = "right" }
enum Status { Active, Inactive, Pending }

comptime {
    // ── Integer enum with explicit values ──
    const cInfo = getTypeInfo("Color")
    let cKind = cInfo.kind
    let cIsStr = cInfo.isString
    let cCount = cInfo.variants.length()
    let cV0Name = cInfo.variants[0].name
    let cV0Val = cInfo.variants[0].value
    let cV2Name = cInfo.variants[2].name
    let cV2Val = cInfo.variants[2].value

    // ── String enum ──
    const dInfo = getTypeInfo("Direction")
    let dKind = dInfo.kind
    let dIsStr = dInfo.isString
    let dCount = dInfo.variants.length()
    let dV0Name = dInfo.variants[0].name
    let dV0Val = dInfo.variants[0].value
    let dV3Name = dInfo.variants[3].name
    let dV3Val = dInfo.variants[3].value

    // ── Auto-increment enum (starts at 0) ──
    const sInfo = getTypeInfo("Status")
    let sCount = sInfo.variants.length()
    let sV0Val = sInfo.variants[0].value
    let sV1Val = sInfo.variants[1].value
    let sV2Val = sInfo.variants[2].value

    @comptimeEmit(`
function testColorKind(): string { return "${cKind}" }
function testColorIsString(): int { return ${cIsStr} }
function testColorCount(): int { return ${cCount} }
function testColorV0Name(): string { return "${cV0Name}" }
function testColorV0Val(): int { return ${cV0Val} }
function testColorV2Name(): string { return "${cV2Name}" }
function testColorV2Val(): int { return ${cV2Val} }
function testDirKind(): string { return "${dKind}" }
function testDirIsString(): int { return ${dIsStr} }
function testDirCount(): int { return ${dCount} }
function testDirV0Name(): string { return "${dV0Name}" }
function testDirV0Val(): string { return "${dV0Val}" }
function testDirV3Name(): string { return "${dV3Name}" }
function testDirV3Val(): string { return "${dV3Val}" }
function testStatusCount(): int { return ${sCount} }
function testStatusV0(): int { return ${sV0Val} }
function testStatusV1(): int { return ${sV1Val} }
function testStatusV2(): int { return ${sV2Val} }
`)
}

function main() {
    test("int enum reflection", () => {
        assertEqual(testColorKind(), "enum")
        assertEqual(testColorIsString(), 0)
        assertEqual(testColorCount(), 3)
        assertEqual(testColorV0Name(), "Red")
        assertEqual(testColorV0Val(), 1)
        assertEqual(testColorV2Name(), "Blue")
        assertEqual(testColorV2Val(), 3)
    })
    test("string enum reflection", () => {
        assertEqual(testDirKind(), "enum")
        assertEqual(testDirIsString(), 1)
        assertEqual(testDirCount(), 4)
        assertEqual(testDirV0Name(), "Up")
        assertEqual(testDirV0Val(), "up")
        assertEqual(testDirV3Name(), "Right")
        assertEqual(testDirV3Val(), "right")
    })
    test("auto-increment enum reflection", () => {
        assertEqual(testStatusCount(), 3)
        assertEqual(testStatusV0(), 0)
        assertEqual(testStatusV1(), 1)
        assertEqual(testStatusV2(), 2)
    })
}
