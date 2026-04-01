// SimpleScript CSV Library — RFC 4180 compliant parser/stringifier
//
// Usage:
//   import { CSV, CsvTable } from "@/lib/csv"
//
//   // Parse
//   const table = CSV.parse("name,age\nAlice,30\nBob,25")
//   table.rowCount()             // 3
//   table.get(1, 0)              // "Alice"
//   table.getByName(1, "name")   // "Alice"
//
//   // Stringify
//   CSV.stringify(table)          // "name,age\nAlice,30\nBob,25\n"
//
//   // Build from scratch
//   const t = CSV.create()
//   t.addRow(["name", "age"])
//   t.addRow(["Alice", "30"])
//   CSV.stringify(t)              // "name,age\nAlice,30\n"

// ── Internal storage ─────────────────────────────────────────

let csvCells = ""
let csvMeta = ""
let csvNextId = 1
let csvReady = 0

function csvInit() {
    if (csvReady == 1) { return }
    csvCells = new Map()
    csvMeta = new Map()
    csvReady = 1
}

function csvNewTable(): int {
    csvInit()
    const id = csvNextId
    csvNextId = csvNextId + 1
    csvMeta.set(`${id}:rows`, "0")
    csvMeta.set(`${id}:cols`, "0")
    return id
}

function csvSetCell(tid: int, row: int, col: int, val: string) {
    csvCells.set(`${tid}:${row}:${col}`, val)
}

function csvGetCell(tid: int, row: int, col: int): string {
    const key = `${tid}:${row}:${col}`
    if (csvCells.has(key) == 0) { return "" }
    return csvCells.getString(key)
}

function csvGetRows(tid: int): int {
    return parseInt(csvMeta.getString(`${tid}:rows`))
}

function csvGetCols(tid: int): int {
    return parseInt(csvMeta.getString(`${tid}:cols`))
}

function csvSetMeta(tid: int, rows: int, cols: int) {
    csvMeta.set(`${tid}:rows`, `${rows}`)
    csvMeta.set(`${tid}:cols`, `${cols}`)
}

// ── CsvTable class ───────────────────────────────────────────

class CsvTable(tableId: int) {
    function rowCount(): int {
        return csvGetRows(this.tableId)
    }

    function colCount(): int {
        return csvGetCols(this.tableId)
    }

    function get(row: int, col: int): string {
        return csvGetCell(this.tableId, row, col)
    }

    function set(row: int, col: int, value: string) {
        csvSetCell(this.tableId, row, col, value)
    }

    function getRow(row: int): Array<string> {
        const cols = this.colCount()
        let result: Array<string> = []
        let c = 0
        while (c < cols) {
            result = result.push(this.get(row, c))
            c = c + 1
        }
        return result
    }

    function headers(): Array<string> {
        return this.getRow(0)
    }

    function getByName(row: int, name: string): string {
        const cols = this.colCount()
        let c = 0
        while (c < cols) {
            if (csvGetCell(this.tableId, 0, c) == name) {
                return this.get(row, c)
            }
            c = c + 1
        }
        return ""
    }

    function addRow(values: Array<string>) {
        const row = this.rowCount()
        const len = values.length()
        let c = 0
        while (c < len) {
            csvSetCell(this.tableId, row, c, values[c])
            c = c + 1
        }
        const currentCols = this.colCount()
        if (len > currentCols) {
            csvSetMeta(this.tableId, row + 1, len)
        } else {
            csvSetMeta(this.tableId, row + 1, currentCols)
        }
    }
}

// ── CSV class (static methods) ───────────────────────────────

class CSV()

// ── Parse implementation ─────────────────────────────────────

function csvParseImpl(input: string, delim: string): CsvTable {
    const tid = csvNewTable()
    const len = input.length()
    if (len == 0) {
        return new CsvTable(tid)
    }

    let row = 0
    let col = 0
    let maxCol = 0
    let pos = 0
    let field = ""
    let inQuoted = 0

    while (pos < len) {
        const ch = input.charAt(pos)

        if (inQuoted == 1) {
            if (ch == "\"") {
                if (pos + 1 < len && input.charAt(pos + 1) == "\"") {
                    field = field + "\""
                    pos = pos + 2
                } else {
                    inQuoted = 0
                    pos = pos + 1
                }
            } else if (ch == "\r" && pos + 1 < len && input.charAt(pos + 1) == "\n") {
                field = field + "\n"
                pos = pos + 2
            } else {
                field = field + ch
                pos = pos + 1
            }
        } else {
            if (ch == "\"" && field.length() == 0) {
                inQuoted = 1
                pos = pos + 1
            } else if (ch == delim) {
                csvSetCell(tid, row, col, field)
                field = ""
                col = col + 1
                if (col > maxCol) { maxCol = col }
                pos = pos + 1
            } else if (ch == "\n") {
                csvSetCell(tid, row, col, field)
                if (col > maxCol) { maxCol = col }
                field = ""
                row = row + 1
                col = 0
                pos = pos + 1
            } else if (ch == "\r") {
                csvSetCell(tid, row, col, field)
                if (col > maxCol) { maxCol = col }
                field = ""
                row = row + 1
                col = 0
                pos = pos + 1
                if (pos < len && input.charAt(pos) == "\n") {
                    pos = pos + 1
                }
            } else {
                field = field + ch
                pos = pos + 1
            }
        }
    }

    if (field.length() > 0 || col > 0) {
        csvSetCell(tid, row, col, field)
        if (col > maxCol) { maxCol = col }
        row = row + 1
    }

    csvSetMeta(tid, row, maxCol + 1)
    return new CsvTable(tid)
}

function CSV_parse(input: string): CsvTable {
    return csvParseImpl(input, ",")
}

function CSV_parseDelimited(input: string, delimiter: string): CsvTable {
    return csvParseImpl(input, delimiter)
}

// ── Create empty table ───────────────────────────────────────

function CSV_create(): CsvTable {
    const tid = csvNewTable()
    return new CsvTable(tid)
}

// ── Stringify implementation ─────────────────────────────────

function csvNeedsQuote(value: string, delim: string): int {
    const len = value.length()
    let i = 0
    while (i < len) {
        const ch = value.charAt(i)
        if (ch == delim || ch == "\"" || ch == "\n" || ch == "\r") {
            return 1
        }
        i = i + 1
    }
    return 0
}

function csvEscapeField(value: string, delim: string): string {
    if (csvNeedsQuote(value, delim) == 0) {
        return value
    }
    let result = "\""
    const len = value.length()
    let i = 0
    while (i < len) {
        const ch = value.charAt(i)
        if (ch == "\"") {
            result = result + "\"\""
        } else {
            result = result + ch
        }
        i = i + 1
    }
    return result + "\""
}

function csvStringifyImpl(table: CsvTable, delim: string): string {
    let result = ""
    const rows = table.rowCount()
    const cols = table.colCount()
    let r = 0
    while (r < rows) {
        let c = 0
        while (c < cols) {
            if (c > 0) { result = result + delim }
            result = result + csvEscapeField(table.get(r, c), delim)
            c = c + 1
        }
        result = result + "\n"
        r = r + 1
    }
    return result
}

function CSV_stringify(table: CsvTable): string {
    return csvStringifyImpl(table, ",")
}

function CSV_stringifyDelimited(table: CsvTable, delimiter: string): string {
    return csvStringifyImpl(table, delimiter)
}
