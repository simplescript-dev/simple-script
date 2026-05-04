// D152 Phase 3 — Blob / Clob / NClob interface dispatch test.
//
// Stub LOB impls model an in-memory string buffer. Real driver impls
// (MysqlBlob / MysqlClob backed by COM_QUERY ResultSet bytes) follow
// in a later D152 §Followup once the server-side LOB streaming protocol
// path is wired.
//
// See docs/3-decisions/D152-jdbc-type-class-foundation.md §Phase 3.

import { assertEqual } from "@/lib/test"
import { Blob, Clob, NClob } from "@/lib/java/sql"

class StubBlob : Blob {
    data: string

    function length(): int { return this.data.length() }
    // 1-based pos. SS substring(start, count) — second arg is count.
    function getBytes(pos: int, len: int): string {
        return this.data.substring(pos - 1, len)
    }
    function setBytes(pos: int, bytes: string): int {
        this.data = bytes
        return bytes.length()
    }
    function position(pattern: string, start: int): int {
        const tail = this.data.substring(start - 1, this.data.length())
        const idx = tail.indexOf(pattern)
        if (idx < 0) { return -1 }
        return idx + start
    }
    function truncate(len: int) {
        this.data = this.data.substring(0, len)
    }
    function free() { this.data = "" }
}

class StubClob : Clob {
    text: string

    function length(): int { return this.text.length() }
    function getSubString(pos: int, len: int): string {
        return this.text.substring(pos - 1, len)
    }
    function setString(pos: int, str: string): int {
        this.text = str
        return str.length()
    }
    function position(pattern: string, start: int): int {
        const tail = this.text.substring(start - 1, this.text.length())
        const idx = tail.indexOf(pattern)
        if (idx < 0) { return -1 }
        return idx + start
    }
    function truncate(len: int) {
        this.text = this.text.substring(0, len)
    }
    function free() { this.text = "" }
}

class StubNClob : NClob {
    text: string

    function length(): int { return this.text.length() }
    function getSubString(pos: int, len: int): string {
        return this.text.substring(pos - 1, len)
    }
    function setString(pos: int, str: string): int {
        this.text = str
        return str.length()
    }
    function position(pattern: string, start: int): int {
        const tail = this.text.substring(start - 1, this.text.length())
        const idx = tail.indexOf(pattern)
        if (idx < 0) { return -1 }
        return idx + start
    }
    function truncate(len: int) {
        this.text = this.text.substring(0, len)
    }
    function free() { this.text = "" }
}

function main() {
    test("Blob length + getBytes 1-based window", () => {
        const b = new StubBlob("Hello, World!")
        assertEqual(b.length(), 13)
        assertEqual(b.getBytes(1, 5), "Hello")
        assertEqual(b.getBytes(8, 5), "World")
    })

    test("Blob position pattern search 1-based, -1 not found", () => {
        const b = new StubBlob("Hello, World!")
        assertEqual(b.position("World", 1), 8)
        assertEqual(b.position("xyz", 1), -1)
    })

    test("Blob truncate + free", () => {
        const b = new StubBlob("Hello, World!")
        b.truncate(5)
        assertEqual(b.length(), 5)
        b.free()
        assertEqual(b.length(), 0)
    })

    test("Clob getSubString + setString chars-written", () => {
        const c = new StubClob("simplescript")
        assertEqual(c.length(), 12)
        assertEqual(c.getSubString(1, 6), "simple")
        assertEqual(c.setString(1, "ss"), 2)
        assertEqual(c.length(), 2)
    })

    test("NClob same surface as Clob (NCHAR/NVARCHAR)", () => {
        const n = new StubNClob("simplescript")
        assertEqual(n.getSubString(1, 6), "simple")
        assertEqual(n.setString(1, "abc"), 3)
        assertEqual(n.length(), 3)
    })
}
