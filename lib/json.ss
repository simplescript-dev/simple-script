// SimpleScript JSON Library — JavaScript-style API
//
// Usage:
//   const data = JSON.parse('{"name":"Alice","age":30}')
//   data.getString("name")   → "Alice"
//   data.getInt("age")       → 30
//
//   const obj = JSON.create().put("name", "Alice").put("age", 30)
//   JSON.stringify(obj)      → {"name":"Alice","age":30}

// ── Internal storage ─────────────────────────────────────────

let jnType = ""
let jnStr = ""
let jnInt = ""
let jnArr = ""
let jnNextId = 1
let jnReady = 0

function initJson() {
    if (jnReady == 1) { return }
    jnType = new Map()
    jnStr = new Map()
    jnInt = new Map()
    jnArr = new Map()
    jnReady = 1
}

function jnNew(nodeType: string): int {
    initJson()
    const id = jnNextId
    jnNextId = jnNextId + 1
    jnType.set(`${id}`, nodeType)
    return id
}

// ── JsonNode wrapper ─────────────────────────────────────────

class JsonNode(nodeId: int) {
    function type(): string {
        return jnType.getString(`${this.nodeId}`)
    }

    function getString(key: string): string {
        const childId = jnGetField(this.nodeId, key)
        if (childId <= 0) { return "" }
        return jnStr.getString(`${childId}`)
    }

    function getInt(key: string): int {
        const childId = jnGetField(this.nodeId, key)
        if (childId <= 0) { return 0 }
        return parseInt(jnInt.getString(`${childId}`))
    }

    function get(key: string): JsonNode {
        const childId = jnGetField(this.nodeId, key)
        return new JsonNode(childId)
    }

    function get(index: int): JsonNode {
        const arrStr = jnArr.getString(`${this.nodeId}`)
        if (arrStr == "") { return new JsonNode(0) }
        let remaining = arrStr
        let i = 0
        while (remaining != "") {
            let part = remaining
            const commaIdx = remaining.indexOf(",")
            if (commaIdx >= 0) {
                part = remaining.substring(0, commaIdx)
                remaining = remaining.substring(commaIdx + 1, remaining.length() - commaIdx - 1)
            } else {
                remaining = ""
            }
            if (i == index) { return new JsonNode(parseInt(part)) }
            i = i + 1
        }
        return new JsonNode(0)
    }

    function size(): int {
        const t = this.type()
        if (t == "array") {
            const arrStr = jnArr.getString(`${this.nodeId}`)
            if (arrStr == "") { return 0 }
            let count = 1
            let remaining = arrStr
            while (remaining != "") {
                const ci = remaining.indexOf(",")
                if (ci < 0) { break }
                count = count + 1
                remaining = remaining.substring(ci + 1, remaining.length() - ci - 1)
            }
            return count
        }
        return 0
    }

    function asString(): string {
        return jnStr.getString(`${this.nodeId}`)
    }

    function asInt(): int {
        return parseInt(jnInt.getString(`${this.nodeId}`))
    }

    function getDouble(key: string): double {
        const childId = jnGetField(this.nodeId, key)
        if (childId <= 0) { return 0.0 }
        return parseDouble(jnInt.getString(`${childId}`))
    }

    function getBool(key: string): int {
        return this.getInt(key)
    }

    function has(key: string): int {
        const childId = jnGetField(this.nodeId, key)
        if (childId > 0) { return 1 }
        return 0
    }

    function keys(): Array<string> {
        let result: Array<string> = []
        if (this.type() != "object") { return result }
        const fieldList = jnStr.getString(`${this.nodeId}`)
        if (fieldList == "") { return result }
        let remaining = fieldList
        while (remaining != "") {
            let entry = remaining
            const commaIdx = remaining.indexOf(",")
            if (commaIdx >= 0) {
                entry = remaining.substring(0, commaIdx)
                remaining = remaining.substring(commaIdx + 1, remaining.length() - commaIdx - 1)
            } else {
                remaining = ""
            }
            const colonIdx = entry.indexOf(":")
            if (colonIdx >= 0) {
                result = result.push(entry.substring(0, colonIdx))
            }
        }
        return result
    }

