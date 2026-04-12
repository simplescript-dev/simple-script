// Test: comptime conditional compilation — predefined constants + comptimeAssert

import { assertEqual } from "@/lib/test"

// Conditional code emission based on OS
comptime {
    if (OS == "linux") {
        @comptimeEmit(`
function platformName(): string {
    return "linux"
}
`)
    } else {
        @comptimeEmit(`
function platformName(): string {
    return "other"
}
`)
    }
}

// Conditional class generation based on ARCH
comptime {
    if (ARCH == "x86_64") {
        @comptimeEmit(`
class PlatformInfo {
    arch: string
    bits: int
}
`)
    }
}

// comptimeAssert — should pass (true condition)
comptime {
    comptimeAssert(1 == 1, "basic truth check failed")
    comptimeAssert(OS != "", "OS must not be empty")
    comptimeAssert(ARCH != "", "ARCH must not be empty")
    comptimeAssert(COMPILER_VERSION != "", "COMPILER_VERSION must not be empty")
}

// Conditional method generation based on DEBUG
comptime {
    if (DEBUG == 1) {
        @comptimeEmit(`
function buildMode(): string {
    return "debug"
}
`)
    } else {
        @comptimeEmit(`
function buildMode(): string {
    return "release"
}
`)
    }
}

// Use getenv to read arbitrary environment variable
comptime {
    const home = getenv("HOME")
    comptimeAssert(home != "", "HOME env var must be set")
}

// Comptime conditional: generate different implementations
comptime {
    const target = OS + "-" + ARCH
    @comptimeEmit(`
function targetTriple(): string {
    return "${target}"
}
`)
}

function main() {
    test("comptime conditional — OS-based function generation", () => {
        assertEqual(platformName(), "linux")
    })
    test("comptime conditional — ARCH-based class generation", () => {
        const info = new PlatformInfo(arch: "x86_64", bits: 64)
        assertEqual(info.arch, "x86_64")
        assertEqual(info.bits, 64)
    })
    test("comptime conditional — DEBUG flag", () => {
        assertEqual(buildMode(), "debug")
    })
    test("comptime conditional — target triple from constants", () => {
        assertEqual(targetTriple(), "linux-x86_64")
    })
    test("comptime conditional — predefined constants accessible", () => {
        const os = comptime { return OS }
        const arch = comptime { return ARCH }
        const ver = comptime { return COMPILER_VERSION }
        assertEqual(os, "linux")
        assertEqual(arch, "x86_64")
        assertEqual(ver, "0.1.0")
    })
}
