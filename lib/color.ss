// SimpleScript Color Library — ANSI terminal color utilities
//
// Usage:
//   import { Color } from "@/lib/color"
//
//   println(Color.red("error"))
//   println(Color.bold(Color.green("success")))
//   println(Color.bgYellow(Color.black("warning")))
//   const clean = Color.strip(Color.red("text"))  // "text"

class Color {}

// ── Internal helper ──────────────────────────────────────────

function colorWrap(text: string, open: int, close: int): string {
    const esc = fromCharCode(27)
    return `${esc}[${open}m${text}${esc}[${close}m`
}

// ── Modifiers ────────────────────────────────────────────────

function Color_bold(text: string): string {
    return colorWrap(text, 1, 22)
}

function Color_dim(text: string): string {
    return colorWrap(text, 2, 22)
}

function Color_italic(text: string): string {
    return colorWrap(text, 3, 23)
}

function Color_underline(text: string): string {
    return colorWrap(text, 4, 24)
}

function Color_inverse(text: string): string {
    return colorWrap(text, 7, 27)
}

function Color_strikethrough(text: string): string {
    return colorWrap(text, 9, 29)
}

// ── Foreground colors ────────────────────────────────────────

function Color_black(text: string): string {
    return colorWrap(text, 30, 39)
}

function Color_red(text: string): string {
    return colorWrap(text, 31, 39)
}

function Color_green(text: string): string {
    return colorWrap(text, 32, 39)
}

function Color_yellow(text: string): string {
    return colorWrap(text, 33, 39)
}

function Color_blue(text: string): string {
    return colorWrap(text, 34, 39)
}

function Color_magenta(text: string): string {
    return colorWrap(text, 35, 39)
}

function Color_cyan(text: string): string {
    return colorWrap(text, 36, 39)
}

function Color_white(text: string): string {
    return colorWrap(text, 37, 39)
}

// ── Bright foreground colors ─────────────────────────────────

function Color_gray(text: string): string {
    return colorWrap(text, 90, 39)
}

function Color_brightRed(text: string): string {
    return colorWrap(text, 91, 39)
}

function Color_brightGreen(text: string): string {
    return colorWrap(text, 92, 39)
}

function Color_brightYellow(text: string): string {
    return colorWrap(text, 93, 39)
}

function Color_brightBlue(text: string): string {
    return colorWrap(text, 94, 39)
}

function Color_brightMagenta(text: string): string {
    return colorWrap(text, 95, 39)
}

function Color_brightCyan(text: string): string {
    return colorWrap(text, 96, 39)
}

function Color_brightWhite(text: string): string {
    return colorWrap(text, 97, 39)
}

// ── Background colors ────────────────────────────────────────

function Color_bgBlack(text: string): string {
    return colorWrap(text, 40, 49)
}

function Color_bgRed(text: string): string {
    return colorWrap(text, 41, 49)
}

function Color_bgGreen(text: string): string {
    return colorWrap(text, 42, 49)
}

function Color_bgYellow(text: string): string {
    return colorWrap(text, 43, 49)
}

function Color_bgBlue(text: string): string {
    return colorWrap(text, 44, 49)
}

function Color_bgMagenta(text: string): string {
    return colorWrap(text, 45, 49)
}

function Color_bgCyan(text: string): string {
    return colorWrap(text, 46, 49)
}

function Color_bgWhite(text: string): string {
    return colorWrap(text, 47, 49)
}

// ── Utilities ────────────────────────────────────────────────

// Remove all ANSI escape sequences from a string
function Color_strip(text: string): string {
    const esc = fromCharCode(27)
    const escCode = 27
    let result = ""
    let i = 0
    const len = text.length()
    while (i < len) {
        if (text.charCodeAt(i) == escCode && i + 1 < len && text.charAt(i + 1) == "[") {
            // Skip ESC[ ... m sequence
            i = i + 2
            while (i < len && text.charAt(i) != "m") {
                i = i + 1
            }
            if (i < len) {
                i = i + 1
            }
        } else {
            result = result + text.charAt(i)
            i = i + 1
        }
    }
    return result
}

// Return the ANSI reset sequence
function Color_reset(): string {
    return `${fromCharCode(27)}[0m`
}
