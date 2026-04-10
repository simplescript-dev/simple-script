// interp_builtins.ss — Built-in type methods for the AST interpreter (D087 Phase 1e)
//
// Handles methods on built-in types (string, Array, Map) and provides
// Map value storage. Separated from interp.ss per D087 design doc to
// keep file sizes manageable.
//
// All functions here reference interp.ss helpers (interpNewVal, interpAsStr,
// etc.) as forward declarations — safe because registerAllDecls resolves them.

// ── Map Value Storage ────────────────────────────────────────

let interpMapEntries = new Map()
let interpMapKeyIds = new Map()

function interpNewMap(): int {
    return interpNewVal("map", "")
}

function interpMapSet(mapId: int, keyStr: string, valId: int) {
    const entryKey = `${mapId}:${keyStr}`
    if (interpMapEntries.has(entryKey) != 1) {
        const keyValId = interpNewString(keyStr)
        const listKey = `${mapId}`
        if (interpMapKeyIds.has(listKey) == 1) {
            interpMapKeyIds.set(listKey, `${interpMapKeyIds.getString(listKey)},${keyValId}`)
        } else {
            interpMapKeyIds.set(listKey, `${keyValId}`)
        }
    }
    interpMapEntries.set(entryKey, `${valId}`)
}

function interpMapGet(mapId: int, keyStr: string): int {
    const entryKey = `${mapId}:${keyStr}`
    if (interpMapEntries.has(entryKey) == 1) {
        return parseInt(interpMapEntries.getString(entryKey))
    }
    return interpNewNull()
}

function interpMapHas(mapId: int, keyStr: string): int {
    return interpMapEntries.has(`${mapId}:${keyStr}`)
}

function interpMapDelete(mapId: int, keyStr: string) {
    const entryKey = `${mapId}:${keyStr}`
    if (interpMapEntries.has(entryKey) != 1) { return }
    interpMapEntries.delete(entryKey)
    const listKey = `${mapId}`
    if (interpMapKeyIds.has(listKey) != 1) { return }
    const keyIds = interpMapKeyIds.getString(listKey)
    if (keyIds == "") { return }
    let newIds = ""
    const parts = keyIds.split(",")
    let i = 0
    while (i < parts.length()) {
        if (interpAsStr(parseInt(parts[i])) != keyStr) {
            if (newIds != "") { newIds = `${newIds},` }
            newIds = `${newIds}${parts[i]}`
        }
        i = i + 1
    }
    interpMapKeyIds.set(listKey, newIds)
}

function interpMapGetKeys(mapId: int): int {
    const listKey = `${mapId}`
    if (interpMapKeyIds.has(listKey) != 1) { return interpNewArray("") }
    return interpNewArray(interpMapKeyIds.getString(listKey))
}

function interpMapGetSize(mapId: int): int {
    const listKey = `${mapId}`
    if (interpMapKeyIds.has(listKey) != 1) { return 0 }
    const keyIds = interpMapKeyIds.getString(listKey)
    if (keyIds == "") { return 0 }
    return keyIds.split(",").length()
}

// ── Value Equality (for indexOf) ─────────────────────────────

function interpValEquals(a: int, b: int): int {
    const ta = interpType(a)
    const tb = interpType(b)
    if (ta != tb) { return 0 }
    if (ta == "null") { return 1 }
    if (ta == "object" || ta == "array" || ta == "map" || ta == "fn") {
        return a == b ? 1 : 0
    }
    return interpAsStr(a) == interpAsStr(b) ? 1 : 0
}

// ── String Methods ───────────────────────────────────────────

