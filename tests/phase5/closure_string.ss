// Test: closure capturing string from outer scope

function testStringCapture() {
    const prefix = "Hello"
    const greet = (name: string): string => `${prefix} ${name}`
    const result = greet("World")
    if (result != "Hello World") { exit(1) }
}

function testStringMultiCapture() {
    const first = "Good"
    const second = "Morning"
    const combine = (sep: string): string => `${first}${sep}${second}`
    if (combine(" ") != "Good Morning") { exit(1) }
    if (combine("-") != "Good-Morning") { exit(1) }
}

function main() {
    testStringCapture()
    testStringMultiCapture()
}
