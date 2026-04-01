// SimpleScript Template Library — Mustache-style template engine
//
// Usage:
//   import { Template } from "@/lib/template"
//
//   let vars = new Map()
//   vars.set("name", "Alice")
//   vars.set("greeting", "Hello")
//   Template.render("{{greeting}}, {{name}}!", vars)   // "Hello, Alice!"
//
//   // Sections (conditional)
//   vars.set("loggedIn", "true")
//   Template.render("{{#loggedIn}}Welcome!{{/loggedIn}}", vars)  // "Welcome!"
//
//   // Inverted sections
//   Template.render("{{^admin}}Guest{{/admin}}", vars)  // "Guest"
//
//   // Comments
//   Template.render("Hello{{! this is ignored }}World", vars)  // "HelloWorld"
//
//   // HTML escaping
//   Template.escape("<b>bold</b>")  // "&lt;b&gt;bold&lt;/b&gt;"
//
//   // Extract variable names
//   Template.variables("{{a}} and {{#b}}{{c}}{{/b}}")  // ["a", "b", "c"]
//
//   // Strip all tags
//   Template.strip("Hello {{name}}!")  // "Hello !"

class Template()

// ── Internal Helpers ─────────────────────────────────────────

function tmplTrim(s: string): string {
    const len = s.length()
    if (len == 0) { return "" }
    let start = 0
    while (start < len && s.charAt(start) == " ") {
        start = start + 1
    }
    let end = len - 1
    while (end > start && s.charAt(end) == " ") {
        end = end - 1
    }
    if (start > end) { return "" }
    return s.substring(start, end - start + 1)
}

function tmplSliceFrom(s: string, start: int): string {
    return s.substring(start, s.length() - start)
}

function tmplIsTruthy(vars: Map, key: string): int {
    if (vars.has(key) == 0) { return 0 }
    const val = vars.getString(key)
    if (val == "") { return 0 }
    if (val == "false") { return 0 }
    if (val == "0") { return 0 }
    return 1
}

// Skip past {{ ... }}, returning position after }}
function tmplSkipTag(tmpl: string, pos: int): int {
    let i = pos + 2
    const len = tmpl.length()
    while (i + 1 < len) {
        if (tmpl.charAt(i) == "}" && tmpl.charAt(i + 1) == "}") {
            return i + 2
        }
        i = i + 1
    }
    return len
}

// Find matching {{/key}} for a section opened at pos
// Returns start position of {{/key}} or -1
function tmplFindClose(tmpl: string, pos: int, key: string): int {
    const len = tmpl.length()
    let depth = 1
    let i = pos

    while (i < len) {
        if (i + 1 < len && tmpl.charAt(i) == "{" && tmpl.charAt(i + 1) == "{") {
            let j = i + 2
            while (j + 1 < len) {
                if (tmpl.charAt(j) == "}" && tmpl.charAt(j + 1) == "}") {
                    break
                }
                j = j + 1
            }
            if (j + 1 >= len) { return -1 }

            const tag = tmplTrim(tmpl.substring(i + 2, j - i - 2))

            if (tag.length() > 0) {
                const first = tag.charAt(0)
                if (first == "#" || first == "^") {
                    if (tmplTrim(tmplSliceFrom(tag, 1)) == key) {
                        depth = depth + 1
                    }
                } else if (first == "/") {
                    if (tmplTrim(tmplSliceFrom(tag, 1)) == key) {
                        depth = depth - 1
                        if (depth == 0) { return i }
                    }
                }
            }

            i = j + 2
        } else {
            i = i + 1
        }
    }

    return -1
}

// ── Core render implementation ───────────────────────────────

function tmplRenderImpl(tmpl: string, vars: Map): string {
    let result = ""
    let pos = 0
    const len = tmpl.length()

    while (pos < len) {
        // Escape: \{{ → literal {{
        if (tmpl.charAt(pos) == "\\" && pos + 2 < len && tmpl.charAt(pos + 1) == "{" && tmpl.charAt(pos + 2) == "{") {
            result = result + "{{"
            pos = pos + 3
            continue
        }

        // Tag: {{ ... }}
        if (pos + 1 < len && tmpl.charAt(pos) == "{" && tmpl.charAt(pos + 1) == "{") {
            let endPos = pos + 2
            while (endPos + 1 < len) {
                if (tmpl.charAt(endPos) == "}" && tmpl.charAt(endPos + 1) == "}") {
                    break
                }
                endPos = endPos + 1
            }

            if (endPos + 1 >= len) {
                result = result + tmpl.charAt(pos)
                pos = pos + 1
                continue
            }

            const tag = tmplTrim(tmpl.substring(pos + 2, endPos - pos - 2))

            if (tag.length() == 0) {
                pos = endPos + 2
            } else if (tag.charAt(0) == "!") {
                // Comment — skip
                pos = endPos + 2
            } else if (tag.charAt(0) == "#") {
                // Section: {{#key}}...{{/key}}
                const key = tmplTrim(tmplSliceFrom(tag, 1))
                const bodyStart = endPos + 2
                const closePos = tmplFindClose(tmpl, bodyStart, key)
                if (closePos < 0) {
                    result = result + tmpl.substring(pos, endPos + 2 - pos)
                    pos = endPos + 2
                } else {
                    if (tmplIsTruthy(vars, key) == 1) {
                        const body = tmpl.substring(bodyStart, closePos - bodyStart)
                        result = result + tmplRenderImpl(body, vars)
                    }
                    pos = tmplSkipTag(tmpl, closePos)
                }
            } else if (tag.charAt(0) == "^") {
                // Inverted section: {{^key}}...{{/key}}
                const key = tmplTrim(tmplSliceFrom(tag, 1))
                const bodyStart = endPos + 2
                const closePos = tmplFindClose(tmpl, bodyStart, key)
                if (closePos < 0) {
                    result = result + tmpl.substring(pos, endPos + 2 - pos)
                    pos = endPos + 2
                } else {
                    if (tmplIsTruthy(vars, key) == 0) {
                        const body = tmpl.substring(bodyStart, closePos - bodyStart)
                        result = result + tmplRenderImpl(body, vars)
                    }
                    pos = tmplSkipTag(tmpl, closePos)
                }
            } else {
                // Variable substitution: {{key}}
                if (vars.has(tag) == 1) {
                    result = result + vars.getString(tag)
                }
                pos = endPos + 2
            }
        } else {
            result = result + tmpl.charAt(pos)
            pos = pos + 1
        }
    }

    return result
}

