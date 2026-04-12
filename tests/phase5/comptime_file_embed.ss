// Test: comptime file I/O — readFile/fileExists/writeFile at compile time

import { assertEqual, assertTrue } from "@/lib/test"

// Embed file content at compile time (like Zig's @embedFile)
const embeddedData = comptime {
    return readFile("tests/phase5/comptime_embed_data.txt")
}

// Compile-time file existence check
const dataFileExists = comptime {
    return fileExists("tests/phase5/comptime_embed_data.txt")
}
const missingFileExists = comptime {
    return fileExists("tests/phase5/nonexistent_file.txt")
}

// Conditional code generation based on file existence
comptime {
    if (fileExists("tests/phase5/comptime_embed_data.txt") == 1) {
        @comptimeEmit(`
function hasEmbedData(): int {
    return 1
}
`)
    } else {
        @comptimeEmit(`
function hasEmbedData(): int {
    return 0
}
`)
    }
}

// Parse embedded config at compile time → generate constants
comptime {
    const content = readFile("tests/phase5/comptime_embed_data.txt")
    const lines = content.split("\n")
    let i = 0
    let nameVal = ""
    let versionVal = ""
    while (i < lines.length()) {
        const line = lines[i]
        const eqPos = line.indexOf("=")
        if (eqPos >= 0) {
            const key = line.substring(0, eqPos)
            const val = line.substring(eqPos + 1, line.length())
            if (key == "name") { nameVal = val }
            if (key == "version") { versionVal = val }
        }
        i = i + 1
    }
    @comptimeEmit(`
function configName(): string {
    return "${nameVal}"
}
function configVersion(): string {
    return "${versionVal}"
}
`)
}

// Write file at compile time, then read it back
comptime {
    writeFile("/tmp/ss_comptime_gen.txt", "generated-at-compile-time")
    const check = readFile("/tmp/ss_comptime_gen.txt")
    comptimeAssert(check == "generated-at-compile-time", "writeFile/readFile round-trip failed")
}

function main() {
    test("comptime file embed — readFile at compile time", () => {
        assertTrue(embeddedData.indexOf("SimpleScript") >= 0)
        assertTrue(embeddedData.indexOf("version=0.1.0") >= 0)
    })
    test("comptime file embed — fileExists check", () => {
        assertEqual(dataFileExists, 1)
        assertEqual(missingFileExists, 0)
    })
    test("comptime file embed — conditional on file existence", () => {
        assertEqual(hasEmbedData(), 1)
    })
    test("comptime file embed — parse config at compile time", () => {
        assertEqual(configName(), "SimpleScript")
        assertEqual(configVersion(), "0.1.0")
    })
    test("comptime file embed — writeFile at compile time", () => {
        // The comptimeAssert in the comptime block already verified this
        // If we got here, the write+read round-trip succeeded at compile time
        assertTrue(1 == 1)
    })
}