    function asDouble(): double {
        return parseDouble(jnInt.getString(`${this.nodeId}`))
    }

    function asBool(): int {
        return this.asInt()
    }

    // Builder methods (object)
    function put(key: string, value: string): JsonNode {
        const childId = jnNew("string")
        jnStr.set(`${childId}`, value)
        jnSetField(this.nodeId, key, childId)
        return this
    }

    function put(key: string, value: int): JsonNode {
        const childId = jnNew("number")
        jnInt.set(`${childId}`, `${value}`)
        jnSetField(this.nodeId, key, childId)
        return this
    }

    // Builder methods (array)
    function add(value: string): JsonNode {
        const childId = jnNew("string")
        jnStr.set(`${childId}`, value)
        jnAddElement(this.nodeId, childId)
        return this
    }

    function add(value: int): JsonNode {
        const childId = jnNew("number")
        jnInt.set(`${childId}`, `${value}`)
        jnAddElement(this.nodeId, childId)
        return this
    }

    function put(key: string, value: double): JsonNode {
        const childId = jnNew("number")
        jnInt.set(`${childId}`, `${value}`)
        jnSetField(this.nodeId, key, childId)
        return this
    }

    function putBool(key: string, value: int): JsonNode {
        const childId = jnNew("bool")
        jnInt.set(`${childId}`, `${value}`)
        jnSetField(this.nodeId, key, childId)
        return this
    }

    function putNull(key: string): JsonNode {
        const childId = jnNew("null")
        jnSetField(this.nodeId, key, childId)
        return this
    }

    function add(value: double): JsonNode {
        const childId = jnNew("number")
        jnInt.set(`${childId}`, `${value}`)
        jnAddElement(this.nodeId, childId)
        return this
    }

    function addBool(value: int): JsonNode {
        const childId = jnNew("bool")
        jnInt.set(`${childId}`, `${value}`)
        jnAddElement(this.nodeId, childId)
        return this
    }

    function addNull(): JsonNode {
        const childId = jnNew("null")
        jnAddElement(this.nodeId, childId)
        return this
    }
}

// ── JSON static methods ──────────────────────────────────────

class JSON()

function JSON_parse(source: string): JsonNode {
    initJson()
    const id = jpParse(source)
    return new JsonNode(id)
}

function JSON_stringify(node: JsonNode): string {
    return jnStringify(node.nodeId)
}

function JSON_create(): JsonNode {
    const id = jnNew("object")
    jnStr.set(`${id}`, "")
    return new JsonNode(id)
}

function JSON_create(key: string, value: string): JsonNode {
    const id = jnNew("object")
    jnStr.set(`${id}`, "")
    const childId = jnNew("string")
    jnStr.set(`${childId}`, value)
    jnSetField(id, key, childId)
    return new JsonNode(id)
}

function JSON_createArray(): JsonNode {
    const id = jnNew("array")
    return new JsonNode(id)
}

// ── Internal helpers ─────────────────────────────────────────

function jnGetField(objId: int, key: string): int {
    const fieldList = jnStr.getString(`${objId}`)
    if (fieldList == "") { return 0 }
    let remaining = fieldList
    while (remaining != "") {
        let entry = remaining
        const commaIdx = remaining.indexOf(",")
        if (commaIdx >= 0) {
            entry = remaining.substring(0, commaIdx)
            remaining = remaining.substring(commaIdx + 1, remaining.length() - commaIdx - 1)
        } else {
            remaining = ""
        }
        const colonIdx = entry.indexOf(":")
        if (colonIdx >= 0) {
            const fKey = entry.substring(0, colonIdx)
            const fVal = entry.substring(colonIdx + 1, entry.length() - colonIdx - 1)
            if (fKey == key) { return parseInt(fVal) }
        }
    }
    return 0
}

