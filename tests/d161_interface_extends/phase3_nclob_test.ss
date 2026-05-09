// D161 Phase 3 NClob extends Clob 样本回退验证 — lib/java/sql.ss:538-545 NClob
// standalone restate 7 method 删除后 `interface NClob extends Clob {}` 形态,
// MysqlNClob : NClob 仍正确 dispatch + 通过 Clob type upcast 命中 vtable。
//
// Case 1 — MysqlNClob 直接调用 Clob 7 method 继承自 NClob extends Clob entry
// Case 2 — NClob type 上 MysqlNClob 实例多态 dispatch(子接口位置)
// Case 3 — Clob type 上 MysqlNClob 实例多态 dispatch(父接口位置 — D161
//          Phase 2 class_register.ss line 186-204 走 ifaceParents 链注册祖先
//          接口 implementor 启用,回退前 MysqlNClob 不在 Clob implementors)
// Case 4 — Clob type 上 getCharacterStream() 走 vtable 派发到 MysqlNClob 实现
//          返回 MysqlNCharacterStream(Reader)证全 method 通路非仅 length

import { test, assertEqual } from "@/lib/test"
import { Clob, NClob } from "@/lib/java/sql"
import { Reader } from "@/lib/java/io"
import { MysqlNClob } from "@/lib/com/mysql/driver_lobs"

function main() {
    test("Case 1: MysqlNClob 直接调用 Clob 7 method 全继承(NClob extends Clob {} 自动 merge)", () => {
        const nc = new MysqlNClob("hello world")
        assertEqual(nc.length(), 11)
        assertEqual(nc.getSubString(1, 5), "hello")
        assertEqual(nc.position("world", 1), 7)
        nc.truncate(5)
        assertEqual(nc.length(), 5)
        assertEqual(nc.getSubString(1, 5), "hello")
        nc.free()
        assertEqual(nc.length(), 0)
    })

    test("Case 2: NClob type 多态 dispatch — 子接口位置(回退前后均通)", () => {
        let n: NClob = new MysqlNClob("ntext-payload")
        assertEqual(n.length(), 13)
        assertEqual(n.getSubString(1, 5), "ntext")
        assertEqual(n.position("pay", 1), 7)
    })

    test("Case 3: Clob type upcast MysqlNClob — 父接口位置(D161 Phase 2 启用)", () => {
        let c: Clob = new MysqlNClob("clob-via-nclob-extends")
        assertEqual(c.length(), 22)
        assertEqual(c.getSubString(1, 4), "clob")
        assertEqual(c.position("nclob", 1), 10)
    })

    test("Case 4: Clob type 上 getCharacterStream() 走 vtable 派发到 MysqlNClob 返回 Reader", () => {
        let c: Clob = new MysqlNClob("XYZ")
        const r = c.getCharacterStream()
        assertEqual(r.read(), 88)
        assertEqual(r.read(), 89)
        assertEqual(r.read(), 90)
        assertEqual(r.read(), -1)
    })
}
