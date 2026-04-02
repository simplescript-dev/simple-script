// SimpleScript Regex Library — Basic regular expression matching
//
// Usage:
//   import { Regex } from "@/lib/regex"
//
//   Regex.test("\\d+", "abc 123")            // 1
//   Regex.match("\\d+", "abc 123")           // "123"
//   Regex.replace("\\d+", "abc 123", "NUM")  // "abc NUM"
//   Regex.replaceAll("\\d+", "a1 b2", "X")   // "aX bX"
//   Regex.split("[,;]", "a,b;c")             // ["a", "b", "c"]
//
// Supported patterns:
//   .            any character (except newline)
//   *            zero or more (greedy)
//   +            one or more (greedy)
//   ?            zero or one (greedy)
//   ^            start of string anchor
//   $            end of string anchor
//   [abc]        character class
//   [a-z]        character range
//   [^abc]       negated character class
//   \d \w \s     digit, word char, whitespace
//   \D \W \S     negated shorthand classes
//   (...)        grouping
//   |            alternation
//   \\           escape special character

class Regex {}

// ── Global match state ───────────────────────────────────────

let rxStart = 0
let rxEnd = 0

// ── Character classification ─────────────────────────────────

function rxIsDigit(ch: string): int {
    if (ch >= "0" && ch <= "9") { return 1 }
    return 0
}

function rxIsAlpha(ch: string): int {
    if (ch >= "a" && ch <= "z") { return 1 }
    if (ch >= "A" && ch <= "Z") { return 1 }
    return 0
}

function rxIsWord(ch: string): int {
    if (rxIsAlpha(ch) == 1) { return 1 }
    if (rxIsDigit(ch) == 1) { return 1 }
    if (ch == "_") { return 1 }
    return 0
}

function rxIsSpace(ch: string): int {
    if (ch == " ") { return 1 }
    const code = ch.charCodeAt(0)
    if (code == 9 || code == 10 || code == 13) { return 1 }
    return 0
}

// ── Pattern navigation ───────────────────────────────────────

// Find matching ] for character class. start = position after [
function rxFindClassEnd(pat: string, start: int, pEnd: int): int {
    let i = start
    if (i < pEnd && pat.charAt(i) == "^") { i = i + 1 }
    if (i < pEnd && pat.charAt(i) == "]") { i = i + 1 }
    while (i < pEnd) {
        const ch = pat.charAt(i)
        if (ch == "\\") { i = i + 2; continue }
        if (ch == "]") { return i }
        i = i + 1
    }
    return pEnd
}

// Find matching ) for group. start = position after (
function rxFindGroupEnd(pat: string, start: int, pEnd: int): int {
    let depth = 1
    let i = start
    while (i < pEnd) {
        const ch = pat.charAt(i)
        if (ch == "\\") { i = i + 2; continue }
        if (ch == "[") {
            i = rxFindClassEnd(pat, i + 1, pEnd) + 1
            continue
        }
        if (ch == "(") { depth = depth + 1 }
        if (ch == ")") {
            depth = depth - 1
            if (depth == 0) { return i }
        }
        i = i + 1
    }
    return pEnd
}

// Return position after current atom in pattern
function rxAtomEnd(pat: string, pi: int, pEnd: int): int {
    if (pi >= pEnd) { return pi }
    const ch = pat.charAt(pi)
    if (ch == "\\") { return pi + 2 }
    if (ch == "[") { return rxFindClassEnd(pat, pi + 1, pEnd) + 1 }
    if (ch == "(") { return rxFindGroupEnd(pat, pi + 1, pEnd) + 1 }
    return pi + 1
}

// Find first top-level | in pat[start:pEnd)
function rxFindAlt(pat: string, start: int, pEnd: int): int {
    let i = start
    while (i < pEnd) {
        const ch = pat.charAt(i)
        if (ch == "\\") { i = i + 2; continue }
        if (ch == "[") {
            i = rxFindClassEnd(pat, i + 1, pEnd) + 1
            continue
        }
        if (ch == "(") {
            i = rxFindGroupEnd(pat, i + 1, pEnd) + 1
            continue
        }
        if (ch == "|") { return i }
        i = i + 1
    }
    return -1
}

// ── Character matching ───────────────────────────────────────

