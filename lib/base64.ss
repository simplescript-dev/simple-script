// Base64 encoder/decoder — pure SimpleScript, no C dependency
// Can replace ss_base64Encode/ss_base64Decode in runtime.c

const B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function base64encode(data: string): string {
    const len = data.length()
    let result = ""
    let i = 0
    while (i < len) {
        const a = data.charCodeAt(i)
        const b = i + 1 < len ? data.charCodeAt(i + 1) : 0
        const c = i + 2 < len ? data.charCodeAt(i + 2) : 0
        const n = a * 65536 + b * 256 + c

        result = result + B64_CHARS.charAt((n / 262144) % 64)
        result = result + B64_CHARS.charAt((n / 4096) % 64)
        if (i + 1 < len) {
            result = result + B64_CHARS.charAt((n / 64) % 64)
        } else {
            result = result + "="
        }
        if (i + 2 < len) {
            result = result + B64_CHARS.charAt(n % 64)
        } else {
            result = result + "="
        }
        i = i + 3
    }
    return result
}

function b64CharVal(ch: string): int {
    const c = ch.charCodeAt(0)
    if (c >= 65 && c <= 90) { return c - 65 }
    if (c >= 97 && c <= 122) { return c - 97 + 26 }
    if (c >= 48 && c <= 57) { return c - 48 + 52 }
    if (ch == "+") { return 62 }
    if (ch == "/") { return 63 }
    return 0
}

function base64decode(data: string): string {
    const len = data.length()
    let result = ""
    let i = 0
    while (i < len) {
        const a = b64CharVal(data.charAt(i))
        const b = b64CharVal(data.charAt(i + 1))
        const c = b64CharVal(data.charAt(i + 2))
        const d = b64CharVal(data.charAt(i + 3))

        result = result + fromCharCode(a * 4 + b / 16)
        if (data.charAt(i + 2) != "=") {
            result = result + fromCharCode((b % 16) * 16 + c / 4)
        }
        if (data.charAt(i + 3) != "=") {
            result = result + fromCharCode((c % 4) * 64 + d)
        }
        i = i + 4
    }
    return result
}
