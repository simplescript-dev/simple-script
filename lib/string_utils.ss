// SimpleScript String Utilities — Higher-level string functions
//
// Usage:
//   import { StringUtil } from "@/lib/string_utils"
//   StringUtil.capitalize("hello")             → "Hello"
//   StringUtil.reverse("abc")                  → "cba"
//   StringUtil.padCenter("hi", 10, "-")        → "----hi----"
//   StringUtil.truncate("hello world", 8, "...") → "hello..."
//   StringUtil.count("ababa", "ab")            → 2
//   StringUtil.isBlank("  \t\n")               → 1

class StringUtil()

// ── Trimming ─────────────────────────────────────────────────

function StringUtil_trimStart(s: string): string {
    let start = 0
    while (start < s.length()) {
        const ch = s.charAt(start)
        if (ch != " " && ch != "\t" && ch != "\n" && ch != "\r") { break }
        start = start + 1
    }
    return s.substring(start, s.length() - start)
}

function StringUtil_trimEnd(s: string): string {
    let end = s.length()
    while (end > 0) {
        const ch = s.charAt(end - 1)
        if (ch != " " && ch != "\t" && ch != "\n" && ch != "\r") { break }
        end = end - 1
    }
    return s.substring(0, end)
}

// ── Casing ───────────────────────────────────────────────────

function StringUtil_capitalize(s: string): string {
    if (s.length() == 0) { return s }
    const code = s.charCodeAt(0)
    if (code >= 97 && code <= 122) {
        return fromCharCode(code - 32) + s.substring(1, s.length() - 1)
    }
    return s
}

// ── Checks ───────────────────────────────────────────────────

function StringUtil_isBlank(s: string): int {
    if (s.length() == 0) { return 1 }
    for (let i = 0; i < s.length(); i = i + 1) {
        const ch = s.charAt(i)
        if (ch != " " && ch != "\t" && ch != "\n" && ch != "\r") { return 0 }
    }
    return 1
}

function StringUtil_isDigit(s: string): int {
    if (s.length() == 0) { return 0 }
    for (let i = 0; i < s.length(); i = i + 1) {
        const code = s.charCodeAt(i)
        if (code < 48 || code > 57) { return 0 }
    }
    return 1
}

function StringUtil_isAlpha(s: string): int {
    if (s.length() == 0) { return 0 }
    for (let i = 0; i < s.length(); i = i + 1) {
        const code = s.charCodeAt(i)
        const isUpper = code >= 65 && code <= 90
        const isLower = code >= 97 && code <= 122
        if (isUpper == 0 && isLower == 0) { return 0 }
    }
    return 1
}

function StringUtil_isAlphaNumeric(s: string): int {
    if (s.length() == 0) { return 0 }
    for (let i = 0; i < s.length(); i = i + 1) {
        const code = s.charCodeAt(i)
        const isDigit = code >= 48 && code <= 57
        const isUpper = code >= 65 && code <= 90
        const isLower = code >= 97 && code <= 122
        if (isDigit == 0 && isUpper == 0 && isLower == 0) { return 0 }
    }
    return 1
}

// ── Transformation ───────────────────────────────────────────

function StringUtil_reverse(s: string): string {
    let result = ""
    let i = s.length() - 1
    while (i >= 0) {
        result = result + s.charAt(i)
        i = i - 1
    }
    return result
}

function StringUtil_padCenter(s: string, width: int, pad: string): string {
    if (s.length() >= width) { return s }
    const total = width - s.length()
    const left = total / 2
    const right = total - left
    let result = ""
    for (let i = 0; i < left; i = i + 1) {
        result = result + pad
    }
    result = result + s
    for (let i = 0; i < right; i = i + 1) {
        result = result + pad
    }
    if (result.length() > width) {
        result = result.substring(0, width)
    }
    return result
}

function StringUtil_truncate(s: string, maxLen: int, suffix: string): string {
    if (s.length() <= maxLen) { return s }
    const cut = maxLen - suffix.length()
    if (cut <= 0) { return suffix.substring(0, maxLen) }
    return s.substring(0, cut) + suffix
}

// ── Search & count ───────────────────────────────────────────

function StringUtil_count(s: string, sub: string): int {
    if (sub.length() == 0) { return 0 }
    let result = 0
    let pos = 0
    const sLen = s.length()
    const subLen = sub.length()
    while (pos <= sLen - subLen) {
        const remaining = s.substring(pos, sLen - pos)
        const idx = remaining.indexOf(sub)
        if (idx < 0) { break }
        result = result + 1
        pos = pos + idx + subLen
    }
    return result
}

// ── Prefix / suffix ─────────────────────────────────────────

function StringUtil_removePrefix(s: string, prefix: string): string {
    if (s.startsWith(prefix) == 1) {
        return s.substring(prefix.length(), s.length() - prefix.length())
    }
    return s
}

function StringUtil_removeSuffix(s: string, suffix: string): string {
    if (s.endsWith(suffix) == 1) {
        return s.substring(0, s.length() - suffix.length())
    }
    return s
}

// ── Comparison ───────────────────────────────────────────────

function StringUtil_equalsIgnoreCase(a: string, b: string): int {
    if (a.length() != b.length()) { return 0 }
    for (let i = 0; i < a.length(); i = i + 1) {
        let codeA = a.charCodeAt(i)
        let codeB = b.charCodeAt(i)
        if (codeA >= 65 && codeA <= 90) { codeA = codeA + 32 }
        if (codeB >= 65 && codeB <= 90) { codeB = codeB + 32 }
        if (codeA != codeB) { return 0 }
    }
    return 1
}

// ── Splitting ────────────────────────────────────────────────

function StringUtil_lines(s: string): Array<string> {
    let result: Array<string> = []
    let start = 0
    for (let i = 0; i < s.length(); i = i + 1) {
        if (s.charAt(i) == "\n") {
            let end = i
            if (end > start && s.charAt(end - 1) == "\r") {
                end = end - 1
            }
            result = result.push(s.substring(start, end - start))
            start = i + 1
        }
    }
    if (start <= s.length()) {
        let end = s.length()
        if (end > start && s.charAt(end - 1) == "\r") {
            end = end - 1
        }
        result = result.push(s.substring(start, end - start))
    }
    return result
}

function StringUtil_words(s: string): Array<string> {
    let result: Array<string> = []
    let start = -1
    for (let i = 0; i < s.length(); i = i + 1) {
        const ch = s.charAt(i)
        const isWs = ch == " " || ch == "\t" || ch == "\n" || ch == "\r"
        if (isWs == 0) {
            if (start < 0) { start = i }
        } else {
            if (start >= 0) {
                result = result.push(s.substring(start, i - start))
                start = -1
            }
        }
    }
    if (start >= 0) {
        result = result.push(s.substring(start, s.length() - start))
    }
    return result
}
