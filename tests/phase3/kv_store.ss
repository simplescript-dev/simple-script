function main() {
    const dbPath = "/tmp/ss_kv.txt"

    // Store entries as "key=value\n" format
    let db = ""

    // Set some values
    db = kvSet(db, "name", "Alice")
    db = kvSet(db, "age", "30")
    db = kvSet(db, "city", "Beijing")
    db = kvSet(db, "lang", "SimpleScript")

    // Save to file
    writeFile(dbPath, db)
    println(`Saved ${countEntries(db)} entries to ${dbPath}`)

    // Read back
    const loaded = readFile(dbPath)
    println(`Loaded: ${loaded.length()} bytes`)

    // Get values
    println(`name = ${kvGet(loaded, "name")}`)
    println(`age = ${kvGet(loaded, "age")}`)
    println(`city = ${kvGet(loaded, "city")}`)
    println(`lang = ${kvGet(loaded, "lang")}`)
    println(`missing = ${kvGet(loaded, "missing")}`)
}

function kvSet(db: string, key: string, value: string): string {
    return db + key + "=" + value + "\n"
}

function kvGet(db: string, key: string): string {
    const search = key + "="
    const pos = db.indexOf(search)
    if (pos == -1) {
        return "(not found)"
    }

    // Find the value after "key="
    const start = pos + search.length()
    const rest = db.substring(start, db.length() - start)

    // Find end of line
    const nl = rest.indexOf("\n")
    if (nl == -1) {
        return rest
    }
    return rest.substring(0, nl)
}

function countEntries(db: string): int {
    let count = 0
    const len = db.length()
    for (let i = 0; i < len; i++) {
        if (db.substring(i, 1) == "\n") {
            count = count + 1
        }
    }
    return count
}
