// D152 Phase 5 — Cross-interface chained call integration test.
//
// Verifies the LOB → Stream chained dispatch end-to-end:
//   blob.getBinaryStream() → InputStream.readN(N)
//   clob.getCharacterStream() → Reader.readN(N)
//   nclob.getCharacterStream() → Reader.read()
//   sqlxml.getBinaryStream() / getCharacterStream() → readN(N)
//
// Stub LOBs hold an in-memory string and hand out MemoryInputStream
// / MemoryReader views over the same payload. The point is to exercise
// two interface vtable dispatches in sequence — Blob → InputStream and
// Clob/NClob/SQLXML → Reader — through the same chained call path that
// real driver impls (MysqlBlob → MysqlBlobInputStream backed by the
// COM_QUERY ResultSet bytes) will follow in a later D152 §F sub-D.
//
// See docs/3-decisions/D152-jdbc-type-class-foundation.md §Phase 5.

import { assertEqual } from "@/lib/test"
import { Blob, Clob, NClob, SQLXML } from "@/lib/java/sql"
import { InputStream, Reader } from "@/lib/java/io"

// In-memory backing stream stubs used as the chained-call target.

class MemoryInputStream : InputStream {
    data: string
    pos: int

    function read(): int {
        if (this.pos >= this.data.length()) { return -1 }
        const b = this.data.charCodeAt(this.pos)
        this.pos = this.pos + 1
        return b
    }
    function readN(len: int): string {
        const remaining = this.data.length() - this.pos
        let take = len
        if (len > remaining) { take = remaining }
        const chunk = this.data.substring(this.pos, take)
        this.pos = this.pos + take
        return chunk
    }
    function skip(n: int): int {
        const remaining = this.data.length() - this.pos
        let take = n
        if (n > remaining) { take = remaining }
        this.pos = this.pos + take
        return take
    }
    function available(): int { return this.data.length() - this.pos }
    function close() { this.pos = this.data.length() }
    function mark(readlimit: int) {}
    function reset() { this.pos = 0 }
    function markSupported(): int { return 1 }
}

class MemoryReader : Reader {
    text: string
    pos: int

    function read(): int {
        if (this.pos >= this.text.length()) { return -1 }
        const c = this.text.charCodeAt(this.pos)
        this.pos = this.pos + 1
        return c
    }
    function readN(len: int): string {
        const remaining = this.text.length() - this.pos
        let take = len
        if (len > remaining) { take = remaining }
        const chunk = this.text.substring(this.pos, take)
        this.pos = this.pos + take
        return chunk
    }
    function skip(n: int): int {
        const remaining = this.text.length() - this.pos
        let take = n
        if (n > remaining) { take = remaining }
        this.pos = this.pos + take
        return take
    }
    function ready(): int {
        if (this.pos < this.text.length()) { return 1 }
        return 0
    }
    function close() { this.pos = this.text.length() }
    function mark(readlimit: int) {}
    function reset() { this.pos = 0 }
    function markSupported(): int { return 1 }
}

// Chained LOB stubs return Memory{InputStream,Reader} on demand —
// each call yields a fresh independent cursor (matches JDK semantics
// where Blob.getBinaryStream() returns a new ByteArrayInputStream view).

class ChainedBlob : Blob {
    payload: string

    function length(): int { return this.payload.length() }
    function getBytes(pos: int, len: int): string {
        return this.payload.substring(pos - 1, len)
    }
    function setBytes(pos: int, bytes: string): int {
        this.payload = bytes
        return bytes.length()
    }
    function position(pattern: string, start: int): int { return -1 }
    function truncate(len: int) {
        this.payload = this.payload.substring(0, len)
    }
    function getBinaryStream(): InputStream {
        return new MemoryInputStream(this.payload, 0)
    }
    function free() { this.payload = "" }
}

class ChainedClob : Clob {
    body: string

    function length(): int { return this.body.length() }
    function getSubString(pos: int, len: int): string {
        return this.body.substring(pos - 1, len)
    }
    function setString(pos: int, str: string): int {
        this.body = str
        return str.length()
    }
    function position(pattern: string, start: int): int { return -1 }
    function truncate(len: int) {
        this.body = this.body.substring(0, len)
    }
    function getCharacterStream(): Reader {
        return new MemoryReader(this.body, 0)
    }
    function free() { this.body = "" }
}

class ChainedNClob : NClob {
    body: string

    function length(): int { return this.body.length() }
    function getSubString(pos: int, len: int): string {
        return this.body.substring(pos - 1, len)
    }
    function setString(pos: int, str: string): int {
        this.body = str
        return str.length()
    }
    function position(pattern: string, start: int): int { return -1 }
    function truncate(len: int) {
        this.body = this.body.substring(0, len)
    }
    function getCharacterStream(): Reader {
        return new MemoryReader(this.body, 0)
    }
    function free() { this.body = "" }
}

class ChainedSQLXML : SQLXML {
    xml: string

    function getString(): string { return this.xml }
    function setString(value: string) { this.xml = value }
    function getBinaryStream(): InputStream {
        return new MemoryInputStream(this.xml, 0)
    }
    function getCharacterStream(): Reader {
        return new MemoryReader(this.xml, 0)
    }
    function free() { this.xml = "" }
}

function main() {
    test("Blob.getBinaryStream → InputStream.readN end-to-end", () => {
        const b = new ChainedBlob("Hello, World!")
        const is = b.getBinaryStream()
        assertEqual(is.readN(5), "Hello")
        assertEqual(is.readN(7), ", World")
        assertEqual(is.readN(100), "!")
        assertEqual(is.readN(1), "")
    })

    test("Clob.getCharacterStream → Reader.readN end-to-end", () => {
        const c = new ChainedClob("simplescript")
        const r = c.getCharacterStream()
        assertEqual(r.readN(6), "simple")
        assertEqual(r.readN(100), "script")
        assertEqual(r.ready(), 0)
    })

    test("NClob.getCharacterStream → Reader.read codepoint loop", () => {
        const n = new ChainedNClob("ABC")
        const r = n.getCharacterStream()
        assertEqual(r.read(), 65)
        assertEqual(r.read(), 66)
        assertEqual(r.read(), 67)
        assertEqual(r.read(), -1)
    })

    test("SQLXML.getBinaryStream + getCharacterStream both wired", () => {
        const x = new ChainedSQLXML("<root/>")
        const is = x.getBinaryStream()
        assertEqual(is.readN(7), "<root/>")
        const r = x.getCharacterStream()
        assertEqual(r.readN(7), "<root/>")
    })

    test("Blob → InputStream skip + readN + available", () => {
        const b = new ChainedBlob("Hello, World!")
        const is = b.getBinaryStream()
        assertEqual(is.skip(7), 7)
        assertEqual(is.readN(5), "World")
        assertEqual(is.available(), 1)
    })

    test("Two getBinaryStream calls return independent cursors", () => {
        const b = new ChainedBlob("ABCDEF")
        const isA = b.getBinaryStream()
        const isB = b.getBinaryStream()
        assertEqual(isA.readN(3), "ABC")
        assertEqual(isB.readN(3), "ABC")
        assertEqual(isA.readN(3), "DEF")
        assertEqual(isB.available(), 3)
    })
}
