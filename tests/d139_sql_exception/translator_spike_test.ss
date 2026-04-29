// D139 Phase 3 spike — SQLExceptionTranslator + Spring DAE Tree.
// Pure local, no docker dependency: constructs SQLException variants and
// runs them through SQLExceptionTranslator.translate, then exercises the
// 5-level catch hierarchy (DuplicateKey → DataIntegrityViolation →
// NonTransient → DataAccessException → Error).
//
// Validates D139 §Phase 3 §Phase 收关锚 + §A.2 H1 (cross-module class
// hierarchy in spring/jdbc) and H6 (multi-level fallthrough catch unwind
// across DAE depth ≥ 4 — Spring DAE root + 3 mid layers + leaf).

import { assertEqual, assertTrue } from "@/lib/test"
import { SQLException, SQLIntegrityConstraintViolationException, SQLSyntaxErrorException, SQLNonTransientConnectionException, SQLTransactionRollbackException } from "@/lib/java/sql"
import { SQLExceptionTranslator, DataAccessException, NonTransientDataAccessException, TransientDataAccessException, DataIntegrityViolationException, BadSqlGrammarException, CannotGetJdbcConnectionException, DataAccessResourceFailureException, DataRetrievalFailureException, DuplicateKeyException, EmptyResultDataAccessException, IncorrectResultSizeDataAccessException, TransientDataAccessResourceException, ConcurrencyFailureException, DeadlockLoserDataAccessException } from "@/lib/spring/jdbc"

