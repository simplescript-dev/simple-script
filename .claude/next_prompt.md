ultrathink D137 Phase 2 实施 — lib/spring/data.ss 11 处 JpaRepository CRUD retcon 走 callback。前置:Phase 1 已落地 commit `d2df1ba` 解锁 JdbcTemplate 5 callback 重载(execute/update/queryForList(sql, setter: fn) + queryForString/queryForInt(sql, setter: fn, column)),spring/data.ss 现可消费 setter callback overload。

**RED 凭据**(本轮已跑过):
- `grep -cE '\$\{(id|value|setClauses|vals)\}' lib/spring/data.ss` 期望 > 0(实测 = 7,动态值未 ?化);Phase 2 GREEN 期望 = 0(全 ?化 + setter 注入)
- `grep -cE '\$\{(this\.tableName|this\.columns|column|cols)\}' lib/spring/data.ss` 期望 > 0(实测 = 10,元数据合法);Phase 2 GREEN 维持 > 0(元数据保留)
- `grep -c "prepareStatement\|setInt\|setString" lib/spring/data.ss` 期望 = 0(实测 = 0,无 prepared 调用);Phase 2 GREEN 期望 > 0(setter 内调)

**改动清单**(D137 §Phase 2 §改动清单 + 11 处元数据 vs 动态值分类表 line 188-202):

1. **11 处分类**(§核心原则 4):data.ss line 30/34/38/42/46/50/54/58/62/66/26 — `${this.tableName}` / `${this.columns}` / `${column}` / `${cols}` 是**元数据**(用户 const,合法保留拼接;MySQL 不允许 prepared statement ? 占位列名/表名);`${id}` / `${value}` / `${setClauses}` / `${vals}` 是**动态值**(?化 + setter)
2. **findById / findBy / findByInt / existsById / deleteById**(line 38/42/46/50/58):`WHERE id = ${id}` / `WHERE ${column} = '${value}'` 类 — 元数据列名保留,id/value 改 `?` + setter.setInt/setString
3. **save / update 两 method 签名重设计**(R5 接受 JpaRepository 局部签名破坏,§核心原则 2 仅约束 JdbcTemplate 不破签名):save(values: string) → save(setter: fn);update(id, setClauses: string) → update(id, setter: fn)
4. **新增 JpaRepository 字段 `placeholders: string`**:constructor 初始化为按 columns 拆分数生成的 `"?, ?, ?"` 串(供 save INSERT 占位使用)
5. **JpaRepositoryFactory_create 改 constructor**:增 placeholders 参数(基于 columns 字符串内 `,` 数计算)
6. **业务调用方 retcon**:grep -rn "save\|update" tests/ 找全调用方,save/update 旧字符串签名改 callback 形式

**GREEN 标准**(D137 §Phase 2 §GREEN):

- `./build.sh bootstrap` 三阶段固定点
- `bin/ss test tests/` 全绿(baseline 259/4/263 不降,4 pre-existing fail 不变)
- `bin/ss test tests/d134_mysql/` 全绿(旧 jdbc 签名仍可用,Phase 3 才 retcon 调用方)
- `bin/ss test tests/d135_caching_sha2/` + `tests/d136_prepared_statement/` 全绿(本 Phase 不动)
- `grep -cE '\$\{(id|value|setClauses|vals)\}' lib/spring/data.ss` = 0(主判据)
- `grep -cE '\$\{(this\.tableName|this\.columns|column|cols)\}' lib/spring/data.ss` > 0(元数据合法保留)
- `grep -c "prepareStatement\|setInt\|setString" lib/spring/data.ss` > 0(setter 调用)
- `bin/ss run tools/d_doc_index_linter.ss` F1 = 0
- `bin/ss run tools/reflection_health_linter.ss` baseline 不升

严格按 D137 §核心原则 1-11 + docs/3-MNK.md §M PSM 九问 + §N VCM 六验执行:
- §核心原则 1 callback 主线 + §核心原则 4 元数据 vs 动态值 grep 分类(MySQL 不允许 prepared statement ? 占位列名/表名,严防误 ?化致 ER_PARSE_ERROR)
- §核心原则 6 spring/data.ss 11 处全迁完整性(禁手动跳过任何一处)
- §核心原则 9 bootstrap 隔离(仅 lib/ + tests/ 改,不动 bootstrap)
- R4 元数据 vs 动态值分类完整性(Phase 2 grep 逐条标分类 + §5 §Evaluation §3-4 grep 互补交叉验证)
- R5 save/update 签名重设计致调用方破坏(同 commit 内改 JpaRepository + 所有 save/update 调用方,grep 全调用方实测)

**§After Done 三步必走**(收尾 gate):
1. /simplify 跑 3 agent 并行(reuse / quality / efficiency)
2. commit(2-commit 范式: feat(D137) Phase 2 实施 → docs(D137) Phase 2 hash 回填 + Status 收关 + next_prompt 指向 Phase 3)
3. 写下轮 next_prompt 指向 D137 Phase 3(tests/d134_mysql/integration_test.ss 8 case 含动态值 retcon)且必含 ultrathink 关键字 + 跑 `bin/ss run tools/next_prompt_ultrathink_linter.ss` GATE PASS