function interpStringMethod(objVal: int, method: string, args: Array<string>): int {
    const s = interpAsStr(objVal)

    if (method == "length") { return interpNewInt(s.length()) }
    if (method == "trim") { return interpNewString(s.trim()) }
    if (method == "toUpperCase") { return interpNewString(s.toUpperCase()) }
    if (method == "toLowerCase") { return interpNewString(s.toLowerCase()) }

    if (method == "split") {
        const sep = args.length() > 0 ? interpAsStr(parseInt(args[0])) : ""
        const parts = s.split(sep)
        let items = ""
        let i = 0
        while (i < parts.length()) {
            const vid = interpNewString(parts[i])
            if (i > 0) { items = `${items},` }
            items = `${items}${vid}`
            i = i + 1
        }
        return interpNewArray(items)
    }
    if (method == "indexOf") {
        const sub = args.length() > 0 ? interpAsStr(parseInt(args[0])) : ""
        return interpNewInt(s.indexOf(sub))
    }
    if (method == "substring") {
        const start = args.length() > 0 ? interpAsInt(parseInt(args[0])) : 0
        const len = args.length() > 1 ? interpAsInt(parseInt(args[1])) : s.length()
        return interpNewString(s.substring(start, len))
    }
    if (method == "replace") {
        const old = args.length() > 0 ? interpAsStr(parseInt(args[0])) : ""
        const rep = args.length() > 1 ? interpAsStr(parseInt(args[1])) : ""
        return interpNewString(s.replace(old, rep))
    }
    if (method == "startsWith") {
        const prefix = args.length() > 0 ? interpAsStr(parseInt(args[0])) : ""
        return interpNewInt(s.startsWith(prefix))
    }
    if (method == "endsWith") {
        const suffix = args.length() > 0 ? interpAsStr(parseInt(args[0])) : ""
        return interpNewInt(s.endsWith(suffix))
    }
    if (method == "charAt") {
        const idx = args.length() > 0 ? interpAsInt(parseInt(args[0])) : 0
        return interpNewString(s.charAt(idx))
    }
    if (method == "includes") {
        const sub = args.length() > 0 ? interpAsStr(parseInt(args[0])) : ""
        return interpNewInt(s.indexOf(sub) >= 0 ? 1 : 0)
    }

    println(`[interp] unsupported string method: ${method}`)
    return interpNewNull()
}

// ── Array Methods ────────────────────────────────────────────

