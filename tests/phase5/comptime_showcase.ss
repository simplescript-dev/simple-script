// Test: comptime comprehensive showcase — combines all features in a real-world scenario
//
// Scenario: Mini application framework that uses comptime for:
//   1. Build metadata embedding (shell execution)
//   2. Config parsing from file (file I/O + string ops)
//   3. Domain model serialization (@derive built-in)
//   4. Schema introspection (user-defined @derive)
//   5. Auto-registry of serializable types (type discovery + hasMethod)
//   6. Debug/release conditional code (conditional compilation)
//   7. Compile-time validation (comptimeAssert)

import { assertEqual, assertTrue } from "@/lib/test"
import { } from "@/lib/comptime"

// ── 1. Build Metadata via shell execution ──

const BUILD_HASH = comptime { return shellOutput("echo abc123def").trim() }
const BUILD_OS = comptime { return OS }

// ── 2. Config Parsing via file I/O ──

comptime {
    writeFile("/tmp/ss_showcase.conf", "app.name=TaskManager\napp.version=2.1.0\napp.maxWorkers=8")
    const raw = readFile("/tmp/ss_showcase.conf")
    comptimeAssert(raw != "", "config file must not be empty")

    const lines = raw.split("\n")
    let appName = ""
    let appVersion = ""
    let maxWorkers = ""
    let i = 0
    while (i < lines.length()) {
        const line = lines[i]
        const eqPos = line.indexOf("=")
        if (eqPos >= 0) {
            const key = line.substring(0, eqPos)
            const val = line.substring(eqPos + 1, line.length())
            if (key == "app.name") { appName = val }
            if (key == "app.version") { appVersion = val }
            if (key == "app.maxWorkers") { maxWorkers = val }
        }
        i = i + 1
    }
    comptimeAssert(appName != "", "app.name is required")
    comptimeAssert(appVersion != "", "app.version is required")

    @comptimeEmit(`
const APP_NAME = "${appName}"
const APP_VERSION = "${appVersion}"
const MAX_WORKERS = ${maxWorkers}
`)
}

// ── 3. Domain Models with built-in @derive ──

@derive("ToJson,Equals")
class Task {
    id: int
    title: string
    done: int
}

@derive("ToJson,ToString")
class Worker {
    name: string
    taskCount: int
}

// ── 4. User-defined @derive("Schema") — type introspection ──

comptime {
    function ctDeriveSchema(className: string) {
        const info = getTypeInfo(className)
        let pairs = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { pairs = pairs + ", " }
            pairs = pairs + f.name + ": " + f.type
            i = i + 1
        }
        @comptimeEmit(`function schema(): string { return "${className}(${pairs})" }`)
    }
}

@derive("Schema")
class AppInfo {
    name: string
    version: string
    workers: int
}

// ── 5. Auto-Registry via type discovery ──

comptime {
    const classes = classNames()
    let jsonClasses = ""
    let count = 0
    let i = 0
    while (i < classes.length()) {
        const cls = classes[i]
        if (hasMethod(cls, "toJson") == 1) {
            if (count > 0) { jsonClasses = jsonClasses + "," }
            jsonClasses = jsonClasses + cls
            count = count + 1
        }
        i = i + 1
    }
    @comptimeEmit(`
function getJsonCapableClasses(): string { return "${jsonClasses}" }
function getJsonCapableCount(): int { return ${count} }
`)
}

// ── 6. Conditional Compilation ──

comptime {
    if (DEBUG == 1) {
        @comptimeEmit(`function getBuildMode(): string { return "debug" }`)
    } else {
        @comptimeEmit(`function getBuildMode(): string { return "release" }`)
    }
}

// ── 7. Build summary (shell + config combined) ──

comptime {
    const hash = shellOutput("echo abc123def").trim()
    @comptimeEmit(`function buildSummary(): string { return APP_NAME + " v" + APP_VERSION + " (" + "${hash}" + ")" }`)
}

function main() {
    // 1. Build metadata
    test("showcase — build hash from shell", () => {
        assertEqual(BUILD_HASH, "abc123def")
    })
    test("showcase — build OS constant", () => {
        assertEqual(BUILD_OS, "linux")
    })

    // 2. Config parsed at compile time
    test("showcase — config constants", () => {
        assertEqual(APP_NAME, "TaskManager")
        assertEqual(APP_VERSION, "2.1.0")
        assertEqual(MAX_WORKERS, 8)
    })

    // 3. Built-in @derive
    test("showcase — Task toJson", () => {
        const t = new Task(id: 1, title: "Deploy", done: 0)
        assertEqual(t.toJson(), "{\"id\":1,\"title\":\"Deploy\",\"done\":0}")
    })
    test("showcase — Task equals", () => {
        const a = new Task(id: 1, title: "Deploy", done: 0)
        const b = new Task(id: 1, title: "Deploy", done: 0)
        const c = new Task(id: 2, title: "Test", done: 1)
        assertEqual(a.equals(b), 1)
        assertEqual(a.equals(c), 0)
    })
    test("showcase — Worker toString", () => {
        const w = new Worker(name: "Alice", taskCount: 5)
        assertEqual(w.toString(), "Worker(name=Alice, taskCount=5)")
    })

    // 4. User-defined @derive
    test("showcase — AppInfo schema via custom derive", () => {
        const info = new AppInfo(name: "Test", version: "1.0", workers: 4)
        assertEqual(info.schema(), "AppInfo(name: string, version: string, workers: int)")
    })

    // 5. Auto-registry
    test("showcase — auto-discovered JSON types", () => {
        const classes = getJsonCapableClasses()
        assertTrue(classes.indexOf("Task") >= 0)
        assertTrue(classes.indexOf("Worker") >= 0)
        assertTrue(getJsonCapableCount() >= 2)
    })

    // 6. Conditional compilation
    test("showcase — debug build mode", () => {
        assertEqual(getBuildMode(), "debug")
    })

    // 7. Combined build summary
    test("showcase — build summary", () => {
        assertEqual(buildSummary(), "TaskManager v2.1.0 (abc123def)")
    })
}
