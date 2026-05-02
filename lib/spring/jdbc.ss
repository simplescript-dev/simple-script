// spring-jdbc:7.0 — JdbcTemplate. D134 Phase 5: real driver wiring.
//
// JdbcTemplate dispatches every call through DriverManager_getConnection(url).
// Per-call Connection lifecycle is managed at this layer (open + close around
// each method); ResultSet returned by queryForList aliases the underlying
// socket — caller must call ResultSet.close() before the next query on the
// same JdbcTemplate or the socket buffer will desync.
//
// withTransaction wraps fn() with setAutoCommit(0) + commit/rollback gating
// on fn's int return (0 = success → commit; nonzero = error → rollback).
//
// See docs/3-decisions/D133-sqlite-c-link-elimination.md
// See docs/3-decisions/D134-jdbc-mysql-wire-protocol.md §3 §Phase 5
// See docs/3-decisions/D138-mysql-generated-keys.md §Phase 3 (KeyHolder)

import { Connection, ResultSet, PreparedStatement, DriverManager_getConnection, RETURN_GENERATED_KEYS, SQLException } from "@/lib/java/sql"

// ── RowCallbackHandler — D146 Phase 4 streaming row callback ─
// Mirrors org.springframework.jdbc.core.RowCallbackHandler. Single
// processRow method invoked once per row by JdbcTemplate.query(sql,
// callback) + JdbcTemplate.query(sql, setter, callback). Implementor
// decides what to do with the row (sum / filter / write to file /
// dispatch downstream) without materializing the full ResultSet.
//
// Combined with PreparedStatement.setFetchSize the dual semantics are:
//   setFetchSize(N >= 1)             → server-side cursor (useCursor=1
//                                        + COM_STMT_FETCH N rows / batch)
//   setFetchSize(INTEGER_MIN_VALUE)  → MySQL Connector/J client-side
//                                        row streaming (useCursor=0)
//   setFetchSize(0) / no call        → client streaming default
//
// INTEGER_MIN_VALUE -2147483648 is the MySQL Connector/J 5.0.6+
// magic value (java.lang.Integer.MIN_VALUE) — Spring "Streaming Query
// Results" docs reference it.
const INTEGER_MIN_VALUE = -2147483648

interface RowCallbackHandler {
    function processRow(rs: ResultSet): void
}

// Default no-op handler — kept here so that any translation unit that
// imports jdbc.ss (e.g. tests/d139_sql_exception/translator_spike_test.ss)
// transitively pulls a RowCallbackHandler implementor into its
// ifaceImplementors map. SS interface dispatchers are only emitted when
// the interface has at least one implementor in the unit's import
// closure (see bootstrap/gen/gen_iface.ss generateInterfaceDispatchers
// line 140 `if (impls == "") { continue }`); without this stub
// JdbcTemplate.query's `callback.processRow(rs)` call site would
// reference an undefined `@__iface_RowCallbackHandler_processRow`
// symbol. Same idiom as KeyHolder + GeneratedKeyHolder above.
class NoopRowCallbackHandler : RowCallbackHandler {
    function processRow(rs: ResultSet): void {}
}

// ── KeyHolder ────────────────────────────────────────────────
// D138 Phase 3 — Spring KeyHolder standard. JdbcTemplate.update(sql, setter,
// keyHolder) populates keyHolder.getKeyList() with one Map<string,int> per
// generated row (column name "GENERATED_KEY" — MySQL Connector/J convention).
// getKey / getKeyAsLong return the single int from the first row (most common
// path for AUTO_INCREMENT INSERT). getKeys returns the first row Map for the
// rare multi-column generated-keys case (kept as Spring spec parity even
// though MySQL only generates one column today).
//
// Mirrors org.springframework.jdbc.support.KeyHolder. SS Map<string,int>
// constrains values to int (the only generated-key shape MySQL emits) — Spring's
// Map<String,Object> is not modelable until SS gains a top-type.

interface KeyHolder {
    function getKey(): int
    function getKeyAsLong(): int
    function getKeys(): Map<string, int>
    function getKeyList(): Array<Map<string, int>>
}

class GeneratedKeyHolder : KeyHolder {
    keyList: Array<Map<string, int>>

    function getKey(): int {
        if (this.keyList.length() == 0) { return 0 }
        return this.keyList[0].get("GENERATED_KEY")
    }

    function getKeyAsLong(): int {
        return this.getKey()
    }

