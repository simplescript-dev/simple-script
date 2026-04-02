// SimpleScript UUID Library — UUID v4 generation and validation
//
// Usage:
//   import { UUID } from "@/lib/uuid"
//
//   const id = UUID.v4()           // "550e8400-e29b-41d4-a716-446655440000"
//   UUID.isValid(id)               // 1
//   UUID.version(id)               // 4
//   UUID.parse(id)                 // normalized lowercase
//   UUID.nil()                     // "00000000-0000-0000-0000-000000000000"

class UUID {}

// ── Internal helpers ─────────────────────────────────────────

function uuidHexChar(n: int): string {
    const hex = "0123456789abcdef"
    return hex.charAt(n)
}

function uuidIsHexChar(c: string): int {
    if (c >= "0" && c <= "9") { return 1 }
    if (c >= "a" && c <= "f") { return 1 }
    if (c >= "A" && c <= "F") { return 1 }
    return 0
}

function uuidLowerChar(c: string): string {
    if (c == "A") { return "a" }
    if (c == "B") { return "b" }
    if (c == "C") { return "c" }
    if (c == "D") { return "d" }
    if (c == "E") { return "e" }
    if (c == "F") { return "f" }
    return c
}

// ── UUID static methods ──────────────────────────────────────

// Generate a random UUID v4
// Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
// where x is random hex, 4 is version, y is variant (8/9/a/b)
function UUID_v4(): string {
    let result = ""
    let i = 0
    while (i < 32) {
        if (i == 12) {
            // Version: always '4'
            result = result + "4"
        } else if (i == 16) {
            // Variant: 10xx → 8, 9, a, or b
            const r = Math.randomInt(4)
            result = result + uuidHexChar(8 + r)
        } else {
            const r = Math.randomInt(16)
            result = result + uuidHexChar(r)
        }
        i = i + 1
        if (i == 8 || i == 12 || i == 16 || i == 20) {
            result = result + "-"
        }
    }
    return result
}

// Validate UUID format (any version, 8-4-4-4-12 hex pattern)
function UUID_isValid(str: string): int {
    if (str.length() != 36) { return 0 }
    let i = 0
    while (i < 36) {
        const c = str.charAt(i)
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (c != "-") { return 0 }
        } else {
            if (uuidIsHexChar(c) == 0) { return 0 }
        }
        i = i + 1
    }
    return 1
}

// Parse and normalize a UUID string (lowercase, validate)
// Returns "" if invalid
function UUID_parse(str: string): string {
    if (UUID_isValid(str) == 0) { return "" }
    let result = ""
    let i = 0
    while (i < 36) {
        const c = str.charAt(i)
        if (c == "-") {
            result = result + "-"
        } else {
            result = result + uuidLowerChar(c)
        }
        i = i + 1
    }
    return result
}

// Extract version number from UUID string (0 if invalid)
function UUID_version(str: string): int {
    if (UUID_isValid(str) == 0) { return 0 }
    // Version is at position 14 (after "xxxxxxxx-xxxx-")
    const c = str.charAt(14)
    if (c >= "0" && c <= "9") {
        return str.charCodeAt(14) - 48
    }
    return 0
}

// Return the nil UUID (all zeros)
function UUID_nil(): string {
    return "00000000-0000-0000-0000-000000000000"
}
