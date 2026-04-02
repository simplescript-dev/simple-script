// Jakarta Persistence API — SimpleScript Implementation
// File-based JSON storage (one .json file per table)
// Data directory: ./data/

// ── EntityManager ────────────────────────────────────────────

class EntityManager {
    dataDir: string

    function ensureDir() {
        mkdirp(this.dataDir)
    }

    function tablePath(table: string): string {
        return `${this.dataDir}/${table}.json`
    }

    function loadTable(table: string): string {
        this.ensureDir()
        const path = this.tablePath(table)
        if (fileExists(path) == 0) { return "[]" }
        const content = readFile(path)
        if (content == "") { return "[]" }
        return content
    }

    function saveTable(table: string, data: string) {
        this.ensureDir()
        writeFile(this.tablePath(table), data)
    }
}

function createEntityManager(): EntityManager {
    return new EntityManager("./data")
}
