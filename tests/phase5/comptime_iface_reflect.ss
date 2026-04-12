// Test: interface reflection via getTypeInfo() in comptime

import { assertEqual } from "@/lib/test"

interface Shape {
    function area(): double
    function name(): string
}

interface Processor {
    function process(data: string, count: int): string
}

interface Marker {}

comptime {
    // ── Shape: 2 methods, no params ──
    const sInfo = getTypeInfo("Shape")
    let sKind = sInfo.kind
    let sName = sInfo.name
    let sMCount = sInfo.methods.length()
    let sM0Name = sInfo.methods[0].name
    let sM0Ret = sInfo.methods[0].returnType
    let sM0PCount = sInfo.methods[0].params.length()
    let sM1Name = sInfo.methods[1].name
    let sM1Ret = sInfo.methods[1].returnType

    // ── Processor: 1 method with 2 params ──
    const pInfo = getTypeInfo("Processor")
    let pMCount = pInfo.methods.length()
    let pM0Name = pInfo.methods[0].name
    let pM0Ret = pInfo.methods[0].returnType
    let pM0PCount = pInfo.methods[0].params.length()
    let pM0P0Name = pInfo.methods[0].params[0].name
    let pM0P0Type = pInfo.methods[0].params[0].type
    let pM0P1Name = pInfo.methods[0].params[1].name
    let pM0P1Type = pInfo.methods[0].params[1].type

    // ── Marker: empty interface ──
    const mInfo = getTypeInfo("Marker")
    let mKind = mInfo.kind
    let mMCount = mInfo.methods.length()

    @comptimeEmit(`
function testShapeKind(): string { return "${sKind}" }
function testShapeName(): string { return "${sName}" }
function testShapeMethodCount(): int { return ${sMCount} }
function testShapeM0Name(): string { return "${sM0Name}" }
function testShapeM0Ret(): string { return "${sM0Ret}" }
function testShapeM0ParamCount(): int { return ${sM0PCount} }
function testShapeM1Name(): string { return "${sM1Name}" }
function testShapeM1Ret(): string { return "${sM1Ret}" }
function testProcessorMethodCount(): int { return ${pMCount} }
function testProcessorM0Name(): string { return "${pM0Name}" }
function testProcessorM0Ret(): string { return "${pM0Ret}" }
function testProcessorM0ParamCount(): int { return ${pM0PCount} }
function testProcessorP0Name(): string { return "${pM0P0Name}" }
function testProcessorP0Type(): string { return "${pM0P0Type}" }
function testProcessorP1Name(): string { return "${pM0P1Name}" }
function testProcessorP1Type(): string { return "${pM0P1Type}" }
function testMarkerKind(): string { return "${mKind}" }
function testMarkerMethodCount(): int { return ${mMCount} }
`)
}

function main() {
    test("interface reflection - Shape", () => {
        assertEqual(testShapeKind(), "interface")
        assertEqual(testShapeName(), "Shape")
        assertEqual(testShapeMethodCount(), 2)
        assertEqual(testShapeM0Name(), "area")
        assertEqual(testShapeM0Ret(), "double")
        assertEqual(testShapeM0ParamCount(), 0)
        assertEqual(testShapeM1Name(), "name")
        assertEqual(testShapeM1Ret(), "string")
    })
    test("interface reflection - Processor with params", () => {
        assertEqual(testProcessorMethodCount(), 1)
        assertEqual(testProcessorM0Name(), "process")
        assertEqual(testProcessorM0Ret(), "string")
        assertEqual(testProcessorM0ParamCount(), 2)
        assertEqual(testProcessorP0Name(), "data")
        assertEqual(testProcessorP0Type(), "string")
        assertEqual(testProcessorP1Name(), "count")
        assertEqual(testProcessorP1Type(), "int")
    })
    test("interface reflection - empty Marker", () => {
        assertEqual(testMarkerKind(), "interface")
        assertEqual(testMarkerMethodCount(), 0)
    })
}
