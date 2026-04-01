// SimpleScript URL Library — URL parsing, formatting, and query string handling
//
// Usage:
//   import { URL, UrlParts } from "@/lib/url"
//
//   const u = URL.parse("https://user:pass@example.com:8080/path?q=1#frag")
//   u.protocol()     // "https"
//   u.hostname()     // "example.com"
//   u.port()         // "8080"
//   u.pathname()     // "/path"
//   u.search()       // "q=1"
//   u.hash()         // "frag"
//   u.host()         // "example.com:8080"
//   u.origin()       // "https://example.com:8080"
//   u.href()         // full URL string
//
//   // Query string parsing
//   const params = URL.parseQuery("a=1&b=hello")
//   params.getString("a")    // "1"
//
//   // Query string encoding (parallel arrays)
//   let keys: Array<string> = []
//   let vals: Array<string> = []
//   keys = keys.push("a"); vals = vals.push("1")
//   URL.encodeQuery(keys, vals)  // "a=1"
//
//   // Percent encoding
//   URL.encodeComponent("hello world")  // "hello%20world"
//   URL.decodeComponent("hello%20world") // "hello world"
//
//   // Resolve relative URLs
//   URL.resolve("https://example.com/a/b", "../c") // "https://example.com/a/../c"

// ── Internal storage ─────────────────────────────────────────

let urlData = ""
let urlNextId = 1
let urlReady = 0

function urlInit() {
    if (urlReady == 1) { return }
    urlData = new Map()
    urlReady = 1
}

function urlNew(): int {
    urlInit()
    const id = urlNextId
    urlNextId = urlNextId + 1
    return id
}

function urlSet(id: int, field: string, value: string) {
    urlData.set(`${id}.${field}`, value)
}

function urlGet(id: int, field: string): string {
    return urlData.getString(`${id}.${field}`)
}

// Substring from offset to end of string
function urlSliceFrom(s: string, start: int): string {
    return s.substring(start, s.length() - start)
}

// ── UrlParts class ───────────────────────────────────────────

class UrlParts(urlId: int) {
    function protocol(): string {
        return urlGet(this.urlId, "protocol")
    }

    function username(): string {
        return urlGet(this.urlId, "username")
    }

    function password(): string {
        return urlGet(this.urlId, "password")
    }

    function hostname(): string {
        return urlGet(this.urlId, "hostname")
    }

    function port(): string {
        return urlGet(this.urlId, "port")
    }

    function pathname(): string {
        return urlGet(this.urlId, "pathname")
    }

    function search(): string {
        return urlGet(this.urlId, "search")
    }

    function hash(): string {
        return urlGet(this.urlId, "hash")
    }

    function host(): string {
        const h = this.hostname()
        const p = this.port()
        if (p == "") { return h }
        return `${h}:${p}`
    }

    function origin(): string {
        const proto = this.protocol()
        const h = this.host()
        if (proto == "") { return h }
        return `${proto}://${h}`
    }

    function href(): string {
        return urlBuildHref(this.urlId)
    }
}

// ── URL class (static methods) ───────────────────────────────

class URL()

// ── URL.parse — parse URL string into UrlParts ──────────────

function URL_parse(input: string): UrlParts {
    const id = urlNew()
    let rest = input

    // 1. Extract fragment (#...)
    const hashIdx = rest.indexOf("#")
    if (hashIdx >= 0) {
        urlSet(id, "hash", urlSliceFrom(rest, hashIdx + 1))
        rest = rest.substring(0, hashIdx)
    }

    // 2. Extract query (?...)
    const qIdx = rest.indexOf("?")
    if (qIdx >= 0) {
        urlSet(id, "search", urlSliceFrom(rest, qIdx + 1))
        rest = rest.substring(0, qIdx)
    }

    // 3. Extract scheme (before ://)
    const schemeEnd = rest.indexOf("://")
    let hasAuthority = 0
    if (schemeEnd >= 0 && urlIsValidScheme(rest.substring(0, schemeEnd)) == 1) {
        urlSet(id, "protocol", rest.substring(0, schemeEnd).toLowerCase())
        rest = urlSliceFrom(rest, schemeEnd + 3)
        hasAuthority = 1
    }

    // 4. Separate authority from path
    if (hasAuthority == 1) {
        const pathStart = urlFindPathStart(rest)
        if (pathStart >= 0) {
            urlParseAuthority(id, rest.substring(0, pathStart))
            urlSet(id, "pathname", urlSliceFrom(rest, pathStart))
        } else {
            urlParseAuthority(id, rest)
        }
    } else {
        urlSet(id, "pathname", rest)
    }

    return new UrlParts(id)
}

