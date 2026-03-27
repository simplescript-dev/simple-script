// JSON library for SimpleScript
// Design: Jackson-style JsonNode tree with Rust-like value enum
//
// Usage:
//   const root = jsonParse('{"name": "Alice", "age": 30}')
//   root.getString("name")   → "Alice"
//   root.getInt("age")       → 30
//   root.get("name").asString() → "Alice"
//
// Internal: each node is an int ID, properties in global Maps.
// Types: "object", "array", "string", "number", "bool", "null"

let jnType = ""        // nodeId → type tag
let jnStr = ""         // nodeId → string value (also stores object field list)
let jnInt = ""         // nodeId → int value (as string)
let jnArr = ""         // nodeId → comma-separated child IDs
let jnNextId = 1
let jnReady = 0

function initJson() {
    if (jnReady == 1) { return }
    jnType = Map()
    jnStr = Map()
    jnInt = Map()
    jnArr = Map()
    jnReady = 1
}

// ── Node creation ─────────────────────────────────────────────

function jnNew(nodeType: string): int {
    initJson()
    const id = jnNextId
    jnNextId = jnNextId + 1
    jnType.set(id + "", nodeType)
    return id
}

function jnNewString(val: string): int {
    const id = jnNew("string")
    jnStr.set(id + "", val)
    return id
}

function jnNewInt(val: int): int {
    const id = jnNew("number")
    jnInt.set(id + "", val + "")
    return id
}

function jnNewBool(val: int): int {
    const id = jnNew("bool")
    jnInt.set(id + "", val + "")
    return id
}

function jnNewNull(): int {
    return jnNew("null")
}

function jnNewObject(): int {
    return jnNew("object")
}

function jnNewArray(): int {
    const id = jnNew("array")
    jnArr.set(id + "", "")
    return id
}

// ── Node modification ─────────────────────────────────────────

function jnSetField(objId: int, key: string, childId: int) {
    const existing = jnStr.getString(objId + "")
    if (existing == "") {
        jnStr.set(objId + "", `${key}:${childId}`)
    } else {
        jnStr.set(objId + "", `${existing},${key}:${childId}`)
    }
}

function jnAddElement(arrId: int, childId: int) {
    const existing = jnArr.getString(arrId + "")
    if (existing == "") {
        jnArr.set(arrId + "", childId + "")
    } else {
        jnArr.set(arrId + "", `${existing},${childId}`)
    }
}

// ── Node access ───────────────────────────────────────────────

function jnGetType(id: int): string {
    initJson()
    if (id <= 0) { return "null" }
    const key = id + ""
    if (jnType.has(key) == 1) { return jnType.getString(key) }
    return "null"
}

function jnAsString(id: int): string {
    if (jnGetType(id) == "string") { return jnStr.getString(id + "") }
    return ""
}

function jnAsInt(id: int): int {
    if (jnGetType(id) == "number") { return parseInt(jnInt.getString(id + "")) }
    return 0
}

function jnAsBool(id: int): int {
    if (jnGetType(id) == "bool") { return parseInt(jnInt.getString(id + "")) }
    return 0
}

function jnIsNull(id: int): int {
    return jnGetType(id) == "null"
}

// Get child by key from object node
function jnGet(objId: int, key: string): int {
    if (jnGetType(objId) != "object") { return 0 }
    const fields = jnStr.getString(objId + "")
    if (fields == "") { return 0 }
    // Parse "key1:id1,key2:id2,..." — find matching key
    const pairs = fields.split(",")
    for (pair in pairs) {
        const colonPos = pair.indexOf(":")
        if (colonPos >= 0) {
            const k = pair.substring(0, colonPos)
            if (k == key) {
                return parseInt(pair.substring(colonPos + 1, pair.length() - colonPos - 1))
            }
        }
    }
    return 0
}

// Convenience: get string field directly
function jnGetString(objId: int, key: string): string {
    return jnAsString(jnGet(objId, key))
}

// Convenience: get int field directly
function jnGetInt(objId: int, key: string): int {
    return jnAsInt(jnGet(objId, key))
}

// Get array length
function jnArrayLen(arrId: int): int {
    if (jnGetType(arrId) != "array") { return 0 }
    const items = jnArr.getString(arrId + "")
    if (items == "") { return 0 }
    let count = 1
    let i = 0
    while (i < items.length()) {
        if (items.charAt(i) == ",") { count = count + 1 }
        i = i + 1
    }
    return count
}

// Get array element by index
function jnArrayGet(arrId: int, index: int): int {
    if (jnGetType(arrId) != "array") { return 0 }
    const items = jnArr.getString(arrId + "")
    if (items == "") { return 0 }
    const parts = items.split(",")
    let i = 0
    for (p in parts) {
        if (i == index) { return parseInt(p) }
        i = i + 1
    }
    return 0
}

// ── Parser ────────────────────────────────────────────────────

let jpSrc = "."
let jpPos = 0

function jsonParse(source: string): int {
    initJson()
    jpSrc = source
    jpPos = 0
    jpSkipWS()
    return jpParseValue()
}

function jpSkipWS() {
    while (jpPos < jpSrc.length()) {
        const ch = jpSrc.charAt(jpPos)
        if (ch == " " || ch == "\n" || ch == "\t" || ch == "\r") {
            jpPos = jpPos + 1
        } else {
            break
        }
    }
}

