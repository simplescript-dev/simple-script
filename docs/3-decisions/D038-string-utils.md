# D038: String Utility Module (lib/string_utils.ss)

**Status:** Accepted
**Depends-on:** D035 (stdlib pattern)

## Decision

Add `lib/string_utils.ss` — a pure SS utility module providing 16 higher-level string operations as `StringUtil` static methods, complementing existing string instance methods.

## Functions

| Method | Signature | Purpose |
|--------|-----------|---------|
| `trimStart` | `(s: string): string` | Remove leading whitespace |
| `trimEnd` | `(s: string): string` | Remove trailing whitespace |
| `capitalize` | `(s: string): string` | Uppercase first character |
| `reverse` | `(s: string): string` | Reverse character order |
| `isBlank` | `(s: string): int` | Check if empty or whitespace-only |
| `isDigit` | `(s: string): int` | Check if all characters are 0-9 |
| `isAlpha` | `(s: string): int` | Check if all characters are a-z/A-Z |
| `isAlphaNumeric` | `(s: string): int` | Check if all characters are alphanumeric |
| `padCenter` | `(s: string, width: int, pad: string): string` | Center-pad to width |
| `truncate` | `(s: string, maxLen: int, suffix: string): string` | Truncate with suffix |
| `count` | `(s: string, sub: string): int` | Count non-overlapping occurrences |
| `removePrefix` | `(s: string, prefix: string): string` | Strip prefix if present |
| `removeSuffix` | `(s: string, suffix: string): string` | Strip suffix if present |
| `equalsIgnoreCase` | `(a: string, b: string): int` | Case-insensitive equality |
| `lines` | `(s: string): Array<string>` | Split by newlines (handles \r\n) |
| `words` | `(s: string): Array<string>` | Split by whitespace, skip empty |

## Reasoning

- Existing string instance methods (15) cover core operations (charAt, substring, trim, etc.)
- This module adds utility-level operations common in Go `strings` package, Java `StringUtils`, and TypeScript utility libraries
- No compiler changes required — pure SS implementation using static method pattern (D035)
- Complements `padStart`/`padEnd` with `padCenter`, `trim` with `trimStart`/`trimEnd`

## Rejected Alternatives

- **Instance methods on string**: Would require compiler changes (gen_builtins.ss). Static method pattern is simpler and consistent with MathUtil/Path
- **format() function**: Dynamic format strings require variable-arity support; template strings already cover this use case
- **camelCase/snakeCase/kebabCase**: Complex logic for limited benefit; deferred to future round if needed

## Interfaces

- Import: `import { StringUtil } from "@/lib/string_utils"`
- Call: `StringUtil.capitalize("hello")` → `"Hello"`
- No compiler changes, no new builtins, no runtime additions

## Tensions

None. Pure library module, no impact on compiler or bootstrap.
