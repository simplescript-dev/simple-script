// SimpleScript Path Library — Node.js-style path manipulation
//
// Usage:
//   import { Path } from "@/lib/path"
//   Path.join("/usr", "local", "bin")  → "/usr/local/bin"
//   Path.basename("/usr/local/bin")    → "bin"
//   Path.dirname("/usr/local/bin")     → "/usr/local"
//   Path.extname("file.txt")           → ".txt"
//   Path.isAbsolute("/usr")            → 1
//   Path.normalize("/usr/../local/./bin") → "/local/bin"

class Path {}

// ── join ─────────────────────────────────────────────────────

function Path_join(a: string, b: string): string {
    if (a == "") { return b }
    if (b == "") { return a }
    const aEnd = a.charAt(a.length() - 1)
    const bStart = b.charAt(0)
    if (aEnd == "/" && bStart == "/") {
        return a + b.substring(1, b.length() - 1)
    }
    if (aEnd != "/" && bStart != "/") {
        return `${a}/${b}`
    }
    return a + b
}

function Path_join(a: string, b: string, c: string): string {
    return Path_join(Path_join(a, b), c)
}

function Path_join(a: string, b: string, c: string, d: string): string {
    return Path_join(Path_join(Path_join(a, b), c), d)
}

// ── basename ─────────────────────────────────────────────────

function Path_basename(path: string): string {
    if (path == "") { return "" }
    // Remove trailing slash
    let p = path
    if (p.length() > 1 && p.charAt(p.length() - 1) == "/") {
        p = p.substring(0, p.length() - 1)
    }
    // Find last slash
    let lastSlash = -1
    for (let i = 0; i < p.length(); i = i + 1) {
        if (p.charAt(i) == "/") { lastSlash = i }
    }
    if (lastSlash < 0) { return p }
    return p.substring(lastSlash + 1, p.length() - lastSlash - 1)
}

// ── dirname ──────────────────────────────────────────────────

function Path_dirname(path: string): string {
    if (path == "") { return "." }
    // Remove trailing slash
    let p = path
    if (p.length() > 1 && p.charAt(p.length() - 1) == "/") {
        p = p.substring(0, p.length() - 1)
    }
    // Find last slash
    let lastSlash = -1
    for (let i = 0; i < p.length(); i = i + 1) {
        if (p.charAt(i) == "/") { lastSlash = i }
    }
    if (lastSlash < 0) { return "." }
    if (lastSlash == 0) { return "/" }
    return p.substring(0, lastSlash)
}

// ── extname ──────────────────────────────────────────────────

function Path_extname(path: string): string {
    const base = Path_basename(path)
    if (base == "") { return "" }
    // Find last dot (not the first character)
    let lastDot = -1
    for (let i = 1; i < base.length(); i = i + 1) {
        if (base.charAt(i) == ".") { lastDot = i }
    }
    if (lastDot < 0) { return "" }
    return base.substring(lastDot, base.length() - lastDot)
}

// ── isAbsolute ───────────────────────────────────────────────

function Path_isAbsolute(path: string): int {
    if (path.length() == 0) { return 0 }
    if (path.charAt(0) == "/") { return 1 }
    return 0
}

// ── normalize ────────────────────────────────────────────────

function Path_normalize(path: string): string {
    if (path == "") { return "." }
    const isAbs = Path_isAbsolute(path)
    // Split into segments
    let segments: Array<string> = []
    let start = 0
    for (let i = 0; i <= path.length(); i = i + 1) {
        if (i == path.length() || path.charAt(i) == "/") {
            if (i > start) {
                const seg = path.substring(start, i - start)
                segments = segments.push(seg)
            }
            start = i + 1
        }
    }
    // Resolve . and ..
    let result: Array<string> = []
    for (let i = 0; i < segments.length(); i = i + 1) {
        const seg = segments[i]
        if (seg == ".") {
            // skip
        } else if (seg == "..") {
            if (result.length() > 0 && result[result.length() - 1] != "..") {
                result = result.slice(0, result.length() - 1)
            } else if (isAbs == 0) {
                result = result.push("..")
            }
        } else {
            result = result.push(seg)
        }
    }
    // Reconstruct
    let out = ""
    if (isAbs == 1) { out = "/" }
    for (let i = 0; i < result.length(); i = i + 1) {
        if (i > 0) { out = `${out}/` }
        out = out + result[i]
    }
    if (out == "") { return "." }
    return out
}

// ── resolve ──────────────────────────────────────────────────

function Path_resolve(base: string, relative: string): string {
    if (Path_isAbsolute(relative) == 1) {
        return Path_normalize(relative)
    }
    return Path_normalize(Path_join(base, relative))
}
