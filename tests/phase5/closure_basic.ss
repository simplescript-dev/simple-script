// Test: basic closure — arrow function capturing variables from outer scope

function testIntCapture() {
    const threshold = 10
    const check = (x: int): int => x > threshold ? 1 : 0
    if (check(15) != 1) { exit(1) }
    if (check(5) != 0) { exit(1) }
}

function testMultiCapture() {
    const a = 3
    const b = 7
    const sum = (x: int): int => x + a + b
    if (sum(10) != 20) { exit(1) }
}

function testNonCapturingStillWorks() {
    const twice = (x: int): int => x * 2
    if (twice(21) != 42) { exit(1) }
}

function testCaptureAndCall() {
    const offset = 100
    const addOffset = (x: int): int => x + offset
    const result = addOffset(23)
    if (result != 123) { exit(1) }
}

function main() {
    testIntCapture()
    testMultiCapture()
    testNonCapturingStillWorks()
    testCaptureAndCall()
}
