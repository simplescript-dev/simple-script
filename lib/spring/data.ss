// Spring Data JPA — SimpleScript Implementation
// JpaRepository with auto-generated CRUD operations
// Storage: JSON files via EntityManager

import { EntityManager, createEntityManager } from "@/lib/jakarta/persistence"
import { JSON, JsonNode } from "@/lib/json"

// ── JpaRepository ────────────────────────────────────────────
// File-based repository. Each entity stored as JSON in ./data/<table>.json
// Format: array of JSON objects, each with an "id" field

class JpaRepository(tableName: string, em: EntityManager) {

    // Save entity (create or update). Returns the saved JSON string.
    function save(entity: string): string {
        const data = this.em.loadTable(this.tableName)
        const parsed = JSON.parse(entity)
        let id = parsed.getInt("id")

        if (id == 0) {
            // Auto-generate ID: find max ID + 1
            id = this.nextId()
            // Prepend id to entity JSON
            const withId = `{"id":${id},${entity.substring(1, entity.length() - 1)}`
            this.appendRecord(withId)
            return withId
        }

        // Update existing: replace record with same ID
        this.replaceRecord(id, entity)
        return entity
    }

    // Find by ID. Returns JSON string or "" if not found.
    function findById(id: int): string {
        const records = this.em.loadTable(this.tableName)
        return this.findRecordById(records, id)
    }

    // Find all. Returns JSON array string.
    function findAll(): string {
        return this.em.loadTable(this.tableName)
    }

    // Check if exists by ID.
    function existsById(id: int): int {
        const record = this.findById(id)
        return record != "" ? 1 : 0
    }

    // Count all records.
    function count(): int {
        const data = this.em.loadTable(this.tableName)
        if (data == "[]") { return 0 }
        let cnt = 1
        let i = 0
        let depth = 0
        while (i < data.length()) {
            const ch = data.charAt(i)
            if (ch == "{") { depth = depth + 1 }
            if (ch == "}") { depth = depth - 1 }
            if (ch == "," && depth == 1) { cnt = cnt + 1 }
            i = i + 1
        }
        return cnt
    }

    // Delete by ID.
    function deleteById(id: int) {
        const data = this.em.loadTable(this.tableName)
        let result = "["
        let first = 1
        let remaining = data.substring(1, data.length() - 2)
        while (remaining != "") {
            let record = ""
            let depth = 0
            let end = 0
            let ri = 0
            while (ri < remaining.length()) {
                const ch = remaining.charAt(ri)
                if (ch == "{") { depth = depth + 1 }
                if (ch == "}") {
                    depth = depth - 1
                    if (depth == 0) { end = ri + 1; break }
                }
                ri = ri + 1
            }
            record = remaining.substring(0, end)
            if (end < remaining.length() && remaining.charAt(end) == ",") {
                remaining = remaining.substring(end + 1, remaining.length() - end - 1)
            } else {
                remaining = ""
            }
            if (record != "") {
                const recParsed = JSON.parse(record)
                if (recParsed.getInt("id") != id) {
                    if (first == 1) { first = 0 } else { result = `${result},` }
                    result = `${result}${record}`
                }
            }
        }
        result = `${result}]`
        this.em.saveTable(this.tableName, result)
    }

    // Delete all records.
    function deleteAll() {
        this.em.saveTable(this.tableName, "[]")
    }

    // ── Internal helpers ─────────────────────────────────────

    function nextId(): int {
        const data = this.em.loadTable(this.tableName)
        if (data == "[]") { return 1 }
        let maxId = 0
        let remaining = data.substring(1, data.length() - 2)
        while (remaining != "") {
            let depth = 0
            let end = 0
            let ri = 0
            while (ri < remaining.length()) {
                const ch = remaining.charAt(ri)
                if (ch == "{") { depth = depth + 1 }
                if (ch == "}") {
                    depth = depth - 1
                    if (depth == 0) { end = ri + 1; break }
                }
                ri = ri + 1
            }
            const record = remaining.substring(0, end)
            if (end < remaining.length() && remaining.charAt(end) == ",") {
                remaining = remaining.substring(end + 1, remaining.length() - end - 1)
            } else {
                remaining = ""
            }
            if (record != "") {
                const rec = JSON.parse(record)
                const recId = rec.getInt("id")
                if (recId > maxId) { maxId = recId }
            }
        }
        return maxId + 1
    }

    function appendRecord(record: string) {
        const data = this.em.loadTable(this.tableName)
        if (data == "[]") {
            this.em.saveTable(this.tableName, `[${record}]`)
        } else {
            const inner = data.substring(1, data.length() - 2)
            this.em.saveTable(this.tableName, `[${inner},${record}]`)
        }
    }

    function replaceRecord(id: int, newRecord: string) {
        const data = this.em.loadTable(this.tableName)
        let result = "["
        let first = 1
        let found = 0
        let remaining = data.substring(1, data.length() - 2)
        while (remaining != "") {
            let depth = 0
            let end = 0
            let ri = 0
            while (ri < remaining.length()) {
                const ch = remaining.charAt(ri)
                if (ch == "{") { depth = depth + 1 }
                if (ch == "}") {
                    depth = depth - 1
                    if (depth == 0) { end = ri + 1; break }
                }
                ri = ri + 1
            }
            let record = remaining.substring(0, end)
            if (end < remaining.length() && remaining.charAt(end) == ",") {
                remaining = remaining.substring(end + 1, remaining.length() - end - 1)
            } else {
                remaining = ""
            }
            if (record != "") {
                const recParsed = JSON.parse(record)
                if (recParsed.getInt("id") == id) {
                    record = newRecord
                    found = 1
                }
                if (first == 1) { first = 0 } else { result = `${result},` }
                result = `${result}${record}`
            }
        }
        result = `${result}]`
        this.em.saveTable(this.tableName, result)
    }

    function findRecordById(data: string, id: int): string {
        if (data == "[]") { return "" }
        let remaining = data.substring(1, data.length() - 2)
        while (remaining != "") {
            let depth = 0
            let end = 0
            let ri = 0
            while (ri < remaining.length()) {
                const ch = remaining.charAt(ri)
                if (ch == "{") { depth = depth + 1 }
                if (ch == "}") {
                    depth = depth - 1
                    if (depth == 0) { end = ri + 1; break }
                }
                ri = ri + 1
            }
            const record = remaining.substring(0, end)
            if (end < remaining.length() && remaining.charAt(end) == ",") {
                remaining = remaining.substring(end + 1, remaining.length() - end - 1)
            } else {
                remaining = ""
            }
            if (record != "") {
                const rec = JSON.parse(record)
                if (rec.getInt("id") == id) { return record }
            }
        }
        return ""
    }
}

// ── Factory ──────────────────────────────────────────────────

function JpaRepository_create(tableName: string): JpaRepository {
    return new JpaRepository(tableName, createEntityManager())
}
