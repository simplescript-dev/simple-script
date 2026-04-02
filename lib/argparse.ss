// SimpleScript ArgParse Library — Command-line argument parser
//
// Usage:
//   import { ArgParse, ArgParser, ArgResult } from "@/lib/argparse"
//
//   let parser = ArgParse.create("myapp", "My application")
//   parser.option("--output", "-o", "Output file", "out.txt")
//   parser.flag("--verbose", "-v", "Enable verbose output")
//   let result = parser.parse()
//   let output = result.getString("output")
//   let verbose = result.getBool("verbose")
//   let files = result.positionals()

// ── Internal storage ─────────────────────────────────────────

let apStore = ""
let apNextId = 1
let apReady = 0

function apInit() {
    if (apReady == 1) { return }
    apStore = new Map()
    apReady = 1
}

function apNewId(): int {
    apInit()
    const id = apNextId
    apNextId = apNextId + 1
    return id
}

// ── Internal helpers ─────────────────────────────────────────

function apStripDashes(name: string): string {
    if (name.length() >= 2 && name.substring(0, 2) == "--") {
        return name.substring(2, name.length() - 2)
    }
    if (name.length() >= 1 && name.substring(0, 1) == "-") {
        return name.substring(1, name.length() - 1)
    }
    return name
}

function apAddDef(id: int, long: string, short: string, desc: string, defaultVal: string, isFlag: int) {
    const countKey = `${id}:oc`
    let count = 0
    if (apStore.has(countKey) == 1) {
        count = parseInt(apStore.getString(countKey))
    }
    apStore.set(`${id}:o:${count}:long`, long)
    apStore.set(`${id}:o:${count}:short`, short)
    apStore.set(`${id}:o:${count}:desc`, desc)
    apStore.set(`${id}:o:${count}:default`, defaultVal)
    apStore.set(`${id}:o:${count}:flag`, `${isFlag}`)
    const key = apStripDashes(long)
    apStore.set(`${id}:o:${count}:key`, key)
    apStore.set(`${id}:m:${long}`, `${count}`)
    if (short != "") {
        apStore.set(`${id}:m:${short}`, `${count}`)
    }
    apStore.set(countKey, `${count + 1}`)
}

function apGetOptCount(id: int): int {
    const countKey = `${id}:oc`
    if (apStore.has(countKey) == 0) { return 0 }
    return parseInt(apStore.getString(countKey))
}

function apFindOpt(id: int, name: string): int {
    const mKey = `${id}:m:${name}`
    if (apStore.has(mKey) == 0) { return -1 }
    return parseInt(apStore.getString(mKey))
}

function apIsFlag(id: int, optIdx: int): int {
    return parseInt(apStore.getString(`${id}:o:${optIdx}:flag`))
}

function apGetKey(id: int, optIdx: int): string {
    return apStore.getString(`${id}:o:${optIdx}:key`)
}

function apSetResult(rid: int, key: string, value: string) {
    apStore.set(`${rid}:v:${key}`, value)
    apStore.set(`${rid}:h:${key}`, "1")
}

function apAddPositional(rid: int, value: string) {
    const pcKey = `${rid}:pc`
    let count = 0
    if (apStore.has(pcKey) == 1) {
        count = parseInt(apStore.getString(pcKey))
    }
    apStore.set(`${rid}:p:${count}`, value)
    apStore.set(pcKey, `${count + 1}`)
}

// ── Parse logic ──────────────────────────────────────────────

function apDoParse(parserId: int, argv: Array<string>, startIdx: int): int {
    const rid = apNewId()
    const ac = argv.length()

    // Set defaults
    const optCount = apGetOptCount(parserId)
    let oi = 0
    while (oi < optCount) {
        const key = apGetKey(parserId, oi)
        const isFlag = apIsFlag(parserId, oi)
        if (isFlag == 1) {
            apStore.set(`${rid}:v:${key}`, "0")
        } else {
            const defKey = `${parserId}:o:${oi}:default`
            if (apStore.has(defKey) == 1) {
                const def = apStore.getString(defKey)
                if (def != "") {
                    apStore.set(`${rid}:v:${key}`, def)
                }
            }
        }
        oi = oi + 1
    }

    apStore.set(`${rid}:pc`, "0")

    let i = startIdx
    let stopParsing = 0
    while (i < ac) {
        const a = argv[i]

        if (stopParsing == 1) {
            apAddPositional(rid, a)
            i = i + 1
            continue
        }

        if (a == "--") {
            stopParsing = 1
            i = i + 1
            continue
        }

        // Check for --option=value
        if (a.length() > 2 && a.substring(0, 2) == "--") {
            const eqPos = a.indexOf("=")
            if (eqPos > 0) {
                const optName = a.substring(0, eqPos)
                const optVal = a.substring(eqPos + 1, a.length() - eqPos - 1)
                const idx = apFindOpt(parserId, optName)
                if (idx >= 0) {
                    const key = apGetKey(parserId, idx)
                    apSetResult(rid, key, optVal)
                } else {
                    println(`Error: unknown option '${optName}'`)
                    exit(1)
                }
                i = i + 1
                continue
            }
        }

        // Check for -x or --xxx
        if (a.length() > 1 && a.charAt(0) == "-") {
            const idx = apFindOpt(parserId, a)
            if (idx >= 0) {
                const key = apGetKey(parserId, idx)
                if (apIsFlag(parserId, idx) == 1) {
                    apSetResult(rid, key, "1")
                } else {
                    if (i + 1 < ac) {
                        i = i + 1
                        apSetResult(rid, key, argv[i])
                    } else {
                        println(`Error: option '${a}' requires a value`)
                        exit(1)
                    }
                }
            } else {
                println(`Error: unknown option '${a}'`)
                exit(1)
            }
        } else {
            apAddPositional(rid, a)
        }

        i = i + 1
    }

    return rid
}

