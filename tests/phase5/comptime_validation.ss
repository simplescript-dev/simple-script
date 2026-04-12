// Test: comptime structural validation builtins
// fieldCount, fieldNames, implements, isSubclassOf

import { assertEqual, assertTrue } from "@/lib/test"
import { ctAssertHasField, ctAssertImplements, ctAssertExtends } from "@/lib/comptime"

// ── Type hierarchy for testing ──

interface Drawable {
    function draw(): string
}

interface Resizable {
    function resize(factor: int): int
}

class Shape {
    x: int
    y: int
}

class Circle extends Shape : Drawable {
    radius: int

    function draw(): string {
        return "circle"
    }
}

class Square extends Shape : Drawable, Resizable {
    side: int

    function draw(): string {
        return "square"
    }

    function resize(factor: int): int {
        return this.side * factor
    }
}

class ColoredCircle extends Circle {
    color: string
}

class Standalone {
    value: int
}

// ── Comptime validation ──

comptime {
    // fieldCount tests
    const fcShape = fieldCount("Shape")
    const fcCircle = fieldCount("Circle")
    const fcSquare = fieldCount("Square")
    const fcStandalone = fieldCount("Standalone")
    const fcUnknown = fieldCount("NonExistent")

    // fieldNames tests
    const fnShape = fieldNames("Shape")
    const fnCircle = fieldNames("Circle")
    const fnStandalone = fieldNames("Standalone")
    const fnUnknown = fieldNames("NonExistent")

    // implements tests
    const imCircleDraw = hasInterface("Circle", "Drawable")
    const imCircleResize = hasInterface("Circle", "Resizable")
    const imSquareDraw = hasInterface("Square", "Drawable")
    const imSquareResize = hasInterface("Square", "Resizable")
    const imStandaloneDraw = hasInterface("Standalone", "Drawable")
    const imUnknownDraw = hasInterface("NonExistent", "Drawable")
    const imCircleUnknown = hasInterface("Circle", "NonExistent")

    // isSubclassOf tests
    const scCircleShape = isSubclassOf("Circle", "Shape")
    const scSquareShape = isSubclassOf("Square", "Shape")
    const scColoredCircle = isSubclassOf("ColoredCircle", "Circle")
    const scColoredShape = isSubclassOf("ColoredCircle", "Shape")
    const scShapeCircle = isSubclassOf("Shape", "Circle")
    const scStandaloneShape = isSubclassOf("Standalone", "Shape")
    const scUnknown = isSubclassOf("NonExistent", "Shape")
    const scSelf = isSubclassOf("Circle", "Circle")

    @comptimeEmit(`
function testFieldCountShape(): int { return ${fcShape} }
function testFieldCountCircle(): int { return ${fcCircle} }
function testFieldCountSquare(): int { return ${fcSquare} }
function testFieldCountStandalone(): int { return ${fcStandalone} }
function testFieldCountUnknown(): int { return ${fcUnknown} }

function testFieldNamesShape(): string { return "${fnShape}" }
function testFieldNamesCircle(): string { return "${fnCircle}" }
function testFieldNamesStandalone(): string { return "${fnStandalone}" }
function testFieldNamesUnknown(): string { return "${fnUnknown}" }

function testIfaceCircleDraw(): int { return ${imCircleDraw} }
function testIfaceCircleResize(): int { return ${imCircleResize} }
function testIfaceSquareDraw(): int { return ${imSquareDraw} }
function testIfaceSquareResize(): int { return ${imSquareResize} }
function testIfaceStandaloneDraw(): int { return ${imStandaloneDraw} }
function testIfaceUnknownDraw(): int { return ${imUnknownDraw} }
function testIfaceCircleUnknown(): int { return ${imCircleUnknown} }

function testSubCircleShape(): int { return ${scCircleShape} }
function testSubSquareShape(): int { return ${scSquareShape} }
function testSubColoredCircle(): int { return ${scColoredCircle} }
function testSubColoredShape(): int { return ${scColoredShape} }
function testSubShapeCircle(): int { return ${scShapeCircle} }
function testSubStandaloneShape(): int { return ${scStandaloneShape} }
function testSubUnknown(): int { return ${scUnknown} }
function testSubSelf(): int { return ${scSelf} }
`)

    // ── Validation pattern: raw comptimeAssert ──
    comptimeAssert(fieldCount("Circle") > 0, "Circle must have fields")
    comptimeAssert(hasInterface("Circle", "Drawable") == 1, "Circle must implement Drawable")
    comptimeAssert(isSubclassOf("Circle", "Shape") == 1, "Circle must extend Shape")
}

