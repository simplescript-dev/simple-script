// jdbc_test_helpers.ss — JDBC 集成测试共享 fixture。
//
// 落点 tests/jdbc/import/:目录名以 /import 结尾,collectTestFiles
// (bootstrap/main.ss:410)对 /import 目录只收 main.ss、跳过其余 .ss,本辅助
// 无 main() 不会被 bin/ss test 误当独立测试编译。同模式于 tests/phase5/import/。
//
// drainReader 不在本文件 — canonical 在 lib/com/mysql/prepared.ss:56,d151/d154
// 直接显式 import。在本文件复制会与 transitive prepared.ss 同签名 dead code 冲突
// (SS 后定义覆盖,helper 版本永远被吞)。

import { JdbcTemplate } from "@/lib/spring/jdbc"

function dropAllProcs(url: string, names: Array<string>) {
    const tmpl = new JdbcTemplate(url)
    let i = 0
    while (i < names.length()) {
        tmpl.execute(`DROP PROCEDURE IF EXISTS ${names[i]}`)
        i = i + 1
    }
}

function dropAllTables(url: string, names: Array<string>) {
    const tmpl = new JdbcTemplate(url)
    let i = 0
    while (i < names.length()) {
        tmpl.execute(`DROP TABLE IF EXISTS ${names[i]}`)
        i = i + 1
    }
}
