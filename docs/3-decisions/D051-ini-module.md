# D051: INI Module — Config File Parser and Stringifier

**Status:** Accepted
**Depends on:** None (self-contained, pure string processing)

## Decision

Add `lib/ini.ss` — a pure SS INI configuration file parser and stringifier with section/key/value access, mutation, and removal.

## Reasoning

INI is a ubiquitous config format that is simple to parse (line-based, no nesting beyond sections). A standard module enables SS programs to read/write `.ini` and `.cfg` files without manual string parsing.

1. **Parse/stringify** — bidirectional: INI text to structured data and back
2. **Section + key access** — `get`, `set`, `hasSection`, `hasKey`, `sections`, `keys`
3. **Mutation** — modify values, add new sections/keys, remove keys
4. **Global section** — keys before any `[section]` header stored under `""` section
5. **Zero dependencies** — self-contained, no imports from other lib modules

## Design

Uses the same global Map-based storage pattern as csv.ss:
- `iniStore` Map: values keyed by `"${id}:v:${section}:${key}"`
- `iniMeta` Map: metadata (section/key counts, existence flags, indexed names)
- Integer table IDs allow multiple independent IniData instances
- Avoids `Map.keys()` on function parameters (known compiler limitation)

Key removal uses sentinel-flag approach: has-flag set to "0" instead of Map.delete(), allowing re-addition of removed keys without index duplication.

## Rejected Alternatives

- **Nested Map<string, Map<string, string>>**: SS Map.keys() is unreliable on function params. Flat composite-key Map avoids this.
- **Parallel arrays for storage**: More complex API. Map-based storage is simpler and matches csv.ss pattern.
- **Inline comments**: Ambiguous (`;` in values). Only full-line comments supported for simplicity.
- **Multiline values**: Non-standard INI extension. Single-line values only.
- **Quoted values**: Would add parser complexity. Values are literal strings (trimmed).

## Interfaces

### Import
```
import { Ini, IniData } from "@/lib/ini"
```

### IniData Instance Methods (7)
- `get(section: string, key: string): string` — get value (empty string if not found)
- `set(section: string, key: string, value: string)` — set or update value
- `hasSection(section: string): int` — 1 if section exists
- `hasKey(section: string, key: string): int` — 1 if key exists (and not removed)
- `sections(): Array<string>` — list all section names
- `keys(section: string): Array<string>` — list active keys in section
- `remove(section: string, key: string)` — remove a key

### Ini Static Methods (3)
- `Ini.parse(text: string): IniData` — parse INI text
- `Ini.stringify(data: IniData): string` — format as INI text
- `Ini.create(): IniData` — create empty IniData

### Internal Helpers (8)
- `iniInit`, `iniNewId`, `iniEnsureSection`, `iniSetValue`, `iniGetValue`
- `iniHasSec`, `iniHasKey`, `iniRemoveKey`
- `iniSectionCount`, `iniSectionAt`, `iniKeyCount`, `iniKeyAt`

### Module Globals (4)
- `iniStore`, `iniMeta` — Map-based storage (initialized lazily)
- `iniNextId` — table ID counter
- `iniReady` — lazy init flag

## Parse Rules

1. Lines starting with `;` or `#` are comments (skipped)
2. Empty lines are skipped
3. `[name]` is a section header
4. `key = value` is a key-value pair (split on first `=`, both sides trimmed)
5. Keys before any section header belong to the global section `""`
6. `\r\n` line endings handled (trailing `\r` stripped)

## Stringify Format

```
key = value

[section1]
key1 = value1
key2 = value2

[section2]
key3 = value3
```

Global keys (section `""`) appear first without header. Blank line between sections.

## Tensions

- **Section/key names with `:`**: Composite Map keys use `:` separator. Names containing `:` may collide. Standard INI names don't contain `:`.
- **Empty sections in stringify**: Sections with all keys removed are omitted from output.