// Match char against character class contents pat[start:classEnd)
function rxMatchClassInner(pat: string, start: int, classEnd: int, ch: string): int {
    let i = start
    while (i < classEnd) {
        const c = pat.charAt(i)
        if (c == "\\") {
            if (i + 1 < classEnd) {
                const esc = pat.charAt(i + 1)
                if (esc == "d" && rxIsDigit(ch) == 1) { return 1 }
                if (esc == "D" && rxIsDigit(ch) == 0) { return 1 }
                if (esc == "w" && rxIsWord(ch) == 1) { return 1 }
                if (esc == "W" && rxIsWord(ch) == 0) { return 1 }
                if (esc == "s" && rxIsSpace(ch) == 1) { return 1 }
                if (esc == "S" && rxIsSpace(ch) == 0) { return 1 }
                if (ch == esc) { return 1 }
            }
            i = i + 2
            continue
        }
        if (i + 2 < classEnd && pat.charAt(i + 1) == "-") {
            const hi = pat.charAt(i + 2)
            if (ch >= c && ch <= hi) { return 1 }
            i = i + 3
            continue
        }
        if (ch == c) { return 1 }
        i = i + 1
    }
    return 0
}

// Match char against [...] class at pat[pi]. atomEnd = position after ]
function rxMatchClass(pat: string, pi: int, atomEnd: int, ch: string): int {
    let start = pi + 1
    let negated = 0
    if (pat.charAt(start) == "^") {
        negated = 1
        start = start + 1
    }
    const classEnd = atomEnd - 1
    const matched = rxMatchClassInner(pat, start, classEnd, ch)
    if (negated == 1) {
        if (matched == 1) { return 0 }
        return 1
    }
    return matched
}

// Match char against escape sequence at pat[pi] (\ followed by escape char)
function rxNot(v: int): int {
    if (v == 0) { return 1 }
    return 0
}

function rxMatchEscape(pat: string, pi: int, ch: string): int {
    const esc = pat.charAt(pi + 1)
    if (esc == "d") { return rxIsDigit(ch) }
    if (esc == "D") { return rxNot(rxIsDigit(ch)) }
    if (esc == "w") { return rxIsWord(ch) }
    if (esc == "W") { return rxNot(rxIsWord(ch)) }
    if (esc == "s") { return rxIsSpace(ch) }
    if (esc == "S") { return rxNot(rxIsSpace(ch)) }
    if (ch == esc) { return 1 }
    return 0
}

// ── Core matching engine ─────────────────────────────────────

// Match one instance of atom pat[pi:atomEnd) at text[ti]
// Returns end position in text, or -1
function rxMatchOne(pat: string, pi: int, atomEnd: int, text: string, ti: int, tLen: int): int {
    const ch = pat.charAt(pi)

    // Group (...)
    if (ch == "(") {
        return rxMatchAt(pat, pi + 1, atomEnd - 1, text, ti, tLen)
    }

    // All other atoms need one char
    if (ti >= tLen) { return -1 }
    const tc = text.charAt(ti)

    if (ch == ".") {
        if (tc.charCodeAt(0) == 10) { return -1 }
        return ti + 1
    }
    if (ch == "[") {
        if (rxMatchClass(pat, pi, atomEnd, tc) == 1) { return ti + 1 }
        return -1
    }
    if (ch == "\\") {
        if (rxMatchEscape(pat, pi, tc) == 1) { return ti + 1 }
        return -1
    }
    if (tc == ch) { return ti + 1 }
    return -1
}

// Match pat[pi:pEnd) at text[ti]. Returns end position or -1.
function rxMatchAt(pat: string, pi: int, pEnd: int, text: string, ti: int, tLen: int): int {
    if (pi >= pEnd) { return ti }

    // Alternation (lowest precedence)
    const altIdx = rxFindAlt(pat, pi, pEnd)
    if (altIdx != -1) {
        const left = rxMatchAt(pat, pi, altIdx, text, ti, tLen)
        if (left != -1) { return left }
        return rxMatchAt(pat, altIdx + 1, pEnd, text, ti, tLen)
    }

    const ch = pat.charAt(pi)

    // Anchors
    if (ch == "^") {
        if (ti != 0) { return -1 }
        return rxMatchAt(pat, pi + 1, pEnd, text, ti, tLen)
    }
    if (ch == "$") {
        if (ti != tLen) { return -1 }
        return rxMatchAt(pat, pi + 1, pEnd, text, ti, tLen)
    }

    // Current atom
    const atomEnd = rxAtomEnd(pat, pi, pEnd)

    // Quantifier
    let quant = ""
    let restStart = atomEnd
    if (atomEnd < pEnd) {
        const qc = pat.charAt(atomEnd)
        if (qc == "*" || qc == "+" || qc == "?") {
            quant = qc
            restStart = atomEnd + 1
        }
    }

    // No quantifier: match exactly one
    if (quant == "") {
        const endPos = rxMatchOne(pat, pi, atomEnd, text, ti, tLen)
        if (endPos == -1) { return -1 }
        return rxMatchAt(pat, restStart, pEnd, text, endPos, tLen)
    }

    // Collect greedy match positions
    let positions: Array<int> = []
    if (quant == "*" || quant == "?") {
        positions = positions.push(ti)
    }

    let pos = ti
    if (quant == "?") {
        // At most one match
        const endPos = rxMatchOne(pat, pi, atomEnd, text, pos, tLen)
        if (endPos != -1 && endPos != pos) {
            positions = positions.push(endPos)
        }
    } else {
        // * or +: as many as possible
        let done = 0
        while (done == 0) {
            const endPos = rxMatchOne(pat, pi, atomEnd, text, pos, tLen)
            if (endPos == -1 || endPos == pos) {
                done = 1
            } else {
                positions = positions.push(endPos)
                pos = endPos
            }
        }
    }

    // Backtrack: try most matches first (greedy)
    let k = positions.length() - 1
    while (k >= 0) {
        const result = rxMatchAt(pat, restStart, pEnd, text, positions[k], tLen)
        if (result != -1) { return result }
        k = k - 1
    }
    return -1
}

