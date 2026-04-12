// Test: comptime shell execution — system()/shellOutput() at compile time

import { assertEqual, assertTrue } from "@/lib/test"

// Embed git commit hash at compile time
const gitHash = comptime {
    const hash = shellOutput("git rev-parse --short HEAD").trim()
    return hash
}

// Embed build timestamp at compile time
const buildTime = comptime {
    return shellOutput("date -u +%Y-%m-%d").trim()
}

// Detect machine architecture dynamically
const machineArch = comptime {
    return shellOutput("uname -m").trim()
}

// Use system() to check exit code
const lsExitCode = comptime {
    return system("ls / > /dev/null 2>&1")
}

// Conditional compilation based on shell output
comptime {
    const kernel = shellOutput("uname -s").trim()
    if (kernel == "Linux") {
        @comptimeEmit(`
function kernelName(): string {
    return "Linux"
}
`)
    } else {
        @comptimeEmit(`
function kernelName(): string {
    return "other"
}
`)
    }
}

// Generate build info function from multiple shell commands
comptime {
    const user = shellOutput("whoami").trim()
    const hostname = shellOutput("hostname").trim()
    @comptimeEmit(`
function buildInfo(): string {
    return "${user}@${hostname}"
}
`)
}

function main() {
    test("comptime shell — git hash embedded", () => {
        assertTrue(gitHash.length() >= 7)
        assertTrue(gitHash.length() <= 12)
    })
    test("comptime shell — build timestamp embedded", () => {
        assertTrue(buildTime.indexOf("-") > 0)
        assertTrue(buildTime.length() == 10)
    })
    test("comptime shell — machine arch detected", () => {
        assertTrue(machineArch.length() > 0)
        assertEqual(machineArch, "x86_64")
    })
    test("comptime shell — system exit code", () => {
        assertEqual(lsExitCode, 0)
    })
    test("comptime shell — conditional on kernel", () => {
        assertEqual(kernelName(), "Linux")
    })
    test("comptime shell — build info from shell", () => {
        assertTrue(buildInfo().indexOf("@") >= 0)
    })
}