    function getKeys(): Map<string, int> {
        if (this.keyList.length() == 0) { return new Map() }
        return this.keyList[0]
    }

    function getKeyList(): Array<Map<string, int>> {
        return this.keyList
    }
}

// ── DataAccessException Hierarchy — Spring DAE Tree ──────────
// Mirrors org.springframework.dao.DataAccessException complete class tree
// (Spring 7.0). Empty-body subclasses are intentional — Spring DAE
// subclasses carry no extra state; type identity alone routes catch-clause
// dispatch via bootstrap/gen/stmts/stmts_exc.ss:99 genCatchClauses.
//
// Constructor positional args: new <Subclass>(message, cause). The cause is
// the underlying java.sql.SQLException (Spring `getRootCause()` standard) —
// callers reach the wire-protocol-level sqlState / errorCode via
//   catch (e: DataAccessException) { e.cause.sqlState ; e.cause.errorCode }
// without DAE itself duplicating those fields.
//
//   DataAccessException (extends Error, adds cause: SQLException)
//   ├── NonTransientDataAccessException                ← retry will not succeed
//   │   ├── DataIntegrityViolationException            SQLState class 23
//   │   │   └── DuplicateKeyException                  MySQL errorCode 1062
//   │   ├── BadSqlGrammarException                     SQLState class 42
//   │   ├── CannotGetJdbcConnectionException           SQLState class 08 / 28
//   │   ├── DataAccessResourceFailureException         default fallback
//   │   └── DataRetrievalFailureException
//   │       ├── EmptyResultDataAccessException
//   │       └── IncorrectResultSizeDataAccessException
//   └── TransientDataAccessException                   ← retry may succeed
//       ├── TransientDataAccessResourceException
//       └── ConcurrencyFailureException                ← lock contention
//           └── DeadlockLoserDataAccessException       MySQL errorCode 1213

class DataAccessException extends Error {
    cause: SQLException
}

class NonTransientDataAccessException extends DataAccessException {}
class TransientDataAccessException extends DataAccessException {}

class DataIntegrityViolationException extends NonTransientDataAccessException {}
class BadSqlGrammarException extends NonTransientDataAccessException {}
class CannotGetJdbcConnectionException extends NonTransientDataAccessException {}
class DataAccessResourceFailureException extends NonTransientDataAccessException {}
class DataRetrievalFailureException extends NonTransientDataAccessException {}

class DuplicateKeyException extends DataIntegrityViolationException {}

class EmptyResultDataAccessException extends DataRetrievalFailureException {}
class IncorrectResultSizeDataAccessException extends DataRetrievalFailureException {}

class TransientDataAccessResourceException extends TransientDataAccessException {}
class ConcurrencyFailureException extends TransientDataAccessException {}

class DeadlockLoserDataAccessException extends ConcurrencyFailureException {}

// ── SQLExceptionTranslator ────────────────────────────────────
// Mirrors org.springframework.jdbc.support.SQLErrorCodeSQLExceptionTranslator
// (Spring 7.0 simplified). MySQL Connector/J errorCode primary table →
// SQLState 2-char class fallback (JDBC 4.3 §13.4) → DataAccessResource
// FailureException default. Phase 4 wires JdbcTemplate to call translate()
// on every SQLException it catches before re-throwing.

class SQLExceptionTranslator {
    function translate(ex: SQLException): DataAccessException {
        const code = ex.errorCode
        const msg = ex.message

        // MySQL errorCode primary table — overrides SQLState class to keep
        // common cases (dup key, lock timeout) precise across the sqlState
        // variants Connector/J reports for the same root cause.
        if (code == 1062) { return new DuplicateKeyException(msg, ex) }
        if (code == 1048) { return new DataIntegrityViolationException(msg, ex) }
        if (code == 1452) { return new DataIntegrityViolationException(msg, ex) }
        if (code == 1146) { return new BadSqlGrammarException(msg, ex) }
        if (code == 1054) { return new BadSqlGrammarException(msg, ex) }
        if (code == 1213) { return new DeadlockLoserDataAccessException(msg, ex) }
        if (code == 1205) { return new ConcurrencyFailureException(msg, ex) }
        if (code == 1045) { return new CannotGetJdbcConnectionException(msg, ex) }

        // SQLState 2-char class fallback — JDBC 4.3 §13.4.
        const state = ex.sqlState
        const cls = state.length() < 2 ? "" : state.substring(0, 2)
        if (cls == "08") { return new CannotGetJdbcConnectionException(msg, ex) }
        if (cls == "28") { return new CannotGetJdbcConnectionException(msg, ex) }
        if (cls == "23") { return new DataIntegrityViolationException(msg, ex) }
        if (cls == "40") { return new DeadlockLoserDataAccessException(msg, ex) }
        if (cls == "42") { return new BadSqlGrammarException(msg, ex) }

        return new DataAccessResourceFailureException(msg, ex)
    }
}

