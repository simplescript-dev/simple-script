# D048 — Regex Module (lib/regex.ss)

**Status**: Accepted
**Depends-on**: D035 (static method pattern), D033 (string `.includes()`)

## Decision

Add `lib/regex.ss` — a basic regular expression matching library using the static method pattern. Pure SS implementation, no compiler changes.

## API

```
import { Regex } from "@/lib/regex"

Regex.test(pattern, text): int              // 1 if match found anywhere
Regex.match(pattern, text): string          // first matched substring, "" if none
Regex.matchAll(pattern, text): Array<string> // all non-overlapping matches
Regex.matchIndex(pattern, text): int        // start index of first match, -1 if none
Regex.replace(pattern, text, repl): string  // replace first match
Regex.replaceAll(pattern, text, repl): string  // replace all matches
Regex.split(pattern, text): Array<string>   // split by pattern
Regex.escape(text): string                  // escape special chars for literal matching
```

## Supported Patterns

| Pattern | Meaning |
|---------|---------|
| `.` | Any char (except newline) |
| `*` | Zero or more (greedy) |
| `+` | One or more (greedy) |
| `?` | Zero or one (greedy) |
| `^` / `$` | Start / end anchor |
| `[abc]` | Character class |
| `[a-z]` | Character range |
| `[^abc]` | Negated class |
| `\d` `\w` `\s` | Digit, word char, whitespace |
| `\D` `\W` `\S` | Negated shorthands |
| `(...)` | Grouping |
| `\|` | Alternation |
| `\\` | Escape special char |

## Architecture

Recursive backtracking engine operating directly on the pattern string — no compilation step.

**Core functions:**
- `rxMatchAt(pat, pi, pEnd, text, ti, tLen)` — match `pat[pi:pEnd)` at `text[ti:]`, returns end position or -1
- `rxMatchOne(pat, pi, atomEnd, text, ti, tLen)` — match one atom instance, returns end position or -1
- `rxFindMatch(pat, text, startPos)` — find first match from position, sets `rxStart`/`rxEnd` globals

**Pattern navigation:** `rxAtomEnd` determines atom boundaries (literal, escape, class `[...]`, group `(...)`). `rxFindAlt` finds top-level `|` (skipping groups and classes). `rxFindGroupEnd` / `rxFindClassEnd` handle nesting.

**Quantifier handling:** Greedy — collect all possible match positions in an `Array<int>`, then backtrack from most to least. `?` caps at 1 match. Zero-progress check prevents infinite loops on empty-matching atoms.

**Global state:** `rxStart`/`rxEnd` (int globals, initialized to 0) store the last match position. Set by `rxFindMatch`, consumed by public API methods.

## Reasoning

- **Recursive backtracking over NFA/DFA**: Simpler to implement in SS (~310 lines). Handles all listed features including groups and alternation. Exponential worst-case on pathological patterns is acceptable for a stdlib module.
- **No compilation step**: Pattern parsed on-the-fly during matching. Avoids needing a separate IR representation. Clean and compact.
- **Greedy-only**: Lazy quantifiers (`*?`, `+?`) omitted for simplicity. Greedy covers most real-world use cases.
- **Global int initial value 0 (not -1)**: SS compiler parses `-1` as UNARY_MINUS(INT_LIT(1)), which falls into the non-literal global init path and gets typed as `ptr`. Using `0` (plain INT_LIT) avoids this.

## Rejected Alternatives

- **Thompson NFA**: Better worst-case complexity but significantly more code and harder to support groups/alternation cleanly.
- **Pre-compiled pattern IR**: Would improve repeated matching performance but adds complexity (Map-based IR nodes). Not needed for stdlib use cases.
- **Lazy quantifiers**: Adds implementation complexity with limited practical benefit for basic patterns.
- **Capture groups**: Would need a way to return multiple strings (array or Map). Deferred for future enhancement.

## Interfaces

- **Import**: `import { Regex } from "@/lib/regex"`
- **Internal helpers (16)**: `rxIsDigit`, `rxIsAlpha`, `rxIsWord`, `rxIsSpace`, `rxFindClassEnd`, `rxFindGroupEnd`, `rxAtomEnd`, `rxFindAlt`, `rxMatchClassInner`, `rxMatchClass`, `rxMatchEscape`, `rxMatchOne`, `rxMatchAt`, `rxFindMatch`
- **Globals (2)**: `rxStart`, `rxEnd`

## Tensions

None. Pure SS stdlib addition, no compiler changes, no constraint conflicts.