function jnSetField(objId: int, key: string, childId: int) {
    const existing = jnStr.getString(`${objId}`)
    if (existing == "") {
        jnStr.set(`${objId}`, `${key}:${childId}`)
    } else {
        jnStr.set(`${objId}`, `${existing},${key}:${childId}`)
    }
}

function jnAddElement(arrId: int, childId: int) {
    const existing = jnArr.getString(`${arrId}`)
    if (existing == "") {
        jnArr.set(`${arrId}`, `${childId}`)
    } else {
        jnArr.set(`${arrId}`, `${existing},${childId}`)
    }
}

function jnEscapeString(s: string): string {
    let result = ""
    let i = 0
    while (i < s.length()) {
        const ch = s.charAt(i)
        if (ch == "\\") { result = `${result}\\\\` }
        else if (ch == "\"") { result = `${result}\\"` }
        else if (ch == "\n") { result = `${result}\\n` }
        else if (ch == "\t") { result = `${result}\\t` }
        else if (ch == "\r") { result = `${result}\\r` }
        else { result = `${result}${ch}` }
        i = i + 1
    }
    return result
}

function jnStringify(id: int): string {
    if (id <= 0) { return "null" }
    const t = jnType.getString(`${id}`)
    if (t == "string") {
        return `"${jnEscapeString(jnStr.getString(`${id}`))}"`
    }
    if (t == "number") {
        return jnInt.getString(`${id}`)
    }
    if (t == "bool") {
        return parseInt(jnInt.getString(`${id}`)) == 1 ? "true" : "false"
    }
    if (t == "null") { return "null" }
    if (t == "object") {
        let result = "{"
        const fieldList = jnStr.getString(`${id}`)
        if (fieldList != "") {
            let first = 1
            let remaining = fieldList
            while (remaining != "") {
                let entry = remaining
                const commaIdx = remaining.indexOf(",")
                if (commaIdx >= 0) {
                    entry = remaining.substring(0, commaIdx)
                    remaining = remaining.substring(commaIdx + 1, remaining.length() - commaIdx - 1)
                } else {
                    remaining = ""
                }
                const colonIdx = entry.indexOf(":")
                if (colonIdx >= 0) {
                    const fKey = entry.substring(0, colonIdx)
                    const fVal = entry.substring(colonIdx + 1, entry.length() - colonIdx - 1)
                    if (first == 1) { first = 0 } else { result = `${result},` }
                    result = `${result}"${fKey}":${jnStringify(parseInt(fVal))}`
                }
            }
        }
        return `${result}}`
    }
    if (t == "array") {
        let result = "["
        const arrStr = jnArr.getString(`${id}`)
        if (arrStr != "") {
            let first = 1
            let remaining = arrStr
            while (remaining != "") {
                let part = remaining
                const commaIdx = remaining.indexOf(",")
                if (commaIdx >= 0) {
                    part = remaining.substring(0, commaIdx)
                    remaining = remaining.substring(commaIdx + 1, remaining.length() - commaIdx - 1)
                } else {
                    remaining = ""
                }
                if (first == 1) { first = 0 } else { result = `${result},` }
                result = `${result}${jnStringify(parseInt(part))}`
            }
        }
        return `${result}]`
    }
    return "null"
}

// ── Parser ───────────────────────────────────────────────────

let jpSrc = ""
let jpPos = 0

function jpParse(source: string): int {
    jpSrc = source
    jpPos = 0
    jpSkipWS()
    return jpParseValue()
}

function jpSkipWS() {
    while (jpPos < jpSrc.length()) {
        const ch = jpSrc.charAt(jpPos)
        if (ch != " " && ch != "\t" && ch != "\n" && ch != "\r") { break }
        jpPos = jpPos + 1
    }
}

function jpParseValue(): int {
    if (jpPos >= jpSrc.length()) { return 0 }
    const ch = jpSrc.charAt(jpPos)
    if (ch == "{") { return jpParseObject() }
    if (ch == "[") { return jpParseArray() }
    if (ch == "\"") { return jpParseString() }
    if (ch == "t") { jpPos = jpPos + 4; const id = jnNew("bool"); jnInt.set(`${id}`, "1"); return id }
    if (ch == "f") { jpPos = jpPos + 5; const id = jnNew("bool"); jnInt.set(`${id}`, "0"); return id }
    if (ch == "n") { jpPos = jpPos + 4; return jnNew("null") }
    return jpParseNumber()
}