// ── Public Static Methods ────────────────────────────────────

// Template.render — render template with variable map
function Template_render(tmpl: string, vars: Map): string {
    return tmplRenderImpl(tmpl, vars)
}

// Template.escape — HTML-escape special characters
function Template_escape(text: string): string {
    let result = ""
    let i = 0
    const len = text.length()
    while (i < len) {
        const c = text.charAt(i)
        if (c == "&") {
            result = result + "&amp;"
        } else if (c == "<") {
            result = result + "&lt;"
        } else if (c == ">") {
            result = result + "&gt;"
        } else if (c == "\"") {
            result = result + "&quot;"
        } else if (c == "'") {
            result = result + "&#39;"
        } else {
            result = result + c
        }
        i = i + 1
    }
    return result
}

// Template.unescape — reverse HTML entity escaping
function Template_unescape(text: string): string {
    let result = ""
    let i = 0
    const len = text.length()
    while (i < len) {
        if (text.charAt(i) == "&") {
            if (i + 3 < len && text.charAt(i + 1) == "l" && text.charAt(i + 2) == "t" && text.charAt(i + 3) == ";") {
                result = result + "<"
                i = i + 4
                continue
            }
            if (i + 3 < len && text.charAt(i + 1) == "g" && text.charAt(i + 2) == "t" && text.charAt(i + 3) == ";") {
                result = result + ">"
                i = i + 4
                continue
            }
            if (i + 4 < len && text.charAt(i + 1) == "a" && text.charAt(i + 2) == "m" && text.charAt(i + 3) == "p" && text.charAt(i + 4) == ";") {
                result = result + "&"
                i = i + 5
                continue
            }
            if (i + 5 < len && text.charAt(i + 1) == "q" && text.charAt(i + 2) == "u" && text.charAt(i + 3) == "o" && text.charAt(i + 4) == "t" && text.charAt(i + 5) == ";") {
                result = result + "\""
                i = i + 6
                continue
            }
            if (i + 4 < len && text.charAt(i + 1) == "#" && text.charAt(i + 2) == "3" && text.charAt(i + 3) == "9" && text.charAt(i + 4) == ";") {
                result = result + "'"
                i = i + 5
                continue
            }
        }
        result = result + text.charAt(i)
        i = i + 1
    }
    return result
}

// Template.variables — extract unique variable/section names from template
function Template_variables(tmpl: string): Array<string> {
    let result: Array<string> = []
    let seen = new Map()
    let pos = 0
    const len = tmpl.length()

    while (pos < len) {
        if (pos + 1 < len && tmpl.charAt(pos) == "{" && tmpl.charAt(pos + 1) == "{") {
            let endPos = pos + 2
            while (endPos + 1 < len) {
                if (tmpl.charAt(endPos) == "}" && tmpl.charAt(endPos + 1) == "}") {
                    break
                }
                endPos = endPos + 1
            }

            if (endPos + 1 < len) {
                const tag = tmplTrim(tmpl.substring(pos + 2, endPos - pos - 2))

                if (tag.length() > 0) {
                    let varName = tag
                    const first = tag.charAt(0)
                    if (first == "#" || first == "^" || first == "/") {
                        varName = tmplTrim(tmplSliceFrom(tag, 1))
                    } else if (first == "!") {
                        varName = ""
                    }

                    if (varName != "" && seen.has(varName) == 0) {
                        result = result.push(varName)
                        seen.set(varName, "1")
                    }
                }

                pos = endPos + 2
            } else {
                pos = pos + 1
            }
        } else {
            pos = pos + 1
        }
    }

    return result
}

// Template.strip — remove all {{...}} tags from template
function Template_strip(tmpl: string): string {
    let result = ""
    let pos = 0
    const len = tmpl.length()

    while (pos < len) {
        if (pos + 1 < len && tmpl.charAt(pos) == "{" && tmpl.charAt(pos + 1) == "{") {
            let endPos = pos + 2
            while (endPos + 1 < len) {
                if (tmpl.charAt(endPos) == "}" && tmpl.charAt(endPos + 1) == "}") {
                    break
                }
                endPos = endPos + 1
            }
            if (endPos + 1 < len) {
                pos = endPos + 2
            } else {
                result = result + tmpl.charAt(pos)
                pos = pos + 1
            }
        } else {
            result = result + tmpl.charAt(pos)
            pos = pos + 1
        }
    }

    return result
}
