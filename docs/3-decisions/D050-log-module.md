# D050: Log Module — Structured Logging with Levels and Colors

**Status:** Accepted
**Depends on:** None (self-contained, uses `fromCharCode(27)` for ANSI escape)

## Decision

Add `lib/log.ss` — a pure SS structured logging library with 5 severity levels, level-based filtering, and optional ANSI color output.

## Reasoning

Every non-trivial program needs logging. A standard Log module provides:

1. **Severity levels** — DEBUG/INFO/WARN/ERROR/FATAL with numeric values 0-4
2. **Level filtering** — `setLevel(n)` suppresses messages below threshold, 5=OFF
3. **Color output** — each level has a distinct ANSI color for terminal readability
4. **Zero dependencies** — self-contained, no imports from other lib modules

## Rejected Alternatives

- **Import color.ss**: Would add a dependency. Inline `fromCharCode(27)` is simpler and keeps the module self-contained.
- **Stderr output**: SS has no native stderr. `writeFile("/dev/stderr", msg)` works on Linux but adds fopen/fclose overhead per line. Deferred — stdout is acceptable for a first version.
- **Timestamp support**: Would require importing datetime.ss or runtime `time()`. Users can compose `Log` with `DateTime` externally. Keeps the module minimal.
- **Printf-style formatting**: SS template strings `${expr}` already handle formatting at call site. No need for log-level format strings.

## Interfaces

### Import
```
import { Log } from "@/lib/log"
```

### Static Methods (9)

**Level methods** (output only if level >= current minimum):
- `Log.debug(msg: string)` — level 0, cyan (ANSI 36)
- `Log.info(msg: string)` — level 1, green (ANSI 32)
- `Log.warn(msg: string)` — level 2, yellow (ANSI 33)
- `Log.error(msg: string)` — level 3, red (ANSI 31)
- `Log.fatal(msg: string)` — level 4, bright red (ANSI 91)

**Generic**:
- `Log.log(level: int, msg: string)` — log at arbitrary level

**Configuration**:
- `Log.setLevel(level: int)` — set minimum level (0-4, 5=OFF)
- `Log.getLevel(): int` — get current minimum level
- `Log.enableColor(on: int)` — 1=colors on, 0=plain text

**Query**:
- `Log.isEnabled(level: int): int` — 1 if level would produce output

### Internal Helpers (1)
- `logOutput(level, label, colorCode, msg)` — format and print with optional color

### Module Globals (2)
- `logLevel` — current minimum level (default: 1 = INFO)
- `logColorOn` — color toggle (default: 1 = enabled)

## Output Format

Colored: `ESC[CODEm[LABEL]ESC[0m message`
Plain: `[LABEL] message`

Labels are 5 chars wide for alignment: `DEBUG`, `INFO `, `WARN `, `ERROR`, `FATAL`.

## Tensions

- **stdout only**: Ideally WARN/ERROR/FATAL would go to stderr. SS lacks native stderr support. Acceptable tradeoff — users can redirect output at shell level.
- **No structured output**: JSON logging deferred. Plain text is sufficient for most use cases and avoids json.ss dependency.
