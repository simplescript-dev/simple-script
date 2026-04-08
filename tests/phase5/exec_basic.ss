// Test: D080 exec() process output capture

function main() {
    // Test 1: capture stdout
    const r1 = exec("echo hello")
    if (r1.stdout != "hello\n") { exit(1) }
    if (r1.exitCode != 0) { exit(1) }

    // Test 2: non-zero exit code
    const r2 = exec("false")
    if (r2.exitCode == 0) { exit(2) }

    // Test 3: multi-line output
    const r3 = exec("printf 'line1\nline2\nline3'")
    if (r3.stdout != "line1\nline2\nline3") { exit(3) }
    if (r3.exitCode != 0) { exit(3) }

    // Test 4: empty output
    const r4 = exec("true")
    if (r4.stdout != "") { exit(4) }
    if (r4.exitCode != 0) { exit(4) }

    // Test 5: access .stdout directly
    const out = exec("echo direct").stdout
    if (out != "direct\n") { exit(5) }
}
