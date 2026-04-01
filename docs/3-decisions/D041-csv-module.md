# D041: CSV Standard Library Module

## Status
Implemented

## Depends On
None (pure library, no compiler changes)

## Decision
Add `lib/csv.ss` — an RFC 4180 compliant CSV parser and stringifier using the established static method pattern (`CSV.parse()`, `CSV.stringify()`), with a `CsvTable` wrapper class for data access.

## Reasoning
CSV is one of the most common data interchange formats. A standard library CSV module enables SimpleScript programs to import/export tabular data without manual string parsing. Following the existing stdlib pattern (json.ss, datetime.ss) ensures API consistency.

## Implementation

### Architecture
Map-based internal storage (same pattern as json.ss):
- `csvCells` Map: `"tableId:row:col"` → cell value
- `csvMeta` Map: `"tableId:rows"` → row count, `"tableId:cols"` → col count
- `csvNextId` counter for table IDs
- Lazy initialization via `csvInit()`

### CSV static methods (5)
| Method | Signature | Description |
|--------|-----------|-------------|
| `parse` | `(input: string): CsvTable` | Parse CSV with comma delimiter |
| `parseDelimited` | `(input: string, delimiter: string): CsvTable` | Parse with custom delimiter |
| `stringify` | `(table: CsvTable): string` | Serialize to CSV with comma |
| `stringifyDelimited` | `(table: CsvTable, delimiter: string): string` | Serialize with custom delimiter |
| `create` | `(): CsvTable` | Create empty table for programmatic building |

### CsvTable methods (8)
| Method | Signature | Description |
|--------|-----------|-------------|
| `rowCount` | `(): int` | Number of rows |
| `colCount` | `(): int` | Number of columns (maximum across rows) |
| `get` | `(row: int, col: int): string` | Get cell value |
| `set` | `(row: int, col: int, value: string)` | Set cell value |
| `getRow` | `(row: int): Array<string>` | Get all cells in a row |
| `headers` | `(): Array<string>` | Get first row (convenience for header access) |
| `getByName` | `(row: int, name: string): string` | Get cell by header name lookup |
| `addRow` | `(values: Array<string>)` | Append a new row |

### Parser features (RFC 4180)
- Comma-separated fields (configurable delimiter)
- Quoted fields: `"field with, comma"`
- Escaped quotes: `"field with ""quotes"""`
- Newlines within quoted fields (CRLF normalized to LF)
- CRLF and LF line endings
- Empty fields: `a,,c` → `["a", "", "c"]`
- Trailing newline does not create empty row

### Stringify features
- Auto-quoting: fields containing delimiter, `"`, `\n`, or `\r` are quoted
- Quote escaping: internal `"` → `""` per RFC 4180
- Each row terminated with `\n`

### Helper functions (internal, 11)
`csvInit`, `csvNewTable`, `csvSetCell`, `csvGetCell`, `csvGetRows`, `csvGetCols`, `csvSetMeta`, `csvParseImpl`, `csvNeedsQuote`, `csvEscapeField`, `csvStringifyImpl`

## Rejected Alternatives
- **Row-based Array<Array<string>>**: SS's type system doesn't easily support nested generic arrays. Map-based storage is simpler and matches json.ss pattern.
- **Streaming parser**: Overkill for typical CSV sizes. Character-by-character state machine is sufficient.
- **Class with mutable state for parser position**: Following json.ss's global-variable approach for consistency.

## Interfaces
- Import: `import { CSV, CsvTable } from "@/lib/csv"`
- No compiler changes required.

## Tensions
- None. Pure library addition.