function jpParseObject(): int {
    jpPos = jpPos + 1
    jpSkipWS()
    const id = jnNew("object")
    jnStr.set(`${id}`, "")
    if (jpPos < jpSrc.length() && jpSrc.charAt(jpPos) == "}") {
        jpPos = jpPos + 1
        return id
    }
    while (jpPos < jpSrc.length()) {
        jpSkipWS()
        const keyId = jpParseString()
        const key = jnStr.getString(`${keyId}`)
        jpSkipWS()
        jpPos = jpPos + 1
        jpSkipWS()
        const valId = jpParseValue()
        jnSetField(id, key, valId)
        jpSkipWS()
        if (jpPos >= jpSrc.length()) { break }
        if (jpSrc.charAt(jpPos) == "}") { jpPos = jpPos + 1; break }
        jpPos = jpPos + 1
    }
    return id
}

function jpParseArray(): int {
    jpPos = jpPos + 1
    jpSkipWS()
    const id = jnNew("array")
    if (jpPos < jpSrc.length() && jpSrc.charAt(jpPos) == "]") {
        jpPos = jpPos + 1
        return id
    }
    while (jpPos < jpSrc.length()) {
        jpSkipWS()
        const elemId = jpParseValue()
        jnAddElement(id, elemId)
        jpSkipWS()
        if (jpPos >= jpSrc.length()) { break }
        if (jpSrc.charAt(jpPos) == "]") { jpPos = jpPos + 1; break }
        jpPos = jpPos + 1
    }
    return id
}

function jpParseString(): int {
    jpPos = jpPos + 1
    let result = ""
    while (jpPos < jpSrc.length()) {
        const ch = jpSrc.charAt(jpPos)
        if (ch == "\"") { jpPos = jpPos + 1; break }
        if (ch == "\\") {
            jpPos = jpPos + 1
            const esc = jpSrc.charAt(jpPos)
            if (esc == "n") { result = result + "\n" }
            else if (esc == "t") { result = result + "\t" }
            else if (esc == "\\") { result = result + "\\" }
            else if (esc == "\"") { result = result + "\"" }
            else if (esc == "r") { result = result + "\r" }
            else if (esc == "/") { result = result + "/" }
            else { result = result + esc }
        } else {
            result = result + ch
        }
        jpPos = jpPos + 1
    }
    const id = jnNew("string")
    jnStr.set(`${id}`, result)
    return id
}

function jpParseNumber(): int {
    const start = jpPos
    if (jpPos < jpSrc.length() && jpSrc.charAt(jpPos) == "-") { jpPos = jpPos + 1 }
    while (jpPos < jpSrc.length()) {
        const ch = jpSrc.charAt(jpPos)
        if (ch != "0" && ch != "1" && ch != "2" && ch != "3" && ch != "4" && ch != "5" && ch != "6" && ch != "7" && ch != "8" && ch != "9" && ch != ".") { break }
        jpPos = jpPos + 1
    }
    if (jpPos < jpSrc.length()) {
        const ech = jpSrc.charAt(jpPos)
        if (ech == "e" || ech == "E") {
            jpPos = jpPos + 1
            if (jpPos < jpSrc.length()) {
                const sign = jpSrc.charAt(jpPos)
                if (sign == "+" || sign == "-") { jpPos = jpPos + 1 }
            }
            while (jpPos < jpSrc.length()) {
                const d = jpSrc.charAt(jpPos)
                if (d != "0" && d != "1" && d != "2" && d != "3" && d != "4" && d != "5" && d != "6" && d != "7" && d != "8" && d != "9") { break }
                jpPos = jpPos + 1
            }
        }
    }
    const numStr = jpSrc.substring(start, jpPos - start)
    const id = jnNew("number")
    jnInt.set(`${id}`, numStr)
    return id
}