function main() {
    const tr = new SQLExceptionTranslator()

    test("errorCode 1062 → DuplicateKeyException + cause transit", () => {
        const sql = new SQLIntegrityConstraintViolationException("Duplicate entry '1' for key 'PRIMARY'", "23000", 1062)
        const dae = tr.translate(sql)
        // Catch the leaf DAE — type identity routes to DuplicateKeyException.
        let leaf = 0
        try {
            throw(dae)
        } catch (e: DuplicateKeyException) {
            leaf = 1
            assertEqual(e.cause.sqlState, "23000")
            assertEqual(e.cause.errorCode, 1062)
            assertTrue(e.message.length() > 0)
        }
        assertEqual(leaf, 1)
    })

    test("errorCode 1048 → DataIntegrityViolationException (NOT NULL)", () => {
        const sql = new SQLIntegrityConstraintViolationException("Column 'name' cannot be null", "23000", 1048)
        const dae = tr.translate(sql)
        let caught = 0
        try {
            throw(dae)
        } catch (e: DataIntegrityViolationException) {
            // 1048 → DataIntegrityViolation (not DuplicateKey leaf).
            caught = 1
            assertEqual(e.cause.errorCode, 1048)
        }
        assertEqual(caught, 1)
    })

    test("errorCode 1146 → BadSqlGrammarException (table not exist)", () => {
        const sql = new SQLSyntaxErrorException("Table 'testdb.nope' doesn't exist", "42S02", 1146)
        const dae = tr.translate(sql)
        let caught = 0
        try {
            throw(dae)
        } catch (e: BadSqlGrammarException) {
            caught = 1
            assertEqual(e.cause.errorCode, 1146)
            assertEqual(e.cause.sqlState, "42S02")
        }
        assertEqual(caught, 1)
    })

    test("errorCode 1213 → DeadlockLoserDataAccessException", () => {
        const sql = new SQLTransactionRollbackException("Deadlock found when trying to get lock", "40001", 1213)
        const dae = tr.translate(sql)
        let caught = 0
        try {
            throw(dae)
        } catch (e: DeadlockLoserDataAccessException) {
            caught = 1
            assertEqual(e.cause.errorCode, 1213)
        }
        assertEqual(caught, 1)
    })

    test("errorCode 1045 → CannotGetJdbcConnectionException (invalid auth)", () => {
        const sql = new SQLNonTransientConnectionException("Access denied for user", "28000", 1045)
        const dae = tr.translate(sql)
        let caught = 0
        try {
            throw(dae)
        } catch (e: CannotGetJdbcConnectionException) {
            caught = 1
            assertEqual(e.cause.errorCode, 1045)
        }
        assertEqual(caught, 1)
    })

    test("SQLState 28xxx fallback (errorCode 0) → CannotGetJdbcConnection", () => {
        const sql = new SQLNonTransientConnectionException("auth failure (no errorCode)", "28000", 0)
        const dae = tr.translate(sql)
        let caught = 0
        try {
            throw(dae)
        } catch (e: CannotGetJdbcConnectionException) {
            caught = 1
            assertEqual(e.cause.sqlState, "28000")
        }
        assertEqual(caught, 1)
    })

    test("SQLState 23xxx fallback (errorCode 0) → DataIntegrityViolation", () => {
        const sql = new SQLIntegrityConstraintViolationException("integrity (no errorCode)", "23502", 0)
        const dae = tr.translate(sql)
        let caught = 0
        try {
            throw(dae)
        } catch (e: DataIntegrityViolationException) {
            caught = 1
            assertEqual(e.cause.sqlState, "23502")
        }
        assertEqual(caught, 1)
    })

    test("unknown errorCode + sqlState → DataAccessResourceFailureException default", () => {
        const sql = new SQLException("vendor-specific", "HY000", 9999)
        const dae = tr.translate(sql)
        let caught = 0
        try {
            throw(dae)
        } catch (e: DataAccessResourceFailureException) {
            caught = 1
            assertEqual(e.cause.errorCode, 9999)
        }
        assertEqual(caught, 1)
    })

    test("5-level hierarchy: DuplicateKey caught by DataIntegrityViolation parent", () => {
        const sql = new SQLIntegrityConstraintViolationException("dup", "23000", 1062)
        const dae = tr.translate(sql)
        let caught = 0
        try {
            throw(dae)
        } catch (e: DataIntegrityViolationException) {
            // Parent catch matches DuplicateKey leaf (Test 1 confirmed leaf
            // routing; this confirms parent catch on the same instance).
            caught = 1
        }
        assertEqual(caught, 1)
    })

    test("5-level hierarchy: DuplicateKey caught by NonTransientDataAccess grandparent", () => {
        const sql = new SQLIntegrityConstraintViolationException("dup", "23000", 1062)
        const dae = tr.translate(sql)
        let caught = 0
        try {
            throw(dae)
        } catch (e: NonTransientDataAccessException) {
            caught = 1
        }
        assertEqual(caught, 1)
    })

    test("5-level hierarchy: DuplicateKey caught by DataAccessException root", () => {
        const sql = new SQLIntegrityConstraintViolationException("dup", "23000", 1062)
        const dae = tr.translate(sql)
        let caught = 0
        try {
            throw(dae)
        } catch (e: DataAccessException) {
            caught = 1
            // Root level still exposes the wire fields via cause.
            assertEqual(e.cause.errorCode, 1062)
        }
        assertEqual(caught, 1)
    })

    test("5-level hierarchy: Deadlock caught by Concurrency parent + Transient grandparent", () => {
        // ConcurrencyFailure → DeadlockLoser leaf path: 1213 routes to
        // DeadlockLoser; Concurrency (parent) and Transient (grandparent)
        // catch the same instance.
        const sql1 = new SQLTransactionRollbackException("deadlock 1", "40001", 1213)
        let parentCaught = 0
        try {
            throw(tr.translate(sql1))
        } catch (e: ConcurrencyFailureException) {
            parentCaught = 1
        }
        assertEqual(parentCaught, 1)

        const sql2 = new SQLTransactionRollbackException("deadlock 2", "40001", 1213)
        let grandCaught = 0
        try {
            throw(tr.translate(sql2))
        } catch (e: TransientDataAccessException) {
            grandCaught = 1
        }
        assertEqual(grandCaught, 1)
    })

    println("All D139 Phase 3 SQLExceptionTranslator spike tests passed!")
}
