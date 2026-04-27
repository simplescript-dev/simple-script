ultrathink D137 Phase 3 实施 — tests/d134_mysql/integration_test.ss 11 处含动态值 SQL retcon 走 prepared+setter。前置:Phase 2 已落地 commit `4c28bc0`(JpaRepository 11 处 CRUD callback retcon + placeholders 字段缓存 + buildPlaceholders Array<string>.join 复用 + tests d134_mysql save 调用方 retcon + §F9 锚 SS lambda 参数类型推断 + interface dispatch bug 发现);Phase 1 commit `d2df1ba` 已落锁 JdbcTemplate 5 method callback 重载。

**RED 凭据**(本轮已跑过):
- `grep -cE "VALUES \([0-9]+, '" tests/d134_mysql/integration_test.ss` 期望 > 0(实测 = 4,4 处 INSERT VALUES 含动态字面量未 ?化);Phase 3 GREEN 期望 = 0
- `grep -cE "WHERE id = [0-9]" tests/d134_mysql/integration_test.ss` 期望 > 0(实测 = 7,7 处 WHERE id = literal 未 ?化);Phase 3 GREEN 期望 = 0
- 总计 11 处含动态值 SQL 需 retcon(test 2 line 73/75/83/84/89 + test 3 line 100 + test 4 line 113 + test 7 line 138/139/140/141);test 8 (JpaRepository) Phase 2 已 retcon

**改动清单**(D137 §Phase 3 §改动清单 + 11 处分类):

1. **test 2 CRUD INSERT/SELECT/UPDATE/DELETE**(line 68-92):5 处 SQL ?化 — line 73 INSERT VALUES (?, ?, ?) + setInt/setString/setInt;line 75 SELECT WHERE id = ? + setInt;line 83 UPDATE SET age = ? WHERE id = ? + 双 setInt;line 84 SELECT WHERE id = ? + setInt;line 89 DELETE WHERE id = ? + setInt;改用 `conn.prepareStatement(sql)` + setter + executeUpdate/Query(直 driver 接口,§D136 实证 GREEN 范式)
2. **test 3 transaction commit**(line 95-105):line 100 INSERT VALUES (?, ?, ?) + 三 setter;同上 prepared 直 driver 路径
3. **test 4 transaction rollback**(line 108-118):line 113 INSERT VALUES (?, ?, ?) + 三 setter;同上
4. **test 7 JdbcTemplate**(line 135-143):4 处用 JdbcTemplate Phase 1 callback 重载 — line 138 tmpl.update(sql, setter) + 三 setter;line 139 tmpl.queryForString(sql, setter, column) + setInt;line 140 tmpl.queryForInt(sql, setter, column) + setInt;line 141 tmpl.update(sql, setter) + setInt
5. **lambda 参数显式标 `(s: PreparedStatement) =>`** 全 11 处 callback(§F9 workaround 持续应用,真根因留 sub-D 修编译器)
6. **不动 path**:countAll function(line 42-45)无动态值;recreateTable / dropTable / clearAll(line 23-40)DDL 路径 §核心原则 2 旧签名保留;test 1/5/6 无 SQL

**GREEN 标准**(D137 §Phase 3 §GREEN):

- `./build.sh bootstrap` 三阶段固定点
- `bin/ss test tests/d134_mysql/` 5 case 全绿(8 sub-tests 全 PASS)
- `bin/ss test tests/` 全绿(259/4/263 baseline 不降)
- `bin/ss test tests/d135_caching_sha2/` 4 case 全绿(§核心原则 7 不动)
- `bin/ss test tests/d136_prepared_statement/` 5 case 全绿(§核心原则 7 不动)
- `grep -cE "VALUES \([0-9]+, '" tests/d134_mysql/integration_test.ss` = 0(主判据 1)
- `grep -cE "WHERE id = [0-9]" tests/d134_mysql/integration_test.ss` = 0(主判据 2)
- `bin/ss run tools/d_doc_index_linter.ss` F1 = 0
- `bin/ss run tools/reflection_health_linter.ss` baseline 不升
- axiom 红线 grep / nm = 0 永久维持(D134 + D135 + D136 全继承)

严格按 D137 §核心原则 1-11 + docs/3-MNK.md §M PSM 九问 + §N VCM 六验执行:
- §核心原则 1 callback 主线 + §核心原则 4 元数据 vs 动态值 grep 分类
- §核心原则 6 全迁完整性(11 处全 retcon,metadata-only 路径合法保留需逐项分类标注)
- §核心原则 7 tests/d135_caching_sha2/ + tests/d136_prepared_statement/ 不动
- §核心原则 9 bootstrap 隔离(仅 tests/ 改,不动 bootstrap)
- §F9 lambda 参数显式 type 注解 `(s: PreparedStatement)` 持续应用,真根因留 sub-D 修编译器
- R3 queryForList streaming socket 与 prepared cursor 兼容性(test 7 line 139/140 tmpl.queryForString/Int 走 callback,内部 queryForList(sql, setter) 复用 — 检验 Phase 1 streaming 模式与 binary protocol 兼容)

**§After Done 三步必走**(收尾 gate):
1. /simplify 跑 3 agent 并行(reuse / quality / efficiency)
2. commit(2-commit 范式:feat(D137) Phase 3 实施 → docs(D137) Phase 3 hash 回填 + Status 收关 + next_prompt 指向 Phase 4)
3. 写下轮 next_prompt 指向 D137 Phase 4(e2e 闭环 + D136 §F1 D138 编号冲突注释 + Status 收关)且必含 ultrathink 关键字 + 跑 `bin/ss run tools/next_prompt_ultrathink_linter.ss` GATE PASS
