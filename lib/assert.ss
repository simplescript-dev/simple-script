// SimpleScript Assert Library — Lightweight test assertions
//
// Usage:
//   import { Assert } from "@/lib/assert"
//
//   Assert.isTrue(x > 0, "x positive")
//   Assert.equal(42, 42, "answer")
//   Assert.equal("hello", "hello", "greeting")
//   Assert.approxEqual(3.14, 3.14159, 0.01, "pi")
//   Assert.contains("hello world", "world", "has world")

class Assert {}

// ── Internal ─────────────────────────────────────────────────

function assertFail(method: string, msg: string, detail: string) {
    if (detail != "") {
        println(`FAIL: ${msg} — ${detail}`)
    } else {
        println(`FAIL: ${msg}`)
    }
    exit(1)
}

// ── Boolean checks ───────────────────────────────────────────

function Assert_isTrue(value: int, msg: string) {
    if (value == 0) {
        assertFail("isTrue", msg, "expected true, got false")
    }
}

function Assert_isFalse(value: int, msg: string) {
    if (value != 0) {
        assertFail("isFalse", msg, "expected false, got true")
    }
}

// ── Equality (string overload) ───────────────────────────────

function Assert_equal(actual: string, expected: string, msg: string) {
    if (actual != expected) {
        assertFail("equal", msg, `expected "${expected}", got "${actual}"`)
    }
}

// ── Equality (int overload) ──────────────────────────────────

function Assert_equal(actual: int, expected: int, msg: string) {
    if (actual != expected) {
        assertFail("equal", msg, `expected ${expected}, got ${actual}`)
    }
}

// ── Not-equal (string overload) ──────────────────────────────

function Assert_notEqual(actual: string, expected: string, msg: string) {
    if (actual == expected) {
        assertFail("notEqual", msg, `expected value to differ from "${expected}"`)
    }
}

// ── Not-equal (int overload) ─────────────────────────────────

function Assert_notEqual(actual: int, expected: int, msg: string) {
    if (actual == expected) {
        assertFail("notEqual", msg, `expected value to differ from ${expected}`)
    }
}

// ── Approximate equality (double) ────────────────────────────

function Assert_approxEqual(actual: double, expected: double, epsilon: double, msg: string) {
    const diff = Math.abs(actual - expected)
    if (diff > epsilon) {
        assertFail("approxEqual", msg, `expected ~${expected}, got ${actual} (diff=${diff}, eps=${epsilon})`)
    }
}

// ── Comparison (int) ─────────────────────────────────────────

function Assert_greaterThan(actual: int, expected: int, msg: string) {
    if (actual <= expected) {
        assertFail("greaterThan", msg, `expected ${actual} > ${expected}`)
    }
}

function Assert_lessThan(actual: int, expected: int, msg: string) {
    if (actual >= expected) {
        assertFail("lessThan", msg, `expected ${actual} < ${expected}`)
    }
}

function Assert_greaterOrEqual(actual: int, expected: int, msg: string) {
    if (actual < expected) {
        assertFail("greaterOrEqual", msg, `expected ${actual} >= ${expected}`)
    }
}

function Assert_lessOrEqual(actual: int, expected: int, msg: string) {
    if (actual > expected) {
        assertFail("lessOrEqual", msg, `expected ${actual} <= ${expected}`)
    }
}

// ── String checks ────────────────────────────────────────────

function Assert_contains(text: string, substr: string, msg: string) {
    if (text.indexOf(substr) == -1) {
        assertFail("contains", msg, `"${text}" does not contain "${substr}"`)
    }
}

function Assert_startsWith(text: string, prefix: string, msg: string) {
    const pLen = prefix.length()
    if (text.length() < pLen) {
        assertFail("startsWith", msg, `"${text}" does not start with "${prefix}"`)
    }
    if (text.substring(0, pLen) != prefix) {
        assertFail("startsWith", msg, `"${text}" does not start with "${prefix}"`)
    }
}

function Assert_endsWith(text: string, suffix: string, msg: string) {
    const tLen = text.length()
    const sLen = suffix.length()
    if (tLen < sLen) {
        assertFail("endsWith", msg, `"${text}" does not end with "${suffix}"`)
    }
    if (text.substring(tLen - sLen, sLen) != suffix) {
        assertFail("endsWith", msg, `"${text}" does not end with "${suffix}"`)
    }
}

// ── Unconditional failure ────────────────────────────────────

function Assert_fail(msg: string) {
    assertFail("fail", msg, "")
}
