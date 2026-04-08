// test.ss — Test assertion functions for use with test() framework (D079)
// All assertions throw on failure, caught by the test() wrapper.

function assertEqual(actual: int, expected: int) {
    if (actual != expected) {
        throw(`expected ${expected}, got ${actual}`)
    }
}

function assertEqual(actual: string, expected: string) {
    if (actual != expected) {
        throw(`expected "${expected}", got "${actual}"`)
    }
}

function assertEqual(actual: double, expected: double) {
    if (actual != expected) {
        throw(`expected ${expected}, got ${actual}`)
    }
}

function assertTrue(value: int) {
    if (value == 0) {
        throw("expected true, got false")
    }
}

function assertFalse(value: int) {
    if (value != 0) {
        throw("expected false, got true")
    }
}

function assertNull(value: string) {
    if (value != null) {
        throw(`expected null, got "${value}"`)
    }
}

function assertNotNull(value: string) {
    if (value == null) {
        throw("expected non-null, got null")
    }
}
