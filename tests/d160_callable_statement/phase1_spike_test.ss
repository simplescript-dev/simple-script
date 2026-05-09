// D160 §Phase 1 spike — interface CallableStatement extends PreparedStatement
// + Connection.prepareCall + NoopCallableStatement stub. Validates:
//   * 21 own + 13 inherited (PreparedStatement) methods dispatch via D025
//     vtable (D161 §Phase 2 walk-parent-merge first lib/-side wire on a
//     34-method set — Phase 2 spike capped at ≤7 method shapes)
//   * CallableStatement type polymorphism on the child interface position
//   * PreparedStatement type upcast — D161 §Phase 2
//     class_register.ss line 186-204 ifaceImplementors walks ifaceParents
//     to register NoopCallableStatement on the parent (PreparedStatement)
//     vtable, otherwise the upcast lands on __default and returns 0
//   * Connection.prepareCall returns the NoopCallableStatement stub
//     (jdbc.ss MysqlConnection.prepareCall stub path; Phase 2 swaps in
//     `new MysqlCallableStatement(this, sql)` real impl)

import { test, assertEqual } from "@/lib/test"
import { CallableStatement, PreparedStatement, Connection } from "@/lib/java/sql"
import { NoopCallableStatement, MysqlConnection, NoopDatabaseMetaData } from "@/lib/com/mysql/jdbc"

function main() {
    test("Case 1 — NoopCallableStatement 21 own methods dispatch (registerOutParameter + 7 OUT getter + wasNull)", () => {
        const cs = new NoopCallableStatement()
        cs.registerOutParameter(1, 4)
        cs.registerOutParameter(2, 4, 0)
        assertEqual(cs.getString(1), "")
        assertEqual(cs.getBoolean(1), 0)
        assertEqual(cs.getInt(1), 0)
        assertEqual(cs.getLong(1), 0)
        assertEqual(cs.getByte(1), 0)
        assertEqual(cs.getShort(1), 0)
        assertEqual(cs.wasNull(), 0)
    })

    test("Case 2 — NoopCallableStatement 13 inherited PreparedStatement methods dispatch (setXxx + execute + close)", () => {
        const cs = new NoopCallableStatement()
        cs.setInt(1, 42)
        cs.setLong(2, 100)
        cs.setString(3, "hello")
        cs.setDouble(4, 3.14)
        cs.setBoolean(5, 1)
        cs.setNull(6)
        cs.setFetchSize(50)
        assertEqual(cs.executeUpdate(), 0)
        assertEqual(cs.getLastInsertId(), 0)
        cs.close()
    })

    test("Case 3 — CallableStatement type polymorphism (child interface position)", () => {
        let cs: CallableStatement = new NoopCallableStatement()
        cs.registerOutParameter(1, 4)
        assertEqual(cs.getInt(1), 0)
        assertEqual(cs.getString(1), "")
        assertEqual(cs.wasNull(), 0)
    })

    test("Case 4 — PreparedStatement type upcast (D161 ifaceParents chain — without it the parent vtable __default returns)", () => {
        let ps: PreparedStatement = new NoopCallableStatement()
        ps.setInt(1, 99)
        ps.setString(2, "upcast")
        assertEqual(ps.executeUpdate(), 0)
        assertEqual(ps.getLastInsertId(), 0)
        ps.close()
    })

    test("Case 5 — getObject dual overload (idx alone vs idx+classType, arity dispatch)", () => {
        const cs = new NoopCallableStatement()
        assertEqual(cs.getObject(1), "")
        assertEqual(cs.getObject(1, "java.lang.Integer"), "")
        assertEqual(cs.getObject(2, "java.lang.String"), "")
    })

    test("Case 6 — float / double / BigDecimal numeric OUT getters", () => {
        const cs = new NoopCallableStatement()
        assertEqual(cs.getFloat(1), 0.0)
        assertEqual(cs.getDouble(1), 0.0)
        const bd = cs.getBigDecimal(1)
        assertEqual(bd.unscaledValue(), 0)
        assertEqual(bd.scale(), 0)
    })

    test("Case 7 — Date / Time / Timestamp OUT getters return concrete stubs (D025 vtable forces non-null returns)", () => {
        const cs = new NoopCallableStatement()
        const d = cs.getDate(1)
        assertEqual(d.getYear(), 1970)
        assertEqual(d.getMonth(), 1)
        assertEqual(d.getDay(), 1)
        const t = cs.getTime(2)
        assertEqual(t.getHours(), 0)
        assertEqual(t.getMinutes(), 0)
        assertEqual(t.getSeconds(), 0)
        const ts = cs.getTimestamp(3)
        assertEqual(ts.getYear(), 1970)
        assertEqual(ts.getNanos(), 0)
    })

    test("Case 8 — Reader OUT getters (getCharacterStream / getNCharacterStream) return concrete Reader stubs", () => {
        const cs = new NoopCallableStatement()
        const r = cs.getCharacterStream(1)
        assertEqual(r.read(), -1)
        const nr = cs.getNCharacterStream(2)
        assertEqual(nr.read(), -1)
    })

    test("Case 9 — getNString + getBytes OUT getters return empty string defaults", () => {
        const cs = new NoopCallableStatement()
        assertEqual(cs.getNString(1), "")
        assertEqual(cs.getBytes(2), "")
    })

    test("Case 10 — getParameterMetaData inherited returns NoopParameterMetaData (D161 walk-parent-merge wires inherited PreparedStatement.getParameterMetaData onto CallableStatement vtable)", () => {
        const cs = new NoopCallableStatement()
        const pmd = cs.getParameterMetaData()
        assertEqual(pmd.getParameterCount(), 0)
        assertEqual(pmd.getParameterType(1), 0)
    })

    test("Case 11 — PreparedStatement type upcast getParameterMetaData walks parent vtable (D161 ifaceParents inheritance)", () => {
        let ps: PreparedStatement = new NoopCallableStatement()
        const pmd = ps.getParameterMetaData()
        assertEqual(pmd.getParameterCount(), 0)
    })

    test("Case 12 — MysqlConnection.prepareCall stub returns NoopCallableStatement (Phase 2 swaps in real MysqlCallableStatement); fd=0 since stub does not touch the socket", () => {
        const conn = new MysqlConnection(0, 1, 0, "", "", new NoopDatabaseMetaData(), 0)
        const cs = conn.prepareCall("CALL proc_d160_phase1(?, ?)")
        cs.registerOutParameter(2, 4)
        assertEqual(cs.getInt(2), 0)
        assertEqual(cs.wasNull(), 0)
    })
}