// ── Library helper assertions (from lib/comptime.ss) ─��
comptime {
    ctAssertHasField("Shape", "x")
    ctAssertImplements("Square", "Drawable")
    ctAssertExtends("ColoredCircle", "Shape")
}

function main() {
    // ── fieldCount ──
    test("fieldCount — Shape has 2 fields", () => {
        assertEqual(testFieldCountShape(), 2)
    })
    test("fieldCount — Circle has own fields only", () => {
        // Circle's own field: radius (inherited x,y not in classFields for Circle)
        assertTrue(testFieldCountCircle() >= 1)
    })
    test("fieldCount — Square has own fields", () => {
        assertTrue(testFieldCountSquare() >= 1)
    })
    test("fieldCount — Standalone has 1 field", () => {
        assertEqual(testFieldCountStandalone(), 1)
    })
    test("fieldCount — unknown class returns 0", () => {
        assertEqual(testFieldCountUnknown(), 0)
    })

    // ── fieldNames ──
    test("fieldNames — Shape returns x,y", () => {
        assertEqual(testFieldNamesShape(), "x,y")
    })
    test("fieldNames — Standalone returns value", () => {
        assertEqual(testFieldNamesStandalone(), "value")
    })
    test("fieldNames — unknown returns empty", () => {
        assertEqual(testFieldNamesUnknown(), "")
    })

    // ── hasInterface ──
    test("hasInterface — Circle implements Drawable", () => {
        assertEqual(testIfaceCircleDraw(), 1)
    })
    test("hasInterface — Circle does not implement Resizable", () => {
        assertEqual(testIfaceCircleResize(), 0)
    })
    test("hasInterface — Square implements Drawable", () => {
        assertEqual(testIfaceSquareDraw(), 1)
    })
    test("hasInterface — Square implements Resizable", () => {
        assertEqual(testIfaceSquareResize(), 1)
    })
    test("hasInterface — Standalone does not implement Drawable", () => {
        assertEqual(testIfaceStandaloneDraw(), 0)
    })
    test("hasInterface — unknown class returns 0", () => {
        assertEqual(testIfaceUnknownDraw(), 0)
    })
    test("hasInterface — unknown interface returns 0", () => {
        assertEqual(testIfaceCircleUnknown(), 0)
    })

    // ── isSubclassOf ──
    test("isSubclassOf — Circle extends Shape", () => {
        assertEqual(testSubCircleShape(), 1)
    })
    test("isSubclassOf — Square extends Shape", () => {
        assertEqual(testSubSquareShape(), 1)
    })
    test("isSubclassOf — ColoredCircle extends Circle", () => {
        assertEqual(testSubColoredCircle(), 1)
    })
    test("isSubclassOf — ColoredCircle extends Shape (transitive)", () => {
        assertEqual(testSubColoredShape(), 1)
    })
    test("isSubclassOf — Shape does not extend Circle (not reverse)", () => {
        assertEqual(testSubShapeCircle(), 0)
    })
    test("isSubclassOf — Standalone does not extend Shape", () => {
        assertEqual(testSubStandaloneShape(), 0)
    })
    test("isSubclassOf — unknown class returns 0", () => {
        assertEqual(testSubUnknown(), 0)
    })
    test("isSubclassOf — same class returns 0 (not self)", () => {
        assertEqual(testSubSelf(), 0)
    })
}