// ── JdbcTemplate ─────────────────────────────────────────────
//
// D139 Phase 4 — Spring DataAccessException standard. Every method runs the
// per-call Connection (D137/D138) inside an outer try / catch (e: SQLException)
// → SQLExceptionTranslator.translate(e) → throw DAE so callers catch the DAE
// subtree (DuplicateKey, BadSqlGrammar, …) and never see the underlying
// java.sql.SQLException. Resource cleanup uses nested try / finally
// (stmt.close + conn.close) so that throws on the executeUpdate path still
// release the socket before the translate step fires.
//
// queryForList(...) is the streaming exception: the ResultSet aliases the
// socket, so the Connection cannot be closed in this method — only the
// SQLException → DAE translate step is wrapped, and conn / stmt leak on
// failure (D137 simple per-call model; HikariCP D125+ sub-D recovers via
// pool reclaim). Callers must still rs.close() the returned ResultSet.

class JdbcTemplate {
    url: string

    function execute(sql: string): int {
        let r = 0
        try {
            const conn = DriverManager_getConnection(this.url)
            try {
                const stmt = conn.createStatement()
                try {
                    r = stmt.execute(sql)
                } finally {
                    stmt.close()
                }
            } finally {
                conn.close()
            }
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
        return r
    }

    // D137 Phase 1: PreparedStatementSetter callback — setter binds positional params before executeUpdate fires.
    function execute(sql: string, setter: fn(PreparedStatement):void): int {
        let r = 0
        try {
            const conn = DriverManager_getConnection(this.url)
            try {
                const stmt = conn.prepareStatement(sql)
                try {
                    setter(stmt)
                    r = stmt.executeUpdate()
                } finally {
                    stmt.close()
                }
            } finally {
                conn.close()
            }
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
        return r
    }

    function update(sql: string): int {
        let r = 0
        try {
            const conn = DriverManager_getConnection(this.url)
            try {
                const stmt = conn.createStatement()
                try {
                    r = stmt.executeUpdate(sql)
                } finally {
                    stmt.close()
                }
            } finally {
                conn.close()
            }
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
        return r
    }

    function update(sql: string, setter: fn(PreparedStatement):void): int {
        let r = 0
        try {
            const conn = DriverManager_getConnection(this.url)
            try {
                const stmt = conn.prepareStatement(sql)
                try {
                    setter(stmt)
                    r = stmt.executeUpdate()
                } finally {
                    stmt.close()
                }
            } finally {
                conn.close()
            }
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
        return r
    }

    // D138 Phase 3 — Spring KeyHolder INSERT path. Per-call Connection
    // (HikariCP D125+ sub-D for pooling).
    function update(sql: string, setter: fn(PreparedStatement):void, keyHolder: KeyHolder): int {
        let r = 0
        try {
            const conn = DriverManager_getConnection(this.url)
            try {
                const stmt = conn.prepareStatement(sql, RETURN_GENERATED_KEYS)
                try {
                    setter(stmt)
                    r = stmt.executeUpdate()
                    const list = keyHolder.getKeyList()
                    const rs = stmt.getGeneratedKeys()
                    try {
                        while (rs.next() == 1) {
                            let row: Map<string, int> = new Map()
                            row.set("GENERATED_KEY", rs.getInt("GENERATED_KEY"))
                            list.push(row)
                        }
                    } finally {
                        rs.close()
                    }
                } finally {
                    stmt.close()
                }
            } finally {
                conn.close()
            }
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
        return r
    }

    // ResultSet streams rows from the underlying socket — caller must call
    // rs.close() before issuing another query on the same url, and the
    // Connection leaks until then. Sub-D (HikariCP D125+) introduces pooling.
    // On failure inside getConnection / createStatement / executeQuery the
    // SQLException is translated to a DAE; allocated stmt / conn leak on the
    // failure path (per-call simple model — HikariCP closes on pool reclaim).
    function queryForList(sql: string): ResultSet {
        try {
            const conn = DriverManager_getConnection(this.url)
            const stmt = conn.createStatement()
            return stmt.executeQuery(sql)
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
    }

    // Same streaming semantics as queryForList(sql) — the Connection leaks
    // until rs.close(); PreparedStatement.close() releases the server-side
    // statement handle but the fd is owned by the caller via the leaked conn.
    function queryForList(sql: string, setter: fn(PreparedStatement):void): ResultSet {
        try {
            const conn = DriverManager_getConnection(this.url)
            const stmt = conn.prepareStatement(sql)
            setter(stmt)
            return stmt.executeQuery()
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
    }

    function queryForString(sql: string, column: string): string {
        let v = ""
        try {
            const rs = this.queryForList(sql)
            try {
                if (rs.next() == 1) {
                    v = rs.getString(column)
                }
            } finally {
                rs.close()
            }
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
        return v
    }

    function queryForString(sql: string, setter: fn(PreparedStatement):void, column: string): string {
        let v = ""
        try {
            const rs = this.queryForList(sql, setter)
            try {
                if (rs.next() == 1) {
                    v = rs.getString(column)
                }
            } finally {
                rs.close()
            }
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
        return v
    }

    function queryForInt(sql: string, column: string): int {
        let v = 0
        try {
            const rs = this.queryForList(sql)
            try {
                if (rs.next() == 1) {
                    v = rs.getInt(column)
                }
            } finally {
                rs.close()
            }
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
        return v
    }

    function queryForInt(sql: string, setter: fn(PreparedStatement):void, column: string): int {
        let v = 0
        try {
            const rs = this.queryForList(sql, setter)
            try {
                if (rs.next() == 1) {
                    v = rs.getInt(column)
                }
            } finally {
                rs.close()
            }
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
        return v
    }

    // D146 Phase 4 — Spring JdbcTemplate.query(sql, callback) standard.
    // Streams every row through callback.processRow(rs); the ResultSet,
    // Statement, and Connection are released via four-deep try/finally
    // before query returns — unlike queryForList this method does not
    // leak the socket. This 1-arg path uses Statement.executeQuery
    // (text protocol COM_QUERY 0x03) which has no server-side cursor;
    // callers that need cursor semantics + setFetchSize use the
    // parameterized overload below.
    function query(sql: string, callback: RowCallbackHandler): void {
        try {
            const conn = DriverManager_getConnection(this.url)
            try {
                const stmt = conn.createStatement()
                try {
                    const rs = stmt.executeQuery(sql)
                    try {
                        while (rs.next() == 1) {
                            callback.processRow(rs)
                        }
                    } finally {
                        rs.close()
                    }
                } finally {
                    stmt.close()
                }
            } finally {
                conn.close()
            }
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
    }

    // Parameterized variant — setter binds positional params and may
    // also call ps.setFetchSize(N) to opt into server-side cursor
    // (N >= 1) or ps.setFetchSize(INTEGER_MIN_VALUE) for MySQL
    // Connector/J client-side row streaming (D146 §A.2 H4 dual
    // semantics). Same four-deep try/finally release as the 1-arg
    // path so the socket is clean before query returns.
    function query(sql: string, setter: fn(PreparedStatement):void, callback: RowCallbackHandler): void {
        try {
            const conn = DriverManager_getConnection(this.url)
            try {
                const stmt = conn.prepareStatement(sql)
                try {
                    setter(stmt)
                    const rs = stmt.executeQuery()
                    try {
                        while (rs.next() == 1) {
                            callback.processRow(rs)
                        }
                    } finally {
                        rs.close()
                    }
                } finally {
                    stmt.close()
                }
            } finally {
                conn.close()
            }
        } catch (e: SQLException) {
            const translator = new SQLExceptionTranslator()
            throw(translator.translate(e))
        }
    }
}

// ── Transaction helper ───────────────────────────────────────
// Opens a Connection, disables autocommit, runs fn(), and commits if fn returns
// 0 / rolls back otherwise. Returns fn's return value.

function withTransaction(db: string, fn: fn): int {
    const conn = DriverManager_getConnection(db)
    conn.setAutoCommit(0)
    const r = fn()
    if (r == 0) {
        conn.commit()
    } else {
        conn.rollback()
    }
    conn.close()
    return r
}