// ── URL.format — format UrlParts back to string ─────────────

function URL_format(parts: UrlParts): string {
    return urlBuildHref(parts.urlId)
}

// ── URL.resolve — resolve relative URL against base ─────────

function URL_resolve(base: string, ref: string): string {
    if (ref.indexOf("://") >= 0) { return ref }

    const bp = URL_parse(base)
    const proto = bp.protocol()
    const h = bp.host()

    // Protocol-relative: //host/path
    if (ref.length() >= 2 && ref.charAt(0) == "/" && ref.charAt(1) == "/") {
        return `${proto}://${urlSliceFrom(ref, 2)}`
    }

    // Absolute path
    if (ref.length() > 0 && ref.charAt(0) == "/") {
        return `${proto}://${h}${ref}`
    }

    // Relative path — merge with base directory
    let basePath = bp.pathname()
    let lastSlash = -1
    for (let i = 0; i < basePath.length(); i = i + 1) {
        if (basePath.charAt(i) == "/") { lastSlash = i }
    }
    if (lastSlash >= 0) {
        basePath = basePath.substring(0, lastSlash + 1)
    } else {
        basePath = "/"
    }
    return `${proto}://${h}${basePath}${ref}`
}

// ── URL.parseQuery — parse query string to Map ──────────────

function URL_parseQuery(qs: string): Map<string, string> {
    const result = new Map()
    if (qs == "") { return result }

    let input = qs
    if (input.charAt(0) == "?") {
        input = urlSliceFrom(input, 1)
    }
    if (input == "") { return result }

    let start = 0
    for (let i = 0; i <= input.length(); i = i + 1) {
        if (i == input.length() || input.charAt(i) == "&") {
            if (i > start) {
                const pair = input.substring(start, i - start)
                const eqIdx = pair.indexOf("=")
                if (eqIdx >= 0) {
                    const key = URL_decodeComponent(pair.substring(0, eqIdx))
                    const val = URL_decodeComponent(urlSliceFrom(pair, eqIdx + 1))
                    result.set(key, val)
                } else {
                    result.set(URL_decodeComponent(pair), "")
                }
            }
            start = i + 1
        }
    }
    return result
}

// ── URL.encodeQuery — encode parallel arrays to query string ─

function URL_encodeQuery(keys: Array<string>, values: Array<string>): string {
    let result = ""
    const len = keys.length()
    const vlen = values.length()
    for (let i = 0; i < len; i = i + 1) {
        const key = URL_encodeComponent(keys[i])
        let val = ""
        if (i < vlen) {
            val = URL_encodeComponent(values[i])
        }
        if (i > 0) {
            result = `${result}&${key}=${val}`
        } else {
            result = `${key}=${val}`
        }
    }
    return result
}

// ── URL.encodeComponent — percent-encode string ─────────────

function URL_encodeComponent(str: string): string {
    let result = ""
    for (let i = 0; i < str.length(); i = i + 1) {
        const c = str.charCodeAt(i)
        if (urlIsUnreserved(c) == 1) {
            result = `${result}${str.charAt(i)}`
        } else {
            const hi = c / 16
            const lo = c % 16
            result = `${result}%${urlHexChar(hi)}${urlHexChar(lo)}`
        }
    }
    return result
}

// ── URL.decodeComponent — decode percent-encoded string ─────

function URL_decodeComponent(str: string): string {
    let result = ""
    let i = 0
    while (i < str.length()) {
        if (str.charAt(i) == "%" && i + 2 < str.length()) {
            const hi = urlHexVal(str.charCodeAt(i + 1))
            const lo = urlHexVal(str.charCodeAt(i + 2))
            if (hi >= 0 && lo >= 0) {
                result = `${result}${fromCharCode(hi * 16 + lo)}`
                i = i + 3
                continue
            }
        }
        if (str.charAt(i) == "+") {
            result = `${result} `
        } else {
            result = `${result}${str.charAt(i)}`
        }
        i = i + 1
    }
    return result
}

// ── Internal: build href from stored parts ───────────────────

