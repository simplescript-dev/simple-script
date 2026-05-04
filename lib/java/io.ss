// java.io — InputStream / Reader byte/character stream interfaces
// Mirrors: java.io.InputStream + java.io.Reader
//
// Used by JDBC LOB types — Blob.getBinaryStream / SQLXML.getBinaryStream
// return InputStream; Clob.getCharacterStream / NClob.getCharacterStream
// / SQLXML.getCharacterStream return Reader.
//
// Stream protocol: read() returns the next unit advancing position.
//   InputStream.read() → next byte 0..255 or -1 on EOF
//   Reader.read()      → next char codepoint or -1 on EOF
//
// SS uses int for boolean returns (markSupported / ready) — D135/D136
// established convention prior to a native bool primitive.
//
// AsciiStream / BinaryStream are JDBC method-name aliases for
// InputStream; CharacterStream / NCharacterStream are aliases for
// Reader. JDK does not declare separate interfaces — neither does
// this file (D152 §A.1.1 G2 estimate revised: alias interfaces are
// not part of JDK java.io and are not needed here).
//
// readN(len) reads up to len bytes/chars and returns them as a
// string (matching JDK 11+ readNBytes semantics, adapted for SS
// where strings stand in for byte[] / char[]). At EOF readN returns
// a shorter string; an empty string means EOF.
//
// See docs/3-decisions/D152-jdbc-type-class-foundation.md §Phase 4.

// ── InputStream — java.io.InputStream ────────────────────────
// Byte-oriented stream. read() returns the next unsigned byte 0..255
// or -1 on EOF. readN(len) reads up to len bytes (JDK 11+ readNBytes).
// skip / available are blocking-aware.
//
// mark / reset / markSupported model the bookmark facility. Drivers
// without backing buffers return markSupported() = 0; calling reset()
// on such a stream is a caller error and impls return -1 from the
// next read() to signal "no mark set" rather than throwing IOException
// (SS lacks a JDK exception hierarchy on streams; D136 §A.5).

interface InputStream {
    function read(): int
    function readN(len: int): string
    function skip(n: int): int
    function available(): int
    function close()
    function mark(readlimit: int)
    function reset()
    function markSupported(): int
}

// ── Reader — java.io.Reader ──────────────────────────────────
// Character-oriented stream. read() returns the next char codepoint
// or -1 on EOF. ready() returns 1 if read() will not block, 0
// otherwise. readN(len) reads up to len chars. mark / reset semantics
// mirror InputStream.

interface Reader {
    function read(): int
    function readN(len: int): string
    function skip(n: int): int
    function ready(): int
    function close()
    function mark(readlimit: int)
    function reset()
    function markSupported(): int
}
