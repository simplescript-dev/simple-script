// Test: Assert standard library module (D044)

import { Assert } from "@/lib/assert"

function main() {
    // ── isTrue / isFalse ─────────────────────────────────────
    Assert.isTrue(1, "1 is true")
    Assert.isTrue(42, "42 is true")
    Assert.isFalse(0, "0 is false")

    // ── equal (int overload) ─────────────────────────────────
    Assert.equal(0, 0, "zero equals zero")
    Assert.equal(42, 42, "42 equals 42")
    Assert.equal(-1, -1, "negative equals")

    // ── equal (string overload) ──────────────────────────────
    Assert.equal("hello", "hello", "hello equals hello")
    Assert.equal("", "", "empty string equals")
    Assert.equal("abc def", "abc def", "string with space")

    // ── notEqual (int overload) ──────────────────────────────
    Assert.notEqual(1, 2, "1 != 2")
    Assert.notEqual(0, -1, "0 != -1")
    Assert.notEqual(100, 99, "100 != 99")

    // ── notEqual (string overload) ───────────────────────────
    Assert.notEqual("hello", "world", "hello != world")
    Assert.notEqual("abc", "", "abc != empty")
    Assert.notEqual("", "x", "empty != x")

    // ── approxEqual ──────────────────────────────────────────
    Assert.approxEqual(3.14, 3.14159, 0.01, "pi approx")
    Assert.approxEqual(1.0, 1.0, 0.0001, "exact match")
    Assert.approxEqual(0.1, 0.1, 0.0001, "small value")
    Assert.approxEqual(100.0, 100.001, 0.01, "large value approx")

    // ── greaterThan ──────────────────────────────────────────
    Assert.greaterThan(10, 5, "10 > 5")
    Assert.greaterThan(1, 0, "1 > 0")
    Assert.greaterThan(0, -1, "0 > -1")

    // ── lessThan ─────────────────────────────────────────────
    Assert.lessThan(5, 10, "5 < 10")
    Assert.lessThan(-1, 0, "-1 < 0")
    Assert.lessThan(0, 1, "0 < 1")

    // ── greaterOrEqual ───────────────────────────────────────
    Assert.greaterOrEqual(10, 5, "10 >= 5")
    Assert.greaterOrEqual(5, 5, "5 >= 5")
    Assert.greaterOrEqual(0, -1, "0 >= -1")

    // ── lessOrEqual ──────────────────────────────────────────
    Assert.lessOrEqual(5, 10, "5 <= 10")
    Assert.lessOrEqual(5, 5, "5 <= 5")
    Assert.lessOrEqual(-1, 0, "-1 <= 0")

    // ── contains ─────────────────────────────────────────────
    Assert.contains("hello world", "world", "contains world")
    Assert.contains("hello world", "hello", "contains hello")
    Assert.contains("abcdef", "cd", "contains cd")
    Assert.contains("test", "test", "contains full string")
    Assert.contains("test", "", "contains empty string")

    // ── startsWith ───────────────────────────────────────────
    Assert.startsWith("hello world", "hello", "starts with hello")
    Assert.startsWith("abcdef", "abc", "starts with abc")
    Assert.startsWith("test", "test", "starts with full string")
    Assert.startsWith("test", "", "starts with empty")

    // ── endsWith ─────────────────────────────────────────────
    Assert.endsWith("hello world", "world", "ends with world")
    Assert.endsWith("abcdef", "def", "ends with def")
    Assert.endsWith("test", "test", "ends with full string")
    Assert.endsWith("test", "", "ends with empty")

    // ── Combined usage example ───────────────────────────────
    const name = "Alice"
    const age = 30
    Assert.equal(name, "Alice", "name is Alice")
    Assert.equal(age, 30, "age is 30")
    Assert.greaterThan(age, 0, "age is positive")
    Assert.contains(name, "lic", "name contains lic")
    Assert.startsWith(name, "Al", "name starts with Al")
    Assert.endsWith(name, "ce", "name ends with ce")

    println("All assert tests passed!")
}
