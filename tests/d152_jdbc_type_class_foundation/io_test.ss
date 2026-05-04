// D152 Phase 4 — InputStream / Reader interface dispatch test.
//
// Stub stream impls model an in-memory string buffer with cursor.
// Real driver stream impls (MysqlBlobInputStream / MysqlClobReader
// backed by socket buffer or Connector/J streaming cursor) follow
// in a later D152 §Followup once the server-side LOB streaming
// protocol path is wired.
//
// See docs/3-decisions/D152-jdbc-type-class-foundation.md §Phase 4.

import { assertEqual } from "@/lib/test"
import { InputStream, Reader } from "@/lib/java/io"

class StubInputStream : InputStream {
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
    function available(): int {
        return this.data.length() - this.pos
    }
    function close() { this.pos = this.data.length() }
    function mark(readlimit: int) { /* no-op stub */ }
    function reset() { this.pos = 0 }
    function markSupported(): int { return 1 }
}

class StubReader : Reader {
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
    function mark(readlimit: int) { /* no-op stub */ }
    function reset() { this.pos = 0 }
    function markSupported(): int { return 1 }
}

function main() {
    test("InputStream read advances byte-by-byte with EOF", () => {
        const s = new StubInputStream("ABC", 0)
        assertEqual(s.read(), 65)
        assertEqual(s.read(), 66)
        assertEqual(s.read(), 67)
        assertEqual(s.read(), -1)
    })

    test("InputStream readN window + EOF short read", () => {
        const s = new StubInputStream("Hello, World!", 0)
        assertEqual(s.readN(5), "Hello")
        assertEqual(s.readN(2), ", ")
        assertEqual(s.readN(100), "World!")
        assertEqual(s.readN(1), "")
    })

    test("InputStream skip + available clamp at EOF", () => {
        const s = new StubInputStream("Hello", 0)
        assertEqual(s.available(), 5)
        assertEqual(s.skip(3), 3)
        assertEqual(s.available(), 2)
        assertEqual(s.skip(100), 2)
        assertEqual(s.available(), 0)
    })

    test("InputStream mark/reset round-trip + markSupported", () => {
        const s = new StubInputStream("ABCD", 0)
        s.mark(0)
        assertEqual(s.read(), 65)
        assertEqual(s.read(), 66)
        s.reset()
        assertEqual(s.read(), 65)
        assertEqual(s.markSupported(), 1)
    })

    test("Reader read returns char codepoints with EOF", () => {
        const r = new StubReader("Xyz", 0)
        assertEqual(r.read(), 88)
        assertEqual(r.read(), 121)
        assertEqual(r.read(), 122)
        assertEqual(r.read(), -1)
    })

    test("Reader ready + readN + skip end-to-end", () => {
        const r = new StubReader("simplescript", 0)
        assertEqual(r.ready(), 1)
        assertEqual(r.readN(6), "simple")
        assertEqual(r.skip(3), 3)
        assertEqual(r.readN(100), "ipt")
        assertEqual(r.ready(), 0)
    })
}
