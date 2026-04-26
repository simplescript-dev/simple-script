// MySQL JDBC driver — D134 Phase 5.
//
// class MysqlConnection : Connection and class MysqlStatement : Statement
// implement the lib/java/sql.ss D025 interfaces. ResultSet is implemented by
// class MysqlResultSet in lib/com/mysql/query.ss (Phase 4 — D025 §interface).
//
// getMysqlConnection parses a jdbc:mysql:// URL, calls handshake.mysqlConnect
// to authenticate, and wraps the authenticated fd in a MysqlConnection.
//
// Circular import note: this file imports lib/java/sql for the Connection /
// Statement / ResultSet interfaces; lib/java/sql imports getMysqlConnection
// from here for DriverManager_getConnection url dispatch. bootstrap/main.ss
// resolveInner (line 186-187) uses a visited set so the cycle expands cleanly —
// interfaces and classes are collected globally before method bodies resolve.
//
// Connection layering note: handshake.mysqlConnect returns the authenticated
// socket fd (D134 Phase 5 NAMESPACE COLLISION decision: handshake.ss owns auth
// protocol only, driver-layer Connection state lives here in jdbc.ss).

import { Connection, Statement, ResultSet } from "@/lib/java/sql"
import { writePacket } from "@/lib/com/mysql/wire"
import { mysqlConnect } from "@/lib/com/mysql/handshake"
import { sendQuery, readUpdateResult, readQueryResultSet, MysqlResultSet } from "@/lib/com/mysql/query"
import { URL, URL_parse } from "@/lib/url"

const COM_QUIT = 0x01
const DEFAULT_PORT = 3306
const URL_PREFIX = "jdbc:"

class MysqlConnection : Connection {
    fd: int
    autoCommit: int
    closed: int

    function createStatement(): Statement {
        return new MysqlStatement(this.fd)
    }

    function setAutoCommit(auto: int) {
        if (this.autoCommit == auto) { return }
        let sql = "SET autocommit=0"
        if (auto == 1) { sql = "SET autocommit=1" }
        sendQuery(this.fd, sql)
        readUpdateResult(this.fd)
        this.autoCommit = auto
    }

    function commit() {
        sendQuery(this.fd, "COMMIT")
        readUpdateResult(this.fd)
    }

    function rollback() {
        sendQuery(this.fd, "ROLLBACK")
        readUpdateResult(this.fd)
    }

    // COM_QUIT is a single 0x01 byte payload, seqId reset to 0. The server
    // closes the socket after receiving it; we close our end too.
    function close() {
        if (this.closed != 0) { return }
        writePacket(this.fd, 0, fromCharCode(COM_QUIT), 1)
        tcpClose(this.fd)
        this.closed = 1
    }

    function isClosed(): int {
        return this.closed
    }
}

class MysqlStatement : Statement {
    fd: int

    function executeQuery(sql: string): ResultSet {
        sendQuery(this.fd, sql)
        return readQueryResultSet(this.fd)
    }

    function executeUpdate(sql: string): int {
        sendQuery(this.fd, sql)
        return readUpdateResult(this.fd)
    }

    function execute(sql: string): int {
        sendQuery(this.fd, sql)
        return readUpdateResult(this.fd)
    }

    // Statement does not own the socket fd — Connection does. close() at the
    // Statement layer is a no-op; ResultSet.close() drains the socket buffer.
    function close() {
    }
}

// Parses jdbc:mysql://[user[:pwd]@]host[:port]/[db][?param=val&...] and opens
// an authenticated connection. On any failure the returned MysqlConnection has
// fd = -1 and closed = 1 so isClosed() returns 1 and callers short-circuit.
//
// JDBC URLs carry a double scheme (`jdbc:mysql:`) which RFC 3986 forbids
// (urlIsValidScheme rejects ':' inside scheme), so we strip the `jdbc:` prefix
// before delegating to URL_parse — `mysql://...` is then a normal URI.
//
// Phase 5 scope: query parameters after `?` are stripped (not consumed). User
// is "root", password "" and database "" by default; port defaults to 3306.
function getMysqlConnection(url: string): MysqlConnection {
    const stripped = url.substring(URL_PREFIX.length(), url.length() - URL_PREFIX.length())
    const u = URL_parse(stripped)

    let user = u.username()
    if (user == "") { user = "root" }
    const pwd = u.password()

    let host = u.hostname()
    if (host == "") { host = "127.0.0.1" }

    let port = DEFAULT_PORT
    const portStr = u.port()
    if (portStr != "") {
        const p = parseInt(portStr)
        if (p > 0) { port = p }
    }

    let db = ""
    const path = u.pathname()
    if (path.length() > 1) {
        db = path.substring(1, path.length() - 1)
    }

    const fd = mysqlConnect(host, port, user, pwd, db)
    let closed = 0
    if (fd < 0) { closed = 1 }
    return new MysqlConnection(fd, 1, closed)
}
