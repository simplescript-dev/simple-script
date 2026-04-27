ultrathink D137 Phase 1 实施 — lib/spring/jdbc.ss 5 method callback 重载实施(纯 lib 改,~60 LOC)。前置:D140 Phase 1 已落地 commit `a4741da` 解锁 checker class method overload by arity 对称化,JdbcTemplate 同名 method 加 callback 重载现可过 checker。

**RED 凭据**(第一个工具调用): `grep -c "prepareStatement" lib/spring/jdbc.ss` 期望 = 0(当前 GREEN);Phase 1 GREEN 期望 ≥ 5(5 method 各加 1 overload,每个 overload 内调 prepareStatement)。

**改动清单**(D137 §Phase 1 §改动清单):

1. **lib/spring/jdbc.ss 加 5 重载**(在既有 5 method 之后):
   - `execute(sql: string, setter: fn): int` → `connection.prepareStatement(sql)` + `setter(stmt)` + `executeUpdate()` + `close()`
   - `update(sql: string, setter: fn): int` → 同 execute(语义相同 — DML 路径)
   - `queryForList(sql: string, setter: fn): ResultSet` → `prepareStatement` + `setter(stmt)` + `executeQuery()`(Connection 故意不关 — streaming)
   - `queryForString(sql: string, setter: fn, column: string): string` → 复用 `queryForList(sql, setter)` overload + `rs.next()` + `rs.getString(column)`
   - `queryForInt(sql: string, setter: fn, column: string): int` → 复用 `queryForList(sql, setter)` overload + `rs.next()` + `rs.getInt(column)`

2. **既有 5 method 保留**(execute/update/queryForList/queryForString/queryForInt 旧签名,DDL / 无参数 SELECT 路径继续用)

3. **import 加 PreparedStatement**: `import { PreparedStatement } from "@/lib/java/sql"` 或同 file 既有 import 行扩

**早期 spike**(H1 假设挑战 — D137 §Stable Facts SS fn 多语句 lambda 实证):
Phase 1 第一步先实测 SS fn 多语句 lambda 体,写 `/tmp/spike_lambda_multi.ss`:
```
import { PreparedStatement } from "@/lib/java/sql"
function callMe(s: PreparedStatement, fn: fn) { fn(s) }
function main() {
    // 用 stub PreparedStatement(若编译 stub 太重直接验 fn 多语句 lambda 体即可)
    const cb = (x: int) => { println(`a`); println(`b`); println(`c`) }
    cb(1)
}
```
`bin/ss run /tmp/spike_lambda_multi.ss` GREEN(三行连续 println)→ H1 PASS,继续 5 重载;若失败 → 单语句 lambda 路径 + 用户分多次调 setter 范式(D137 §H1 fallback)。

**GREEN 标准**(D137 §Phase 1 §GREEN):
- `./build.sh bootstrap` 三阶段固定点
- `bin/ss test tests/d134_mysql/` 8 case 全绿(旧签名仍可用,Phase 3 才 retcon 调用方)
- `bin/ss test tests/d135_caching_sha2/` 4 case 全绿(adminStmt DDL 走旧签名,本 Phase 不动)
- `bin/ss test tests/d136_prepared_statement/` 5 case 全绿(直走 driver 接口,与 Spring 层无关)
- `grep -c "prepareStatement" lib/spring/jdbc.ss` ≥ 5(主判据)
- `bin/ss test tests/` 全绿 baseline 不降(259/4/263 — 4 pre-existing fail 不变)
- `bin/ss run tools/d_doc_index_linter.ss` F1 = 0
- `bin/ss run tools/reflection_health_linter.ss` baseline 不升

**严格按 D137 §核心原则 1-12 + docs/3-MNK.md §M PSM 九问 + §N VCM 六验执行**:
- §核心原则 1 仅 lib 改 — 不动 bootstrap / parser / interpreter / codegen
- §核心原则 2 callback 重载是 Java/TS 主线(JdbcTemplate.execute(String) + execute(String, PreparedStatementSetter)),CLAUDE.md §Java/TS 语法对齐
- §核心原则 3 既有 5 method 不破 — Phase 3 才 retcon 调用方
- §核心原则 4 元数据 vs 动态值 grep 分类(本 Phase 仅加 callback 重载,Phase 2 才用)
- §核心原则 5 prepared statement Connection 生命周期(execute/update 关 Connection / queryForList 不关 — streaming)
- §核心原则 6 setter 是 fn 类型 callback 不是 PreparedStatementSetter 接口对象(SS fn 类型主线,D025 interface dispatch 仍可后续切)
- §核心原则 7 tests/d135_caching_sha2/ + tests/d136_prepared_statement/ 不动(本 Phase scope 外)
- §核心原则 8-12 见 D137 全文

**§After Done 三步必走**(收尾 gate):
1. `/simplify` 跑 3 agent 并行(reuse / quality / efficiency)
2. commit(2-commit 范式: feat(D137) Phase 1 实施 → docs(D137) Phase 1 hash 回填 + Status 收关 + next_prompt 指向 Phase 2)
3. 写下轮 next_prompt 指向 D137 Phase 2(lib/spring/data.ss 11 处 JpaRepository CRUD retcon)且必含 ultrathink 关键字 + 跑 `bin/ss run tools/next_prompt_ultrathink_linter.ss` GATE PASS