function jpPeek(): string {
    if (jpPos >= jpSrc.length()) { return "" }
    return jpSrc.charAt(jpPos)
}

function jpParseValue(): int {
    jpSkipWS()
    const ch = jpPeek()
    if (ch == "\"") { return jpParseString() }
    if (ch == "{") { return jpParseObject() }
    if (ch == "[") { return jpParseArray() }
    if (ch == "t") { jpPos = jpPos + 4; return jnNewBool(1) }
    if (ch == "f") { jpPos = jpPos + 5; return jnNewBool(0) }
    if (ch == "n") { jpPos = jpPos + 4; return jnNewNull() }
    return jpParseNumber()
}

function jpParseString(): int {
    jpPos = jpPos + 1
    let result = ""
    while (jpPos < jpSrc.length()) {
        const ch = jpSrc.charAt(jpPos)
        jpPos = jpPos + 1
        if (ch == "\"") { return jnNewString(result) }
        if (ch == "\\") {
            const esc = jpSrc.charAt(jpPos)
            jpPos = jpPos + 1
            if (esc == "\"") { result = result + "\"" }
            else if (esc == "\\") { result = result + "\\" }
            else if (esc == "n") { result = result + "\n" }
            else if (esc == "t") { result = result + "\t" }
            else if (esc == "r") { result = result + "\r" }
            else if (esc == "/") { result = result + "/" }
            else { result = result + esc }
        } else {
            result = result + ch
        }
    }
    return jnNewString(result)
}

function jpParseNumber(): int {
    let start = jpPos
    if (jpPeek() == "-") { jpPos = jpPos + 1 }
    while (jpPos < jpSrc.length()) {
        const ch = jpSrc.charAt(jpPos)
        if ("0123456789".contains(ch) == 1) {
            jpPos = jpPos + 1
        } else {
            break
        }
    }
    // Skip decimal and exponent for now (treat as int)
    if (jpPeek() == ".") {
        jpPos = jpPos + 1
        while (jpPos < jpSrc.length() && "0123456789".contains(jpSrc.charAt(jpPos)) == 1) {
            jpPos = jpPos + 1
        }
    }
    const numStr = jpSrc.substring(start, jpPos - start)
    return jnNewInt(parseInt(numStr))
}

function jpParseObject(): int {
    jpPos = jpPos + 1
    jpSkipWS()
    const objId = jnNewObject()
    while (jpPeek() != "}" && jpPeek() != "") {
        jpSkipWS()
        // Parse key — reuse jpParseString but extract the string value
        const keyNode = jpParseString()
        const key = jnAsString(keyNode)
        jpSkipWS()
        if (jpPeek() == ":") { jpPos = jpPos + 1 }
        // Parse value
        const valId = jpParseValue()
        jnSetField(objId, key, valId)
        jpSkipWS()
        if (jpPeek() == ",") { jpPos = jpPos + 1 }
    }
    if (jpPeek() == "}") { jpPos = jpPos + 1 }
    return objId
}

function jpParseArray(): int {
    jpPos = jpPos + 1
    jpSkipWS()
    const arrId = jnNewArray()
    while (jpPeek() != "]" && jpPeek() != "") {
        const valId = jpParseValue()
        jnAddElement(arrId, valId)
        jpSkipWS()
        if (jpPeek() == ",") { jpPos = jpPos + 1 }
    }
    if (jpPeek() == "]") { jpPos = jpPos + 1 }
    return arrId
}

// ── Builder (JSON stringify) ──────────────────────────────────

function jsonStringify(id: int): string {
    const t = jnGetType(id)
    if (t == "null") { return "null" }
    if (t == "bool") {
        if (jnAsBool(id) == 1) { return "true" }
        return "false"
    }
    if (t == "number") { return jnAsInt(id) + "" }
    if (t == "string") { return `"${jsonEscape(jnAsString(id))}"` }
    if (t == "array") {
        let result = "["
        const items = jnArr.getString(id + "")
        if (items != "") {
            const parts = items.split(",")
            let first = 1
            for (p in parts) {
                if (first == 0) { result = result + "," }
                first = 0
                result = result + jsonStringify(parseInt(p))
            }
        }
        return result + "]"
    }
    if (t == "object") {
        let result = "{"
        const fields = jnStr.getString(id + "")
        if (fields != "") {
            const pairs = fields.split(",")
            let first = 1
            for (pair in pairs) {
                const colonPos = pair.indexOf(":")
                if (colonPos >= 0) {
                    const k = pair.substring(0, colonPos)
                    const vId = parseInt(pair.substring(colonPos + 1, pair.length() - colonPos - 1))
                    if (first == 0) { result = result + "," }
                    first = 0
                    result = result + `"${jsonEscape(k)}":${jsonStringify(vId)}`
                }
            }
        }
        return result + "}"
    }
    return "null"
}

function jsonEscape(s: string): string {
    let result = ""
    let i = 0
    while (i < s.length()) {
        const ch = s.charAt(i)
        if (ch == "\"") { result = result + "\\\"" }
        else if (ch == "\\") { result = result + "\\\\" }
        else if (ch == "\n") { result = result + "\\n" }
        else if (ch == "\t") { result = result + "\\t" }
        else if (ch == "\r") { result = result + "\\r" }
        else { result = result + ch }
        i = i + 1
    }
    return result
}
