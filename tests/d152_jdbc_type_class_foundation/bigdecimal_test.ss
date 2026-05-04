// D152 Phase 2 — lib/java/math.ss BigDecimal real-type unit test.
//
// Validates the JDBC type class foundation underlying D151 setter
// updateBigDecimal(col, val: BigDecimal) (≥18 method scope, JDBC §15.2.5).
// Pure local — no docker / driver dependency.
//
// See docs/3-decisions/D152-jdbc-type-class-foundation.md §Phase 2.

import { assertEqual } from "@/lib/test"
import { BigDecimal, BigDecimal_fromInt, BigDecimal_fromString } from "@/lib/java/math"

function main() {
    test("ctor + accessor", () => {
        const a = new BigDecimal(1999, 2)
        assertEqual(a.scale(), 2)
        assertEqual(a.unscaledValue(), 1999)
    })

    test("BigDecimal_fromInt", () => {
        const fortyTwo = BigDecimal_fromInt(42)
        assertEqual(fortyTwo.scale(), 0)
        assertEqual(fortyTwo.unscaledValue(), 42)
    })

    test("BigDecimal_fromString basic", () => {
        const price = BigDecimal_fromString("19.99")
        assertEqual(price.scale(), 2)
        assertEqual(price.unscaledValue(), 1999)
    })

    test("BigDecimal_fromString negative", () => {
        const negPi = BigDecimal_fromString("-3.14")
        assertEqual(negPi.scale(), 2)
        assertEqual(negPi.unscaledValue(), -314)
    })

    test("BigDecimal_fromString integer literal", () => {
        const intLit = BigDecimal_fromString("12345")
        assertEqual(intLit.scale(), 0)
        assertEqual(intLit.unscaledValue(), 12345)
    })

    test("precision", () => {
        assertEqual(BigDecimal_fromString("0").precision(), 1)
        assertEqual(BigDecimal_fromString("100").precision(), 3)
        assertEqual(BigDecimal_fromString("-1234").precision(), 4)
        assertEqual(BigDecimal_fromString("19.99").precision(), 4)
    })

    test("signum", () => {
        assertEqual(BigDecimal_fromString("0").signum(), 0)
        assertEqual(BigDecimal_fromString("5.5").signum(), 1)
        assertEqual(BigDecimal_fromString("-5.5").signum(), -1)
    })

    test("add same scale", () => {
        const sum = BigDecimal_fromString("1.99").add(BigDecimal_fromString("0.01"))
        assertEqual(sum.unscaledValue(), 200)
        assertEqual(sum.scale(), 2)
    })

    test("add mismatched scales (align up)", () => {
        const sum = BigDecimal_fromString("1.5").add(BigDecimal_fromString("0.05"))
        assertEqual(sum.unscaledValue(), 155)
        assertEqual(sum.scale(), 2)
    })

    test("subtract", () => {
        const diff = BigDecimal_fromString("5.0").subtract(BigDecimal_fromString("2.5"))
        assertEqual(diff.unscaledValue(), 25)
        assertEqual(diff.scale(), 1)
    })

    test("multiply (scale = a.scale + b.scale)", () => {
        const prod = BigDecimal_fromString("1.5").multiply(BigDecimal_fromString("2.0"))
        assertEqual(prod.unscaledValue(), 300)
        assertEqual(prod.scale(), 2)
    })

    test("negate", () => {
        const neg = BigDecimal_fromString("5.5").negate()
        assertEqual(neg.unscaledValue(), -55)
    })

    test("abs", () => {
        assertEqual(BigDecimal_fromString("-5.5").abs().unscaledValue(), 55)
        assertEqual(BigDecimal_fromString("5.5").abs().unscaledValue(), 55)
    })

    test("compareTo cross-scale (1.0 == 1.00 numerically)", () => {
        assertEqual(BigDecimal_fromString("1.0").compareTo(BigDecimal_fromString("1.00")), 0)
        assertEqual(BigDecimal_fromString("1.99").compareTo(BigDecimal_fromString("2.00")), -1)
        assertEqual(BigDecimal_fromString("2.00").compareTo(BigDecimal_fromString("1.99")), 1)
    })

    // JDK semantics: equals requires same scale (1.0 != 1.00); use compareTo for value equality.
    test("equals JDK semantics (scale-sensitive)", () => {
        assertEqual(BigDecimal_fromString("19.99").equals(BigDecimal_fromString("19.99")), 1)
        assertEqual(BigDecimal_fromString("1.0").equals(BigDecimal_fromString("1.00")), 0)
        assertEqual(BigDecimal_fromString("1.99").equals(BigDecimal_fromString("2.00")), 0)
    })

    test("toString round-trip", () => {
        assertEqual(BigDecimal_fromString("19.99").toString(), "19.99")
        assertEqual(BigDecimal_fromString("-3.14").toString(), "-3.14")
        assertEqual(BigDecimal_fromString("12345").toString(), "12345")
        assertEqual(BigDecimal_fromString("0.05").toString(), "0.05")
        assertEqual(BigDecimal_fromInt(42).toString(), "42")
    })
}
