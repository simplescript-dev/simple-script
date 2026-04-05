// Runtime prelude — pure SS implementations of string/array methods
// _ss_ prefix avoids conflict with C runtime declarations

// ── Built-in classes ─────────────────────────────────────────

class Error {
    message: string
}

// ── Higher-order array methods ────────────────────────────────

function _ss_map(arr: List<int>, callback: fn): List<int> {
    const len = arr.length()
    let result = []
    for (let i = 0; i < len; i++) {
        result = result.push(callback(arr[i]))
    }
    return result
}

function _ss_filter(arr: List<int>, predicate: fn): List<int> {
    const len = arr.length()
    let result = []
    for (let i = 0; i < len; i++) {
        if (predicate(arr[i]) == 1) {
            result = result.push(arr[i])
        }
    }
    return result
}

function _ss_reduce(arr: List<int>, callback: fn, initial: int): int {
    let acc = initial
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        acc = callback(acc, arr[i])
    }
    return acc
}

function _ss_forEach(arr: List<int>, callback: fn) {
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        callback(arr[i])
    }
}

function _ss_find(arr: List<int>, predicate: fn): int {
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        if (predicate(arr[i]) == 1) {
            return arr[i]
        }
    }
    return 0
}

function _ss_findIndex(arr: List<int>, predicate: fn): int {
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        if (predicate(arr[i]) == 1) {
            return i
        }
    }
    return -1
}

function _ss_some(arr: List<int>, predicate: fn): int {
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        if (predicate(arr[i]) == 1) {
            return 1
        }
    }
    return 0
}

function _ss_every(arr: List<int>, predicate: fn): int {
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        if (predicate(arr[i]) == 0) {
            return 0
        }
    }
    return 1
}

// ── String methods ────────────────────────────────────────────

function _ss_trim(s: string): string {
    let start = 0
    while (start < s.length()) {
        const ch = s.charAt(start)
        if (ch != " " && ch != "\t" && ch != "\n" && ch != "\r") { break }
        start = start + 1
    }
    let end = s.length()
    while (end > start) {
        const ch = s.charAt(end - 1)
        if (ch != " " && ch != "\t" && ch != "\n" && ch != "\r") { break }
        end = end - 1
    }
    return s.substring(start, end - start)
}

function _ss_replace(s: string, old: string, newStr: string): string {
    let result = ""
    let pos = 0
    const oldLen = old.length()
    const sLen = s.length()
    if (oldLen == 0) { return s }
    while (pos <= sLen - oldLen) {
        const remaining = s.substring(pos, sLen - pos)
        const idx = remaining.indexOf(old)
        if (idx < 0) { break }
        result = result + s.substring(pos, idx) + newStr
        pos = pos + idx + oldLen
    }
    result = result + s.substring(pos, sLen - pos)
    return result
}

function _ss_toUpperCase(s: string): string {
    let result = ""
    let i = 0
    while (i < s.length()) {
        const code = charCodeAt(s, i)
        if (code >= 97 && code <= 122) {
            result = result + fromCharCode(code - 32)
        } else {
            result = result + s.charAt(i)
        }
        i = i + 1
    }
    return result
}

function _ss_toLowerCase(s: string): string {
    let result = ""
    let i = 0
    while (i < s.length()) {
        const code = charCodeAt(s, i)
        if (code >= 65 && code <= 90) {
            result = result + fromCharCode(code + 32)
        } else {
            result = result + s.charAt(i)
        }
        i = i + 1
    }
    return result
}

function _ss_repeat(s: string, n: int): string {
    let result = ""
    for (let i = 0; i < n; i++) {
        result = result + s
    }
    return result
}

function _ss_padStart(s: string, width: int, pad: string): string {
    if (s.length() >= width) { return s }
    let result = s
    while (result.length() < width) {
        result = pad + result
    }
    if (result.length() > width) {
        result = result.substring(result.length() - width, width)
    }
    return result
}

function _ss_padEnd(s: string, width: int, pad: string): string {
    if (s.length() >= width) { return s }
    let result = s
    while (result.length() < width) {
        result = result + pad
    }
    if (result.length() > width) {
        result = result.substring(0, width)
    }
    return result
}

function _ss_join(arr: List<string>, delim: string): string {
    const len = arr.length()
    if (len == 0) { return "" }
    let result = ""
    let first = 1
    for (let i = 0; i < len; i++) {
        if (first == 1) {
            first = 0
        } else {
            result = result + delim
        }
        result = result + arr[i]
    }
    return result
}