function interpArrayMethod(objVal: int, method: string, args: Array<string>): int {
    const items = interpAsStr(objVal)

    if (method == "length") {
        if (items == "") { return interpNewInt(0) }
        return interpNewInt(items.split(",").length())
    }
    if (method == "push") {
        return interpArrayPush(objVal, parseInt(args[0]))
    }
    if (method == "join") {
        const sep = args.length() > 0 ? interpAsStr(parseInt(args[0])) : ","
        if (items == "") { return interpNewString("") }
        const parts = items.split(",")
        let result = ""
        let i = 0
        while (i < parts.length()) {
            if (i > 0) { result = `${result}${sep}` }
            result = `${result}${interpToStr(parseInt(parts[i]))}`
            i = i + 1
        }
        return interpNewString(result)
    }
    if (method == "indexOf") {
        if (items == "") { return interpNewInt(-1) }
        const target = parseInt(args[0])
        const parts = items.split(",")
        let i = 0
        while (i < parts.length()) {
            if (interpValEquals(parseInt(parts[i]), target) == 1) {
                return interpNewInt(i)
            }
            i = i + 1
        }
        return interpNewInt(-1)
    }
    if (method == "slice") {
        if (items == "") { return interpNewArray("") }
        const parts = items.split(",")
        let start = args.length() > 0 ? interpAsInt(parseInt(args[0])) : 0
        let end = args.length() > 1 ? interpAsInt(parseInt(args[1])) : parts.length()
        if (start < 0) { start = parts.length() + start }
        if (end < 0) { end = parts.length() + end }
        if (start < 0) { start = 0 }
        if (end > parts.length()) { end = parts.length() }
        let newItems = ""
        let i = start
        while (i < end) {
            if (i > start) { newItems = `${newItems},` }
            newItems = `${newItems}${parts[i]}`
            i = i + 1
        }
        return interpNewArray(newItems)
    }

    // Higher-order methods (use interpCallValue from interp.ss)
    if (method == "map") {
        const fnVal = parseInt(args[0])
        if (items == "") { return interpNewArray("") }
        const parts = items.split(",")
        let newItems = ""
        let i = 0
        while (i < parts.length()) {
            let callArgs: Array<string> = []
            callArgs = callArgs.push(parts[i])
            const result = interpCallValue(fnVal, callArgs)
            if (i > 0) { newItems = `${newItems},` }
            newItems = `${newItems}${result}`
            i = i + 1
        }
        return interpNewArray(newItems)
    }
    if (method == "filter") {
        const fnVal = parseInt(args[0])
        if (items == "") { return interpNewArray("") }
        const parts = items.split(",")
        let newItems = ""
        let i = 0
        while (i < parts.length()) {
            let callArgs: Array<string> = []
            callArgs = callArgs.push(parts[i])
            const result = interpCallValue(fnVal, callArgs)
            if (interpTruthy(result) == 1) {
                if (newItems != "") { newItems = `${newItems},` }
                newItems = `${newItems}${parts[i]}`
            }
            i = i + 1
        }
        return interpNewArray(newItems)
    }
    if (method == "forEach") {
        const fnVal = parseInt(args[0])
        if (items != "") {
            const parts = items.split(",")
            let i = 0
            while (i < parts.length()) {
                let callArgs: Array<string> = []
                callArgs = callArgs.push(parts[i])
                interpCallValue(fnVal, callArgs)
                i = i + 1
            }
        }
        return interpNewNull()
    }
    if (method == "reduce") {
        const fnVal = parseInt(args[0])
        let acc = args.length() > 1 ? parseInt(args[1]) : interpNewNull()
        if (items != "") {
            const parts = items.split(",")
            let i = 0
            while (i < parts.length()) {
                let callArgs: Array<string> = []
                callArgs = callArgs.push(`${acc}`)
                callArgs = callArgs.push(parts[i])
                acc = interpCallValue(fnVal, callArgs)
                i = i + 1
            }
        }
        return acc
    }

    println(`[interp] unsupported array method: ${method}`)
    return interpNewNull()
}

// ── Map Methods ──────────────────────────────────────────────

function interpMapMethod(objVal: int, method: string, args: Array<string>): int {
    if (method == "set") {
        const key = interpAsStr(parseInt(args[0]))
        interpMapSet(objVal, key, parseInt(args[1]))
        return interpNewNull()
    }
    if (method == "get" || method == "getString") {
        const key = interpAsStr(parseInt(args[0]))
        return interpMapGet(objVal, key)
    }
    if (method == "has") {
        const key = interpAsStr(parseInt(args[0]))
        return interpNewInt(interpMapHas(objVal, key))
    }
    if (method == "delete") {
        const key = interpAsStr(parseInt(args[0]))
        interpMapDelete(objVal, key)
        return interpNewNull()
    }
    if (method == "keys") { return interpMapGetKeys(objVal) }
    if (method == "size") { return interpNewInt(interpMapGetSize(objVal)) }

    println(`[interp] unsupported map method: ${method}`)
    return interpNewNull()
}

// ── Main Dispatcher ──────────────────────────────────────────

function interpBuiltinMethod(objType: string, objVal: int, method: string, args: Array<string>): int {
    if (objType == "string") { return interpStringMethod(objVal, method, args) }
    if (objType == "array") { return interpArrayMethod(objVal, method, args) }
    if (objType == "map") { return interpMapMethod(objVal, method, args) }
    println(`[interp] no built-in method '${method}' on ${objType}`)
    return interpNewNull()
}

// ── Reset ────────────────────────────────────────────────────

function interpResetBuiltins() {
    interpMapEntries = new Map()
    interpMapKeyIds = new Map()
}