// Find first match starting from startPos. Sets rxStart/rxEnd.
function rxFindMatch(pat: string, text: string, startPos: int): int {
    const pLen = pat.length()
    const tLen = text.length()
    let i = startPos
    while (i <= tLen) {
        const end = rxMatchAt(pat, 0, pLen, text, i, tLen)
        if (end != -1) {
            rxStart = i
            rxEnd = end
            return 1
        }
        i = i + 1
    }
    return 0
}

// ── Regex static methods ─────────────────────────────────────

// Test if pattern matches anywhere in text
function Regex_test(pattern: string, text: string): int {
    return rxFindMatch(pattern, text, 0)
}

// Return first matched substring, or "" if no match
function Regex_match(pattern: string, text: string): string {
    if (rxFindMatch(pattern, text, 0) == 0) { return "" }
    return text.substring(rxStart, rxEnd - rxStart)
}

// Return all non-overlapping matched substrings
function Regex_matchAll(pattern: string, text: string): Array<string> {
    let result: Array<string> = []
    let pos = 0
    const tLen = text.length()
    while (pos <= tLen) {
        if (rxFindMatch(pattern, text, pos) == 0) { break }
        result = result.push(text.substring(rxStart, rxEnd - rxStart))
        if (rxEnd == pos) {
            pos = pos + 1
        } else {
            pos = rxEnd
        }
    }
    return result
}

// Return start index of first match, or -1
function Regex_matchIndex(pattern: string, text: string): int {
    if (rxFindMatch(pattern, text, 0) == 0) { return -1 }
    return rxStart
}

// Replace first match with replacement string
function Regex_replace(pattern: string, text: string, repl: string): string {
    if (rxFindMatch(pattern, text, 0) == 0) { return text }
    const before = text.substring(0, rxStart)
    const after = text.substring(rxEnd, text.length() - rxEnd)
    return `${before}${repl}${after}`
}

// Replace all matches with replacement string
function Regex_replaceAll(pattern: string, text: string, repl: string): string {
    let parts: Array<string> = []
    let pos = 0
    const tLen = text.length()
    while (pos <= tLen) {
        if (rxFindMatch(pattern, text, pos) == 0) {
            parts = parts.push(text.substring(pos, tLen - pos))
            break
        }
        parts = parts.push(text.substring(pos, rxStart - pos))
        parts = parts.push(repl)
        if (rxEnd == pos) {
            if (pos < tLen) {
                parts = parts.push(text.charAt(pos))
            }
            pos = pos + 1
        } else {
            pos = rxEnd
        }
    }
    return parts.join("")
}

// Split text by pattern matches
function Regex_split(pattern: string, text: string): Array<string> {
    let result: Array<string> = []
    let pos = 0
    const tLen = text.length()
    while (pos <= tLen) {
        if (rxFindMatch(pattern, text, pos) == 0) {
            result = result.push(text.substring(pos, tLen - pos))
            break
        }
        if (rxEnd == rxStart && rxStart == pos) {
            if (pos >= tLen) { break }
            result = result.push(text.charAt(pos))
            pos = pos + 1
            continue
        }
        result = result.push(text.substring(pos, rxStart - pos))
        pos = rxEnd
    }
    return result
}

// Escape special regex characters in a string
function rxIsSpecial(ch: string): int {
    if (ch == "\\" || ch == "." || ch == "*" || ch == "+" || ch == "?") { return 1 }
    if (ch == "^" || ch == "$" || ch == "|") { return 1 }
    if (ch == "(" || ch == ")" || ch == "[" || ch == "]") { return 1 }
    return 0
}

function Regex_escape(text: string): string {
    let parts: Array<string> = []
    let i = 0
    const len = text.length()
    while (i < len) {
        const ch = text.charAt(i)
        if (rxIsSpecial(ch) == 1) {
            parts = parts.push("\\" + ch)
        } else {
            parts = parts.push(ch)
        }
        i = i + 1
    }
    return parts.join("")
}
