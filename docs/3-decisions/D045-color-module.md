# D045: Color Module — ANSI Terminal Color Library

**Status:** Accepted
**Depends-on:** D035 (stdlib pattern)

## Decision

Add `lib/color.ss` — a lightweight ANSI terminal color library using the static method pattern. 32 methods total:

- **6 modifiers**: bold, dim, italic, underline, inverse, strikethrough
- **8 foreground colors**: black, red, green, yellow, blue, magenta, cyan, white
- **8 bright foreground colors**: gray (=brightBlack), brightRed, brightGreen, brightYellow, brightBlue, brightMagenta, brightCyan, brightWhite
- **8 background colors**: bgBlack, bgRed, bgGreen, bgYellow, bgBlue, bgMagenta, bgCyan, bgWhite
- **2 utilities**: strip (remove ANSI codes), reset (return reset sequence)

## Reasoning

Terminal color output is a basic capability for any CLI tool. ANSI escape codes are standardized and supported by virtually all modern terminals. Providing a clean API avoids users having to manually construct escape sequences.

## API Design

```ss
import { Color } from "@/lib/color"

// Basic usage
println(Color.red("error message"))
println(Color.green("success"))
println(Color.bold("important"))

// Composition via nesting
println(Color.bold(Color.red("critical error")))
println(Color.bgYellow(Color.black("warning")))

// Strip ANSI codes (useful for logging to files)
const clean = Color.strip(Color.red("colored"))  // "colored"

// Reset sequence
const rst = Color.reset()  // "\x1b[0m"
```

## Implementation

- **Pure SS**: No compiler changes. Uses static method pattern (`class Color()` + `Color_method()` functions).
- **ESC character**: Generated via `fromCharCode(27)` inline (no global state needed).
- **Core helper**: `colorWrap(text, open, close)` wraps text with `ESC[{open}m...ESC[{close}m`.
- **strip()**: Scans for ESC character and skips `ESC[...m` sequences.
- **Composition**: Nesting works naturally because inner calls produce strings that outer calls wrap.

## ANSI Code Reference

| Category | Name | Open | Close |
|----------|------|------|-------|
| Modifier | bold | 1 | 22 |
| Modifier | dim | 2 | 22 |
| Modifier | italic | 3 | 23 |
| Modifier | underline | 4 | 24 |
| Modifier | inverse | 7 | 27 |
| Modifier | strikethrough | 9 | 29 |
| FG | black | 30 | 39 |
| FG | red | 31 | 39 |
| FG | green | 32 | 39 |
| FG | yellow | 33 | 39 |
| FG | blue | 34 | 39 |
| FG | magenta | 35 | 39 |
| FG | cyan | 36 | 39 |
| FG | white | 37 | 39 |
| Bright FG | gray | 90 | 39 |
| Bright FG | brightRed | 91 | 39 |
| Bright FG | brightGreen | 92 | 39 |
| Bright FG | brightYellow | 93 | 39 |
| Bright FG | brightBlue | 94 | 39 |
| Bright FG | brightMagenta | 95 | 39 |
| Bright FG | brightCyan | 96 | 39 |
| Bright FG | brightWhite | 97 | 39 |
| BG | bgBlack | 40 | 49 |
| BG | bgRed | 41 | 49 |
| BG | bgGreen | 42 | 49 |
| BG | bgYellow | 43 | 49 |
| BG | bgBlue | 44 | 49 |
| BG | bgMagenta | 45 | 49 |
| BG | bgCyan | 46 | 49 |
| BG | bgWhite | 47 | 49 |

## Rejected Alternatives

- **Builder/chaining API** (`Color.red().bold().text("hi")`): SS lacks method chaining on ad-hoc builders. Nesting achieves the same result more simply.
- **256-color / TrueColor (RGB)**: Deferred. Basic 8+8 colors cover 95% of CLI use cases. Can extend later with `Color.rgb(r, g, b, text)`.
- **NO_COLOR env var support**: SS doesn't have `getenv()` builtin yet. Can add later.

## Interfaces

- **Import**: `import { Color } from "@/lib/color"`
- **No compiler changes**: Pure SS static methods
- **No new dependencies**: Uses only `fromCharCode()` builtin
