function loadTodos(path: string): string {
    const db = Map()
    const content = readFile(path)
    if (content.length() == 0) { return db }

    let lineStart = 0
    const len = content.length()
    let id = 0

    for (let i = 0; i <= len; i++) {
        if (i == len || content.charAt(i) == "\n") {
            const line = content.substring(lineStart, i - lineStart)
            if (line.length() > 0) {
                id = id + 1
                db.set(id.toString(), line)
            }
            lineStart = i + 1
        }
    }
    return db
}

function saveTodos(path: string, db: string) {
    let content = ""
    const keys = db.keys()
    let keyStart = 0
    const klen = keys.length()

    for (let i = 0; i <= klen; i++) {
        if (i == klen || keys.charAt(i) == "\n") {
            const key = keys.substring(keyStart, i - keyStart)
            if (key.length() > 0) {
                const value = db.getString(key)
                content = content + value + "\n"
            }
            keyStart = i + 1
        }
    }
    writeFile(path, content)
}