// ── Help text ────────────────────────────────────────────────

function apBuildHelp(id: int): string {
    const name = apStore.getString(`${id}:name`)
    const desc = apStore.getString(`${id}:desc`)
    let result = ""
    if (desc != "") {
        result = result + desc + "\n\n"
    }
    result = result + `Usage: ${name} [options] [arguments]\n\n`
    result = result + "Options:\n"

    const optCount = apGetOptCount(id)
    let i = 0
    while (i < optCount) {
        const long = apStore.getString(`${id}:o:${i}:long`)
        const short = apStore.getString(`${id}:o:${i}:short`)
        const optDesc = apStore.getString(`${id}:o:${i}:desc`)
        const def = apStore.getString(`${id}:o:${i}:default`)
        const isFlag = apIsFlag(id, i)

        let prefix = "  "
        if (short != "") {
            prefix = prefix + short + ", " + long
        } else {
            prefix = prefix + "    " + long
        }
        if (isFlag == 0) {
            prefix = prefix + " <value>"
        }

        let padded = prefix
        while (padded.length() < 30) {
            padded = padded + " "
        }
        padded = padded + optDesc

        if (def != "" && isFlag == 0) {
            padded = padded + ` (default: ${def})`
        }

        result = result + padded + "\n"
        i = i + 1
    }

    const verKey = `${id}:version`
    if (apStore.has(verKey) == 1) {
        result = result + `\nVersion: ${apStore.getString(verKey)}\n`
    }

    return result
}

// ── ArgResult class ──────────────────────────────────────────

class ArgResult {
    rid: int

    function getString(name: string): string {
        const vKey = `${this.rid}:v:${name}`
        if (apStore.has(vKey) == 0) { return "" }
        return apStore.getString(vKey)
    }

    function getInt(name: string): int {
        const vKey = `${this.rid}:v:${name}`
        if (apStore.has(vKey) == 0) { return 0 }
        return parseInt(apStore.getString(vKey))
    }

    function getBool(name: string): int {
        const vKey = `${this.rid}:v:${name}`
        if (apStore.has(vKey) == 0) { return 0 }
        const s = apStore.getString(vKey)
        if (s == "1" || s == "true") { return 1 }
        return 0
    }

    function has(name: string): int {
        const hKey = `${this.rid}:h:${name}`
        if (apStore.has(hKey) == 1) { return 1 }
        return 0
    }

    function positionals(): Array<string> {
        let result: Array<string> = []
        const pcKey = `${this.rid}:pc`
        if (apStore.has(pcKey) == 0) { return result }
        const count = parseInt(apStore.getString(pcKey))
        let i = 0
        while (i < count) {
            result = result.push(apStore.getString(`${this.rid}:p:${i}`))
            i = i + 1
        }
        return result
    }

    function positionalCount(): int {
        const pcKey = `${this.rid}:pc`
        if (apStore.has(pcKey) == 0) { return 0 }
        return parseInt(apStore.getString(pcKey))
    }
}

// ── ArgParser class ──────────────────────────────────────────

class ArgParser {
    id: int

    function option(long: string, short: string, desc: string, defaultVal: string) {
        apAddDef(this.id, long, short, desc, defaultVal, 0)
    }

    function flag(long: string, short: string, desc: string) {
        apAddDef(this.id, long, short, desc, "", 1)
    }

    function version(ver: string) {
        apInit()
        apStore.set(`${this.id}:version`, ver)
    }

    function parse(): ArgResult {
        let argv: Array<string> = []
        const ac = args()
        let i = 0
        while (i < ac) {
            argv = argv.push(arg(i))
            i = i + 1
        }
        const rid = apDoParse(this.id, argv, 1)
        return new ArgResult(rid)
    }

    function parseArray(argv: Array<string>): ArgResult {
        const rid = apDoParse(this.id, argv, 0)
        return new ArgResult(rid)
    }

    function help(): string {
        return apBuildHelp(this.id)
    }
}

// ── Factory ──────────────────────────────────────────────────

class ArgParse {}

function ArgParse_create(name: string, desc: string): ArgParser {
    const id = apNewId()
    apStore.set(`${id}:name`, name)
    apStore.set(`${id}:desc`, desc)
    return new ArgParser(id)
}
