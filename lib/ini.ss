// SimpleScript INI Library — INI config file parser and stringifier
//
// Usage:
//   import { Ini, IniData } from "@/lib/ini"
//
//   const data = Ini.parse("[db]\nhost = localhost\nport = 3306")
//   data.get("db", "host")          // "localhost"
//   data.sections()                 // ["db"]
//   data.keys("db")                 // ["host", "port"]
//   Ini.stringify(data)             // "[db]\nhost = localhost\nport = 3306\n"
//
//   const cfg = Ini.create()
//   cfg.set("server", "port", "8080")

// ── Internal storage ─────────────────────────────────────────

let iniStore = ""
let iniMeta = ""
let iniNextId = 1
let iniReady = 0

function iniInit() {
    if (iniReady == 1) { return }
    iniStore = new Map()
    iniMeta = new Map()
    iniReady = 1
}

function iniNewId(): int {
    iniInit()
    const id = iniNextId
    iniNextId = iniNextId + 1
    iniMeta.set(`${id}:sc`, "0")
    return id
}

// ── Internal helpers ─────────────────────────────────────────

function iniEnsureSection(id: int, section: string) {
    const sKey = `${id}:sh:${section}`
    if (iniMeta.has(sKey) == 1) { return }
    iniMeta.set(sKey, "1")
    const sc = parseInt(iniMeta.getString(`${id}:sc`))
    iniMeta.set(`${id}:s:${sc}`, section)
    iniMeta.set(`${id}:sc`, `${sc + 1}`)
    iniMeta.set(`${id}:kc:${section}`, "0")
}

function iniSetValue(id: int, section: string, key: string, value: string) {
    iniEnsureSection(id, section)
    const kKey = `${id}:kh:${section}:${key}`
    if (iniMeta.has(kKey) == 0) {
        // New key — add to index
        iniMeta.set(kKey, "1")
        const kc = parseInt(iniMeta.getString(`${id}:kc:${section}`))
        iniMeta.set(`${id}:k:${section}:${kc}`, key)
        iniMeta.set(`${id}:kc:${section}`, `${kc + 1}`)
    } else {
        // Existing key — re-enable (might have been removed)
        iniMeta.set(kKey, "1")
    }
    iniStore.set(`${id}:v:${section}:${key}`, value)
}

function iniGetValue(id: int, section: string, key: string): string {
    if (iniHasKey(id, section, key) == 0) { return "" }
    const vKey = `${id}:v:${section}:${key}`
    if (iniStore.has(vKey) == 0) { return "" }
    return iniStore.getString(vKey)
}

function iniHasSec(id: int, section: string): int {
    if (iniMeta.has(`${id}:sh:${section}`) == 1) { return 1 }
    return 0
}

function iniHasKey(id: int, section: string, key: string): int {
    const kKey = `${id}:kh:${section}:${key}`
    if (iniMeta.has(kKey) == 0) { return 0 }
    if (iniMeta.getString(kKey) == "1") { return 1 }
    return 0
}

function iniSectionCount(id: int): int {
    return parseInt(iniMeta.getString(`${id}:sc`))
}

function iniSectionAt(id: int, i: int): string {
    return iniMeta.getString(`${id}:s:${i}`)
}

function iniKeyCount(id: int, section: string): int {
    const kcKey = `${id}:kc:${section}`
    if (iniMeta.has(kcKey) == 0) { return 0 }
    return parseInt(iniMeta.getString(kcKey))
}

function iniKeyAt(id: int, section: string, i: int): string {
    return iniMeta.getString(`${id}:k:${section}:${i}`)
}

function iniRemoveKey(id: int, section: string, key: string) {
    iniMeta.set(`${id}:kh:${section}:${key}`, "0")
}

// ── IniData class ────────────────────────────────────────────

class IniData(tableId: int) {
    function get(section: string, key: string): string {
        return iniGetValue(this.tableId, section, key)
    }

    function set(section: string, key: string, value: string) {
        iniSetValue(this.tableId, section, key, value)
    }

    function hasSection(section: string): int {
        return iniHasSec(this.tableId, section)
    }

    function hasKey(section: string, key: string): int {
        return iniHasKey(this.tableId, section, key)
    }

    function sections(): Array<string> {
        let result: Array<string> = []
        const sc = iniSectionCount(this.tableId)
        let i = 0
        while (i < sc) {
            result = result.push(iniSectionAt(this.tableId, i))
            i = i + 1
        }
        return result
    }

    function keys(section: string): Array<string> {
        let result: Array<string> = []
        const kc = iniKeyCount(this.tableId, section)
        let i = 0
        while (i < kc) {
            const k = iniKeyAt(this.tableId, section, i)
            if (iniHasKey(this.tableId, section, k) == 1) {
                result = result.push(k)
            }
            i = i + 1
        }
        return result
    }

    function remove(section: string, key: string) {
        iniRemoveKey(this.tableId, section, key)
    }
}

// ── Ini class (static methods) ───────────────────────────────

class Ini()

function Ini_parse(text: string): IniData {
    const id = iniNewId()
    const lines = text.split("\n")
    const lineCount = lines.length()
    let currentSection = ""
    let i = 0
    while (i < lineCount) {
        let line = lines[i]
        // Strip trailing \r
        const lineLen = line.length()
        if (lineLen > 0 && line.charAt(lineLen - 1) == "\r") {
            line = line.substring(0, lineLen - 1)
        }
        line = line.trim()
        const len = line.length()

        if (len > 0) {
            const firstChar = line.charAt(0)
            if (firstChar == ";" || firstChar == "#") {
                // comment — skip
            } else if (firstChar == "[") {
                // section header [name]
                const closeBracket = line.indexOf("]")
                if (closeBracket > 1) {
                    currentSection = line.substring(1, closeBracket - 1)
                    iniEnsureSection(id, currentSection)
                }
            } else {
                // key = value
                const eqPos = line.indexOf("=")
                if (eqPos > 0) {
                    const rawKey = line.substring(0, eqPos)
                    const rawVal = line.substring(eqPos + 1, len - eqPos - 1)
                    iniSetValue(id, currentSection, rawKey.trim(), rawVal.trim())
                }
            }
        }

        i = i + 1
    }
    return new IniData(id)
}

function Ini_stringify(data: IniData): string {
    const id = data.tableId
    let result = ""
    const sc = iniSectionCount(id)
    let si = 0
    let first = 1
    while (si < sc) {
        const section = iniSectionAt(id, si)
        const kc = iniKeyCount(id, section)

        // Check if section has any active keys
        let hasKeys = 0
        let ki = 0
        while (ki < kc) {
            const k = iniKeyAt(id, section, ki)
            if (iniHasKey(id, section, k) == 1) {
                hasKeys = 1
                break
            }
            ki = ki + 1
        }

        if (hasKeys == 1) {
            if (first == 0) {
                result = result + "\n"
            }
            first = 0

            // Section header (skip for global section "")
            if (section.length() > 0) {
                result = result + `[${section}]\n`
            }

            // Key-value pairs
            ki = 0
            while (ki < kc) {
                const k = iniKeyAt(id, section, ki)
                if (iniHasKey(id, section, k) == 1) {
                    const v = iniGetValue(id, section, k)
                    result = result + `${k} = ${v}\n`
                }
                ki = ki + 1
            }
        }

        si = si + 1
    }
    return result
}

function Ini_create(): IniData {
    const id = iniNewId()
    return new IniData(id)
}
