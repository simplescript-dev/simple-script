# D040: JSON Unicode \uXXXX Escape Support

## Status
Implemented

## Depends On
D036 (JSON enhancements)

## Decision
Add full Unicode `\uXXXX` escape support to json.ss — parsing and serialization — completing JSON spec compliance for string handling. Also add missing `\b` (backspace) and `\f` (form feed) named escapes.

## Reasoning
The JSON specification (RFC 8259) requires `\uXXXX` escapes for arbitrary Unicode code points, `\b` for backspace, and `\f` for form feed. Our json.ss was missing all three. Adding these completes the string escape handling per spec.

## Implementation

### Parse direction (`jpParseString`)
- `\b` → `fromCharCode(8)` (SS has no `\b` literal)
- `\f` → `fromCharCode(12)` (SS has no `\f` literal)
- `\uXXXX` → parse 4 hex digits → UTF-8 encode via `jpCodePointToUtf8()`
- Surrogate pairs: `\uD800`–`\uDBFF` followed by `\uDC00`–`\uDFFF` → combined into U+10000+ code point

### Stringify direction (`jnEscapeString`)
- Byte 8 → `\b`, byte 12 → `\f` (named escapes)
- Other control chars (0–31, excluding already-handled `\n`/`\t`/`\r`) → `\u00XX`
- Non-ASCII bytes pass through as-is (UTF-8 preserved)

### Helper functions added
- `jpHexDigit(ch)` — hex char → 0–15
- `jpHexChar(n)` — 0–15 → hex char
- `jpCodePointToUtf8(cp)` — code point → UTF-8 string (1–4 bytes)
- `jpReadHex4()` — read 4 hex digits from parser position

### UTF-8 encoding scheme
| Range | Bytes | Template |
|-------|-------|----------|
| U+0000–U+007F | 1 | `0xxxxxxx` |
| U+0080–U+07FF | 2 | `110xxxxx 10xxxxxx` |
| U+0800–U+FFFF | 3 | `1110xxxx 10xxxxxx 10xxxxxx` |
| U+10000–U+10FFFF | 4 | `11110xxx 10xxxxxx 10xxxxxx 10xxxxxx` |

### Surrogate pair formula
```
cp = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
```

## Rejected Alternatives
- **Stringify all non-ASCII as \uXXXX**: Would require scanning UTF-8 multi-byte sequences to reconstruct code points. Passing through UTF-8 is simpler and valid per JSON spec (RFC 8259 Section 8.1).
- **Separate hex utility module**: Not needed — 4 small helper functions local to json.ss suffice.

## Interfaces
- No new public API. Existing `JSON.parse()` and `JSON.stringify()` now handle Unicode escapes transparently.

## Tensions
- None. Pure library change, no compiler modifications.
