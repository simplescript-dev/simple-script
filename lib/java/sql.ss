// java.sql — JDBC 4.3 Core Interfaces (SimpleScript Implementation)
// Mirrors: java.sql.Connection, Statement, PreparedStatement, ResultSet, DriverManager
// This module defines the JDBC abstraction. Drivers provide concrete implementations.

// ── ResultSet ────────────────────────────────────────────────
// Wraps a query result. Internal: rows stored as "col1\tcol2\n" per row.

class ResultSet {
    data: string
    columns: string
    rowCount: int
    currentRow: int

    function next(): int {
        if (this.currentRow >= this.rowCount) { return 0 }
        return 1
    }

    function getString(columnLabel: string): string {
        return rsGetValue(this.data, this.columns, this.currentRow, columnLabel)
    }

    function getInt(columnLabel: string): int {
        const val = this.getString(columnLabel)
        if (val == "") { return 0 }
        return parseInt(val)
    }

    function getLong(columnLabel: string): int {
        return this.getInt(columnLabel)
    }

    function getDouble(columnLabel: string): double {
        const val = this.getString(columnLabel)
        if (val == "") { return 0.0 }
        return parseDouble(val)
    }

    function getBoolean(columnLabel: string): int {
        const val = this.getString(columnLabel)
        return val == "1" || val == "true" ? 1 : 0
    }

    function close() {
        // No-op for now
    }
}

// Advance row pointer (returns new ResultSet with incremented row)
function rsNext(rs: ResultSet): ResultSet {
    return new ResultSet(rs.data, rs.columns, rs.rowCount, rs.currentRow + 1)
}

// Internal: extract value from tab-separated row data
function rsGetValue(data: string, columns: string, row: int, colLabel: string): string {
    // Find column index
    let colIdx = -1
    let ci = 0
    let remaining = columns
    while (remaining != "") {
        let col = remaining
        const tabIdx = remaining.indexOf("\t")
        if (tabIdx >= 0) {
            col = remaining.substring(0, tabIdx)
            remaining = remaining.substring(tabIdx + 1, remaining.length() - tabIdx - 1)
        } else {
            remaining = ""
        }
        if (col == colLabel) { colIdx = ci; break }
        ci = ci + 1
    }
    if (colIdx < 0) { return "" }

    // Find row
    let ri = 0
    let rowRemaining = data
    while (ri <= row && rowRemaining != "") {
        let rowStr = rowRemaining
        const nlIdx = rowRemaining.indexOf("\n")
        if (nlIdx >= 0) {
            rowStr = rowRemaining.substring(0, nlIdx)
            rowRemaining = rowRemaining.substring(nlIdx + 1, rowRemaining.length() - nlIdx - 1)
        } else {
            rowRemaining = ""
        }
        if (ri == row) {
            // Extract column value from tab-separated row
            let vi = 0
            let valRemaining = rowStr
            while (vi <= colIdx && valRemaining != "") {
                let val = valRemaining
                const vtIdx = valRemaining.indexOf("\t")
                if (vtIdx >= 0) {
                    val = valRemaining.substring(0, vtIdx)
                    valRemaining = valRemaining.substring(vtIdx + 1, valRemaining.length() - vtIdx - 1)
                } else {
                    valRemaining = ""
                }
                if (vi == colIdx) { return val }
                vi = vi + 1
            }
        }
        ri = ri + 1
    }
    return ""
}

// ── Statement ────────────────────────────────────────────────
// Placeholder — actual implementation in driver

class Statement {
    dbHandle: string

    function executeQuery(sql: string): ResultSet {
        return stmtExecuteQuery(this.dbHandle, sql)
    }

    function executeUpdate(sql: string): int {
        return stmtExecuteUpdate(this.dbHandle, sql)
    }

    function execute(sql: string): int {
        return stmtExecuteUpdate(this.dbHandle, sql)
    }

    function close() {
        // No-op
    }
}

// ── Connection ───────────────────────────────────────────────

class Connection {
    dbHandle: string
    url: string
    closed: int

    function createStatement(): Statement {
        return new Statement(this.dbHandle)
    }

    function setAutoCommit(auto: int) {
        if (auto == 0) {
            stmtExecuteUpdate(this.dbHandle, "BEGIN")
        }
    }

    function commit() {
        stmtExecuteUpdate(this.dbHandle, "COMMIT")
    }

    function rollback() {
        stmtExecuteUpdate(this.dbHandle, "ROLLBACK")
    }

    function close() {
        ss_sqlite3_close(this.dbHandle)
    }

    function isClosed(): int {
        return this.closed
    }
}

// ── DriverManager ────────────────────────────────────────────

class DriverManager

function DriverManager_getConnection(url: string): Connection {
    let dbPath = url
    if (url.startsWith("jdbc:sqlite:") == 1) {
        dbPath = url.substring(12, url.length() - 12)
    } else if (url.startsWith("sqlite:") == 1) {
        dbPath = url.substring(7, url.length() - 7)
    }
    const dbHandle = ss_sqlite3_open(dbPath)
    if (dbHandle == "") {
        println(`JDBC: failed to open database: ${dbPath}`)
        exit(1)
    }
    return new Connection(dbHandle, url, 0)
}

// ── SQLite native bindings (declared in gen_runtime.ss) ──────
// These are thin wrappers around sqlite3 C API.
// ss_sqlite3_open(path) → db pointer (as int)
// ss_sqlite3_close(db)
// ss_sqlite3_exec(db, sql) → 0 on success
// ss_sqlite3_query(db, sql) → "col1\tcol2\nval1\tval2\n..." result string

function stmtExecuteQuery(dbHandle: string, sql: string): ResultSet {
    const raw = ss_sqlite3_query(dbHandle, sql)
    // First line is column headers, rest is data
    const nlIdx = raw.indexOf("\n")
    if (nlIdx < 0) { return new ResultSet("", "", 0, 0) }
    const columns = raw.substring(0, nlIdx)
    const data = raw.substring(nlIdx + 1, raw.length() - nlIdx - 1)
    // Count rows
    let rows = 0
    if (data != "") {
        rows = 1
        let di = 0
        while (di < data.length()) {
            if (data.charAt(di) == "\n") { rows = rows + 1 }
            di = di + 1
        }
        // Don't count trailing newline as extra row
        if (data.charAt(data.length() - 1) == "\n") { rows = rows - 1 }
    }
    return new ResultSet(data, columns, rows, 0)
}

function stmtExecuteUpdate(dbHandle: string, sql: string): int {
    return ss_sqlite3_exec(dbHandle, sql)
}
