# D046: Template Module (lib/template.ss)

**Status:** Accepted
**Depends on:** D035 (stdlib pattern)

## Decision

Add `lib/template.ss` — a Mustache-style template engine providing string interpolation with conditional sections, comments, and HTML escaping utilities.

## Reasoning

- Standard library now covers 14 modules but lacks a template/rendering engine
- Template engines are fundamental for generating dynamic text output (config files, emails, reports, HTML)
- SimpleScript already has template strings (`${var}`) for compile-time interpolation; this module enables runtime interpolation from dynamic data (Maps)
- Mustache is the simplest widely-adopted template syntax — no logic, just variable substitution and conditional sections
- Pure SS implementation, no compiler changes needed

## Template Syntax

| Syntax | Meaning |
|--------|---------|
| `{{key}}` | Variable substitution (trimmed, from Map) |
| `{{#key}}...{{/key}}` | Section: render if key is truthy |
| `{{^key}}...{{/key}}` | Inverted section: render if key is falsy |
| `{{! comment }}` | Comment (removed from output) |
| `\{{` | Escaped delimiter (literal `{{`) |

**Truthiness:** A key is truthy if it exists in the Map AND value is not `""`, `"false"`, or `"0"`.

## Static Methods (5)

| Method | Signature | Purpose |
|--------|-----------|---------|
| `render` | `(tmpl: string, vars: Map): string` | Main template rendering |
| `escape` | `(text: string): string` | HTML-escape `& < > " '` |
| `unescape` | `(text: string): string` | Reverse HTML escaping |
| `variables` | `(tmpl: string): Array<string>` | Extract unique variable names |
| `strip` | `(tmpl: string): string` | Remove all `{{...}}` tags |

## Internal Helpers

| Function | Purpose |
|----------|---------|
| `tmplTrim(s)` | Trim leading/trailing spaces |
| `tmplSliceFrom(s, start)` | Substring from start to end |
| `tmplIsTruthy(vars, key)` | Check truthiness rules |
| `tmplSkipTag(tmpl, pos)` | Skip past `}}` from `{{` position |
| `tmplFindClose(tmpl, pos, key)` | Find matching `{{/key}}` with nesting |

## Rejected Alternatives

1. **Handlebars-style with helpers/partials** — Too complex for v1. Mustache's logic-less approach fits better.
2. **EJS-style with embedded code** — Would require an evaluator/interpreter. Overkill.
3. **Regex-based parsing** — SS has no regex support. Character-by-character scanning is the established pattern.

## Interfaces

```
import { Template } from "@/lib/template"

let vars = new Map()
vars.set("name", "Alice")
vars.set("greeting", "Hello")
Template.render("{{greeting}}, {{name}}!", vars)  // "Hello, Alice!"

// Conditional sections
vars.set("loggedIn", "true")
Template.render("{{#loggedIn}}Welcome!{{/loggedIn}}", vars)  // "Welcome!"

// HTML escaping
Template.escape("<script>alert('xss')</script>")
// "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"
```