function urlBuildHref(id: int): string {
    let result = ""
    const proto = urlGet(id, "protocol")
    if (proto != "") {
        result = `${proto}://`
    }
    const user = urlGet(id, "username")
    if (user != "") {
        const pass = urlGet(id, "password")
        if (pass != "") {
            result = `${result}${user}:${pass}@`
        } else {
            result = `${result}${user}@`
        }
    }
    const hostname = urlGet(id, "hostname")
    const port = urlGet(id, "port")
    if (port != "") {
        result = `${result}${hostname}:${port}`
    } else {
        result = `${result}${hostname}`
    }
    result = `${result}${urlGet(id, "pathname")}`
    const query = urlGet(id, "search")
    if (query != "") {
        result = `${result}?${query}`
    }
    const frag = urlGet(id, "hash")
    if (frag != "") {
        result = `${result}#${frag}`
    }
    return result
}

// ── Internal: parse authority [userinfo@]host[:port] ─────────

function urlParseAuthority(id: int, authority: string) {
    let rest = authority

    const atIdx = rest.indexOf("@")
    if (atIdx >= 0) {
        const userInfo = rest.substring(0, atIdx)
        rest = urlSliceFrom(rest, atIdx + 1)
        const colonIdx = userInfo.indexOf(":")
        if (colonIdx >= 0) {
            urlSet(id, "username", userInfo.substring(0, colonIdx))
            urlSet(id, "password", urlSliceFrom(userInfo, colonIdx + 1))
        } else {
            urlSet(id, "username", userInfo)
        }
    }

    // IPv6 bracket notation: [::1] or [::1]:port
    if (rest.length() > 0 && rest.charAt(0) == "[") {
        const bracketEnd = rest.indexOf("]")
        if (bracketEnd >= 0) {
            urlSet(id, "hostname", rest.substring(0, bracketEnd + 1))
            if (bracketEnd + 1 < rest.length() && rest.charAt(bracketEnd + 1) == ":") {
                urlSet(id, "port", urlSliceFrom(rest, bracketEnd + 2))
            }
            return
        }
    }

    let lastColon = -1
    for (let i = 0; i < rest.length(); i = i + 1) {
        if (rest.charAt(i) == ":") { lastColon = i }
    }
    if (lastColon >= 0) {
        const portStr = urlSliceFrom(rest, lastColon + 1)
        if (urlIsNumeric(portStr) == 1) {
            urlSet(id, "hostname", rest.substring(0, lastColon))
            urlSet(id, "port", portStr)
        } else {
            urlSet(id, "hostname", rest)
        }
    } else {
        urlSet(id, "hostname", rest)
    }
}

// ── Internal helpers ─────────────────────────────────────────

function urlFindPathStart(str: string): int {
    // Handles IPv6 brackets — don't match / inside [...]
    let inBracket = 0
    for (let i = 0; i < str.length(); i = i + 1) {
        const c = str.charAt(i)
        if (c == "[") { inBracket = 1 }
        if (c == "]") { inBracket = 0 }
        if (c == "/" && inBracket == 0) { return i }
    }
    return -1
}

function urlIsValidScheme(s: string): int {
    if (s.length() == 0) { return 0 }
    const first = s.charCodeAt(0)
    if ((first < 65 || first > 90) && (first < 97 || first > 122)) { return 0 }
    for (let i = 1; i < s.length(); i = i + 1) {
        const c = s.charCodeAt(i)
        if (c >= 65 && c <= 90) { continue }
        if (c >= 97 && c <= 122) { continue }
        if (c >= 48 && c <= 57) { continue }
        if (c == 43 || c == 45 || c == 46) { continue }
        return 0
    }
    return 1
}

function urlIsNumeric(s: string): int {
    if (s.length() == 0) { return 0 }
    for (let i = 0; i < s.length(); i = i + 1) {
        const c = s.charCodeAt(i)
        if (c < 48 || c > 57) { return 0 }
    }
    return 1
}

function urlIsUnreserved(c: int): int {
    if (c >= 65 && c <= 90) { return 1 }
    if (c >= 97 && c <= 122) { return 1 }
    if (c >= 48 && c <= 57) { return 1 }
    if (c == 45 || c == 95 || c == 46 || c == 126) { return 1 }
    return 0
}

function urlHexChar(n: int): string {
    const hex = "0123456789ABCDEF"
    return hex.charAt(n)
}

function urlHexVal(c: int): int {
    if (c >= 48 && c <= 57) { return c - 48 }
    if (c >= 65 && c <= 70) { return c - 55 }
    if (c >= 97 && c <= 102) { return c - 87 }
    return -1
}
