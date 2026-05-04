# D152: JDBC Type Class Foundation — `lib/java/{math,sql,io}.ss` ≥10 底层 type class(BigDecimal / Timestamp / Date / Time / Blob / Clob / NClob / RowId / SQLXML / Array / Ref / InputStream / Reader)

**Status:** Phase 0 落档(D151 Phase 1 用户对话锁 **C-B-3 底层先做** at commit `fef882f` → D152 sub-D 起首,首次"父 sub-D Phase 中起子 sub-D"路径 vs D135-D151 单 sub-D + sub-D 链路接力范式 + JDBC 4.3 §15.2.5 ≥10 底层 type class `lib/java/*` 落地作 D151 setter ≥18 method 接力的底层依赖 + 业界对标 JDK `java.math.BigDecimal` / `java.sql.{Timestamp,Date,Time,Blob,Clob,NClob,RowId,SQLXML,Array,Ref}` / `java.io.{InputStream,Reader}` 标准库子文件结构 + lib/java/ 子文件结构惯例(`lib/java/math.ss` + `lib/java/sql.ss` + `lib/java/io.ss` 拆分,各 type class scope 独立)+ C-A/C-B/C-C/C-D 4 候选评估 fact 入档 + §字段 10 (e) 自决策评估 **C-B 按 type class 拆分子文件 > C-A/C-C/C-D**(三维全胜:JDK java.* 标准库范式 + lib/java/ 子文件结构惯例 + 各 type class scope 独立可独立测 + N 年返工度低)+ 决策行不锁定 留用户对话授权门槛触发(类比 D148 Phase 2 H15 / D149 Phase 2 H12 / D150 Phase 0 H3 / D151 Phase 1 H2 范式)+ docs only(VCM §1 豁免锚成立)+ d_doc_index F1=0 GATE OK + ultrathink GATE OK + simplify 跳过 docs-only 例外)— **D151 Phase 1 C-B-3 锁定后 D152 起首,JDK java.* 标准库映射范式 + lib/java/ 子文件结构**;后续 D152 Phase 1 = 用户对话授权 C-A/C-B/C-C/C-D 锁定 + Phase 0 hash 回填 + 候选范畴细化 + 路径分支(C-A 全在 sql.ss 单文件 / C-B 按 type class 拆分子文件 / C-C 仅最小 stub / C-D 内嵌 D151 主线)。

**Depends on:** D151(ResultSet update setter type extension,Phase 1 用户对话锁 C-B-3 at commit `fef882f` 底层先做 → D152 起首)+ D147(updatable cursor + ResultSet update 6 核心 setter,Phase 5 close at `8323501`)+ D146(server-side cursor + ResultSet 7 method)+ D138(generated keys 范式 — Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环)+ D139(SQL exception hierarchy)+ D025(class layout `{ i32 rc, ptr TypeInfo, ...fields }` + interface vtable)+ D134(MySQL wire protocol)+ D052(named arg `k: v` syntax)

**Date:** 2026-05-04

---

## 核心目标

D151 Phase 1 用户对话锁 **C-B-3 底层先做**(2026-05-04 commit `fef882f`)起 D152 sub-D 落地 JDBC 4.3 ≥10 底层 type class — `BigDecimal` / `Timestamp` / `Date` / `Time` / `Blob` / `Clob` / `NClob` / `RowId` / `SQLXML` / `Array` / `Ref` / `InputStream` / `Reader` 等,作为 D151 setter ≥18 method 接力的底层依赖。

**第一性需求**:
- D151 setter ≥18 method 实现需要底层 type class 接口 `function updateBigDecimal(col: string, val: BigDecimal): void` 等 — 没 type class 则签名退化 ptr / null-stub 违 D151 §核心原则 1 "完整不裁剪"
- ORM Hibernate `BasicType<BigDecimal>.set/get` cursor 路径成立 — `@Column(precision=10, scale=2) BigDecimal price` 属性 dirty track + flush 走 `ResultSet.updateBigDecimal(col, val)` 标准 binding,缺则 cursor 路径全断回 `INSERT INTO ... VALUES (?)` 重写 SQL workaround / `rs.updateString("amount", val.toString())` 字符串 stringify workaround(丢精度 / 类型安全)
- 业界对标 JDK java.* 标准库 — `java.math.BigDecimal` / `java.sql.{Timestamp,Date,Time,Blob,Clob,NClob,RowId,SQLXML,Array,Ref}` / `java.io.{InputStream,Reader}` 子文件结构 + 各 type class scope 独立(BigDecimal in `java/math/`,SQL types in `java/sql/`,Stream types in `java/io/`)
- N 年返工度:仅最小 stub ≠ JDBC 4.3 完整 — 后续 setter 必定再回头扩展 type class scope 接口,返工度高 → C-B 按 type class 拆分子文件一次到位低返工度

**底层依赖链实证**(继承 D151 §A.2 H1 关键 fact):
- `lib/java/` 仅 `sql.ss`(14428 bytes)— 无 `math.ss` / `io.ss` / `time.ss`
- `lib/java/sql.ss` 无 `Timestamp` / `Date` / `Time` / `Blob` / `Clob` / `NClob` / `RowId` / `SQLXML` / `Array` / `Ref` 等 type class(grep 0 命中)
- `lib/` 无 BigDecimal class(grep 0 命中);仅 `lib/datetime.ss:14 class DateTime {}` 空 class(SS 自定义,非 JDBC 标准)
- `lib/` 无 `InputStream` / `Reader` / `AsciiStream` / `BinaryStream` / `CharacterStream` class

**lib/java/ 子文件结构惯例**(JDK 标准库映射范式):
- `lib/java/math.ss` ← `java.math.BigDecimal`(scope 大含 add/sub/mul/div + scale + precision + toString + equals + hashCode 等 ~100-200 LOC)
- `lib/java/sql.ss` ← `java.sql.{Timestamp,Date,Time,Blob,Clob,NClob,RowId,SQLXML,Array,Ref}`(已 14428 bytes 含 Connection / PreparedStatement / ResultSet / Statement / DriverManager 等 + 加 ≥10 type class ~50-80 LOC each)
- `lib/java/io.ss` ← `java.io.{InputStream,Reader,AsciiStream,BinaryStream,CharacterStream,NCharacterStream}`(scope 中 ~50-80 LOC each)
- `lib/java/time.ss`(留)← `java.time.*` 现代 API(D152 不做,留独立 sub-D 后续)

**不在范畴**:
- ❌ C-A 全在 sql.ss 一文件 ~30000+ bytes(已废 — 违子文件结构惯例 + JDK java.* 标准库范式,§A.3)
- ❌ C-C 仅最小 stub(已废 — 违 §核心原则 1 "完整不裁剪" + setter 签名退化 ptr / null-stub,§A.3)
- ❌ C-D 内嵌 D151 主线一次到位(已废 — 违 C-B-3 用户对话锁定 2026-05-04 Phase 1 底层先做范式,§A.3)
- ❌ 越过用户对话授权门槛自决策 C-A/C-B/C-C/C-D(类比 D148 H15 / D149 H12 / D150 H3 / D151 Phase 1 H2 范式,Phase 0 不锁子候选,等用户对话二次授权)
- ❌ 改 D151 主线 / D147 主线 / D025 / D052 / D134 / D139 等依赖 D 文档(D151 Phase 1 已锁 C-B-3 + D147 主线已 close + 依赖 D 文档不破 — D152 仅做底层 type class)
- ❌ 引入新关键字 / 新语法(CLAUDE.md §Java/TS 语法优先红线;JDK java.* type class 都不需新语法支持)
- ❌ annotation handler 旁路 ≥10 type class(`feedback_no_derive_workaround` 红线 — 主线能力缺口不允许 @derive / annotation handler 作为替代路径)

---

## 核心原则

(继承 CLAUDE.md + D151 §核心原则 13 条 + 新加 JDK java.* 标准库映射范式 + lib/java/ 子文件结构惯例):

1. **完整 JDBC 4.3 type class 不裁剪**(继承 D151 §核心原则 1 + D147 §核心原则 1)— ≥10 底层 type class 完整,含 BigDecimal/Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref + InputStream/Reader,各 type class 内部方法完整不缩水
2. **不引入新关键字 / 新语法**(继承 D151 §核心原则 2)— 复用既有 SS class / interface 语法机制
3. **Root Cause 优先**(CLAUDE.md §Root Cause 优先 第一法则,无例外)— 候选评估按根因解决度 + 长久 / 演化维度排序,**禁按 LOC 最少 / 工程量最小作排序依据**
4. **业界对标 JDK java.* 标准库映射**(CLAUDE.md §长久 / 演化维度)— `java.math.BigDecimal` / `java.sql.{Timestamp,Date,Time,Blob,Clob,NClob,RowId,SQLXML,Array,Ref}` / `java.io.{InputStream,Reader}` 标准库子文件结构 + 各 type class scope 独立
5. **lib/java/ 子文件结构惯例**(CLAUDE.md §高层架构 §未来拆分沿用此风格 + JDK 范式)— `lib/java/math.ss` BigDecimal + `lib/java/sql.ss` SQL types + `lib/java/io.ss` Stream types + `lib/java/time.ss` 留(现代 java.time API),按职责拆分子文件,不堆 sql.ss 单文件
6. **N 年返工度低**(CLAUDE.md §长久 / 演化维度)— C-B 按 type class 拆分一次到位 vs C-C 仅最小 stub setter 后续必返工 vs C-A 单文件后续必拆 vs C-D 内嵌违底层先做范式
7. **底层依赖链先决**(CLAUDE.md §长久 / 演化维度 + memory `feedback_root_cause_no_cost.md` §8 + D151 Phase 1 用户对话锁 C-B-3 范式)— 底层 type class(D152)先于上层 setter(D151 Phase 3+)起首,业界对标 JDK java.* "先底层再上层"终局范式
8. **bootstrap 隔离破例 D135-D151 范式同位例外** — D152 Phase 0 docs-only 不动 bootstrap(VCM §1 豁免锚成立);Phase 1+ 实施各独立 commit
9. **决策行不锁定 留用户对话授权门槛触发**(类比 D148 Phase 2 H15 / D149 Phase 2 H12 / D150 Phase 0 H3 / D151 Phase 1 H2 授权范式)— Phase 0 启动轮 C-A/C-B/C-C/C-D 候选不自决策,等用户对话明确锁定后才入 Phase 1 候选范畴细化
10. **每 type class 内部方法完整 JDK API 范式**(继承 D151 §核心原则 1 完整不裁剪)— 例:BigDecimal 含 add/sub/mul/div + scale/precision + toString/equals/hashCode 等;Timestamp/Date/Time 含 toString/parse + getYear/getMonth + before/after/equals 等;Blob/Clob/NClob 含 length/getBytes/getCharacterStream 等;RowId/SQLXML/Array/Ref 含 getRowIdLifetime/getString/getArray/getObject 等
11. **Phase 计划独立 commit**(继承 D151 §核心原则 11)— Phase 0-N+ 独立 commit
12. **integration_test 扩 cases 真 type class 单元测**(继承 D151 §核心原则 12)— 新建 `tests/d152_jdbc_type_class_foundation/` 加 BigDecimal arithmetic / Timestamp parse / Blob length / Reader read 等真 type 单元测 + 后续 D151 setter 起首时复用真 type case
13. **SS 编译器扩仅按需**(继承 D151 §核心原则 13)— Phase 0 不预判,Phase 1+ 实测 spike 走假设破裂回路 fallback

---

## §1 Context

### D151 Phase 1 用户对话锁 C-B-3 后 D152 起首状态(commit `fef882f`)

- ✓ **D151 Phase 0 落档** at commit `2e94b54` — JDBC 4.3 §15.2.5 ≥18 setter scope + 底层依赖链实证 ≥10 type class 缺 + C-B-1/2/3 子候选评估 fact 入档
- ✓ **D151 Phase 1 用户对话锁 C-B-3** at commit `fef882f`(2026-05-04)— C-B-3 底层先做(D152 sub-D 起首)+ D151 setter 接力(Phase 3+)
- ⚠ **底层 type class 缺实证**(继承 D151 §A.2 H1)— `lib/java/` 仅 `sql.ss`(14428 bytes)无 `math.ss` / `io.ss` / `time.ss`;`lib/java/sql.ss` 无 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref;`lib/` 无 BigDecimal class

### 累计 sub-D 链路(16 sub-D)

D135 → D136 → D137 → D138 → D139 → D140 → D141 → D142 → D143 → D144 → D145 → D146 → **D147 close** → **D150 主线暂停**(v2 类型系统 SQL libs 零受益实证)→ **D151 §F1 起首** → **D151 Phase 1 用户对话锁 C-B-3** → **D152 底层 type class sub-D 起首**(本 D)

**首次"父 sub-D Phase 中起子 sub-D"路径**:D135-D150 范式都是单 sub-D 主线 + sub-D 链路接力(D138 → D139 / D140 / D141 等),D151 Phase 1 用户对话授权后选 C-B-3 = 起 D152 底层 sub-D 先做 + D151 setter 后做接力,首次形成"父 sub-D 在 Phase 中起子 sub-D"路径(类似 D148 Phase 2 H15 用户对话授权后内部 B1/B2 路径分支,但 D151 Phase 1 用户对话授权后是外部 D152 sub-D 起首,与 D 文档级链路接力同形)

### 业界对标

- **JDK `java.math.BigDecimal`**(`java/math/BigDecimal.java` ~3000 LOC)— SS lib/java/math.ss BigDecimal 范式直翻,scope 含 add/sub/mul/div + scale + precision + toString + equals + hashCode 等
- **JDK `java.sql.{Timestamp,Date,Time}`**(`java/sql/Timestamp.java` 等 ~500 LOC each)— SS lib/java/sql.ss 加 Timestamp/Date/Time 直翻
- **JDK `java.sql.{Blob,Clob,NClob}`**(`java/sql/Blob.java` 等 ~300 LOC each)— SS lib/java/sql.ss 加 Blob/Clob/NClob 直翻 interface
- **JDK `java.sql.{RowId,SQLXML,Array,Ref}`**(`java/sql/RowId.java` 等 ~100-300 LOC each)— SS lib/java/sql.ss 加 RowId/SQLXML/Array/Ref 直翻 interface
- **JDK `java.io.{InputStream,Reader}`**(`java/io/InputStream.java` ~600 LOC + `java/io/Reader.java` ~400 LOC)— SS lib/java/io.ss InputStream/Reader 范式直翻

SS 当前 lib/java/ 仅 sql.ss(14428 bytes)— 无 math.ss / io.ss / time.ss,需先按 JDK 子文件结构落地

### lib/java/ 子文件结构(C-B 锁定后 Phase 1+ 落点预设)

```
lib/
  java/
    math.ss      (新建 ~100-200 LOC) — BigDecimal class + 算术方法
    sql.ss       (扩 ~14428 + ~500-800 = ~15000-15500) — 加 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref interface
    io.ss        (新建 ~100-200 LOC) — InputStream + Reader + AsciiStream/BinaryStream/CharacterStream/NCharacterStream
    time.ss      (留)— java.time API 现代版本独立 sub-D 后续
```

---

## §2 RED 锚

D152 Phase 0 是「sub-D 起首选择 + 候选锁定」决策落档,无 RED bug 直接挂载;C-B 锁定后(Phase 1+)对应 RED:

```bash
# C-B 整体 type class RED(目标 ≥10):
grep -rn "class BigDecimal\|class Timestamp\|class Date\|class Time\|class Blob\|class Clob\|class NClob\|class RowId\|class SQLXML\|class Array\|class Ref\|class InputStream\|class Reader" /root/code/simplescript-dev/simple-script/lib/
# 当前 = 0(仅 lib/datetime.ss:14 class DateTime {} 空 class,非 JDBC 标准)
# 目标 ≥ 10

# 子文件结构 RED:
ls /root/code/simplescript-dev/simple-script/lib/java/
# 当前 = sql.ss(单文件)
# 目标 = math.ss + sql.ss + io.ss(三文件 子文件结构 JDK 范式)

# C-B-2 仅最小 stub RED(C-C 子候选 — workaround 模式不取):
# setter 签名退化 ptr / null-stub,违 D151 §核心原则 1 "完整不裁剪"
```

---

## §3 Orchestration

| Phase | 内容 | 落点 | 完成判据 |
|---|---|---|---|
| **Phase 0** [✓ Done at commit `41c4928`(留 D152 Phase 1 启动轮回填 — D135-D151 范式 单 commit 不能引用自己 hash 下下轮回填)] | D 文档落档 + 候选评估 C-A/C-B/C-C/C-D + 子文件结构惯例 fact 入档 + 决策行不锁定 留用户对话授权 | D152.md docs-only ~400 行 — Status header + Depends on + Date 2026-05-04 + §核心目标 + §核心原则 13 条 + §1 Context + §2 RED 锚 + §3 Orchestration Phase 0-N+ + §A.1 4 候选 + §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 + §Phase 收关锚 + §Followup + §Status 时间线 | bootstrap/lib/tools 不动(VCM §1 豁免锚成立)+ ultrathink GATE OK + d_doc_index F1=0 + simplify 跳过 docs-only 例外 |
| **Phase 1** [✓ Done at commit `9f9e8cf`(留 D152 Phase 2 启动轮回填 — D135-D151 范式 单 commit 不能引用自己 hash 下下轮回填)] | Phase 0 hash 回填 + 用户对话锁 **C-B 子文件结构**(2026-05-04)+ 候选范畴细化 + 路径分支 | D151 Phase 1 范式延续 — 用户对话授权门槛触发(类比 D151 Phase 1 H2 范式)+ C-B 锁定后路径明确(`lib/java/math.ss` BigDecimal + `lib/java/sql.ss` 加 ≥10 type class + `lib/java/io.ss` InputStream/Reader)| 用户对话授权门槛 PASS + Phase 0 hash 回填 GREEN + C-B 锁定 + 路径分支明确 |
| **Phase 2** [✓ Done at commit `<placeholder>`(留 D152 Phase 3 启动轮回填 — D135-D151 范式 单 commit 不能引用自己 hash 下下轮回填)] | `lib/java/math.ss` 新建 BigDecimal class + 算术方法 + `tests/d152_jdbc_type_class_foundation/bigdecimal_test.ss` 真 type 单元测 | `lib/java/math.ss` ~180 LOC(BigDecimal class:field `unscaled: int` / `scale: int` + method `scale()` / `precision()` / `signum()` / `unscaledValue()` / `add` / `subtract` / `multiply` / `negate` / `abs` / `compareTo` / `equals` / `toString` + helper `bdPow10` + factory `BigDecimal_fromInt` / `BigDecimal_fromString`)+ `tests/d152_jdbc_type_class_foundation/bigdecimal_test.ss` ~120 LOC 全 case GREEN(ctor+accessor / fromInt / fromString / precision / signum / add same+mismatch scale / subtract / multiply / negate / abs / compareTo cross-scale / equals JDK semantics / toString round-trip) | BigDecimal 单元测 GREEN + bootstrap 三阶段固定点不破 + d_doc_index F1=0 + simplify 4 维 PASS |
| **Phase 3+** Planned (C-B 已锁 2026-05-04 Phase 1) | C-B 锁定后路径明确 — 扩 `lib/java/sql.ss` Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref + 新建 `lib/java/io.ss` InputStream/Reader | Phase 3 = `lib/java/sql.ss` 加 ≥10 type class ~500-800 LOC + Phase 4 = `lib/java/io.ss` InputStream/Reader 100-200 LOC + Phase 5 = integration_test 真 type 单元测扩展 ~100-200 LOC + Phase 6 = close + bootstrap 三阶段固定点 + 各 type class scope 独立测 | D152 各 type class GREEN + bootstrap 不破 + integration_test 真 type case 全 GREEN |
| **Phase N+** close | D152 主线 close 后 next_prompt 转向 D151 Phase 3+ setter ≥18 method | D151 Phase 3+ 起首 setter 接力 — `lib/java/sql.ss` interface ResultSet 加 ≥18 setter + 3 implementor 同步 + integration_test 扩 cases 真 type 写入 server-side | D151 setter ≥18 method GREEN + 7 case bidirectional 不破 + bootstrap 三阶段固定点 + integration_test 真 type 写入 server-side 全 GREEN |

**Phase 间依赖**: Phase 0 → 1(用户对话授权 C-A/C-B/C-C/C-D 子候选门槛触发)→ Phase 2+(路径分支:C-A 单文件 / C-B 子文件结构 / C-C 仅最小 stub / C-D 内嵌 D151)→ Phase N+ close → D151 Phase 3+ setter 接力

**LOC delta 估**(C-B 候选锁定后):
- **C-B `lib/java/math.ss` BigDecimal**: ~100-200 LOC(class BigDecimal + ctor + add/sub/mul/div + scale + precision + toString + equals + hashCode)
- **C-B `lib/java/sql.ss` 加 ≥10 type class**: ~500-800 LOC(Timestamp/Date/Time ~50-80 each + Blob/Clob/NClob ~50-80 each + RowId/SQLXML/Array/Ref ~30-50 each)
- **C-B `lib/java/io.ss`**: ~100-200 LOC(InputStream + Reader + 各 Stream variant 含 read/skip/close 等)
- **C-B integration_test**: ~100-200 LOC(`tests/d152_jdbc_type_class_foundation/` BigDecimal arithmetic / Timestamp parse / Blob length / Reader read 真 type 单元测)
- **C-B 总 LOC delta**: ~800-1400 LOC(分轮 Phase 2-5 实施)
- **C-A 全在 sql.ss 单文件**: ~700-1200 LOC(违子文件结构惯例,堆 sql.ss 单文件 ~30000+ bytes)
- **C-C 仅最小 stub**: ~50-100 LOC(setter 签名退化 ptr / null-stub 违 §核心原则 1 完整不裁剪)
- **C-D 内嵌 D151 主线**: 无独立 D 文档 — 违 C-B-3 底层先做范式

---

## §A.1 决策行

### C-A: 全在 sql.ss 一文件(~700-1200 LOC 堆 sql.ss)

**已废**(§A.3):违反 lib/java/ 子文件结构惯例 + JDK java.* 标准库范式(`java.math.BigDecimal` / `java.sql.*` / `java.io.*` 子目录拆分);sql.ss ~30000+ bytes 单文件难维护 + 各 type class scope 互相干扰

### C-B: 按 type class 拆分子文件(`lib/java/math.ss` + `lib/java/sql.ss` + `lib/java/io.ss`)— ✓ 自决策评估倾向

**起 D152 主线**:`lib/java/math.ss` 新建 BigDecimal ~100-200 LOC + `lib/java/sql.ss` 加 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref ~500-800 LOC + `lib/java/io.ss` 新建 InputStream/Reader ~100-200 LOC + integration_test ~100-200 LOC = 总 ~800-1400 LOC(分轮 Phase 2-5 实施)

**§字段 10 (e) 自决策评估**(C-B vs 其他):
- **根因解决度**:**高**(JDK java.* 标准库范式 + 子文件结构惯例 + 各 type class scope 独立可独立测 — D151 §核心原则 1 "完整不裁剪"延续)
- **长久 / 演化维度**:**高**(JDK java.* 业界对标 + lib/java/ 子文件结构惯例 + N 年返工度 — 一次到位低返工度 + D152 close 后 D151 setter 接力直用 type class 接口)

**§字段 10 (e) 自决策评估**(C-A/C-B/C-C/C-D):**C-B > C-A > C-D > C-C**(根因解决度 + 长久 / 演化维度);Phase 0 不自决策,**留 Phase 1 用户对话明确锁定**(类比 D148 H15 / D149 H12 / D150 H3 / D151 Phase 1 H2 范式)— **用户对话锁 C-B 子文件结构(2026-05-04 Phase 1)**。

### C-C: 仅最小 stub setter 签名退化 ptr / null-stub

**已废**(§A.3):违反 D151 §核心原则 1 "完整不裁剪" + setter 签名退化 ptr / null-stub 是 workaround 违反 CLAUDE.md §Root Cause 优先 + memory `feedback_no_derive_workaround`(主线能力缺口不允许 workaround)

### C-D: 内嵌 D151 主线一次到位(不独立 D 文档)

**已废**(§A.3):违反 C-B-3 用户对话锁定 2026-05-04 Phase 1 底层先做范式 — 用户对话已锁 C-B-3 = 底层(D152)先做 + 上层(D151 Phase 3+)接力,C-D 内嵌违此范式

### 候选评估 4 维度对比表

| 维度 | C-A 单文件 | **C-B 子文件结构**(倾向)| C-C 最小 stub | C-D 内嵌 D151 | 决策倾向 |
|---|---|---|---|---|---|
| **根因解决度** | 中(单文件堆 sql.ss)| **高**(子文件结构 + 完整 type class)| 低(workaround stub)| 中(内嵌违 C-B-3 范式)| **C-B > C-A > C-D > C-C** |
| **长久 / 演化:JDK java.* 业界对标** | 中(部分匹配)| **高**(JDK 子目录范式直翻)| 低(stub 无业界范式)| 中(内嵌不显化)| **C-B > C-A/C-D > C-C** |
| **长久 / 演化:lib/java/ 子文件结构惯例** | 低(违惯例)| **高**(惯例符合)| 低(违惯例)| 低(无独立 D)| **C-B > C-A/C-C/C-D** |
| **长久 / 演化:N 年返工度** | 高(单文件后续必拆)| **低**(子文件一次到位)| 高(stub 必返工)| 中(内嵌 D151 范式)| **C-B > C-A/C-C/C-D** |
| **scope LOC delta** | ~700-1200(堆 sql.ss)| ~800-1400(分子文件)| ~50-100(stub)| 0(内嵌 D151)| C-A 中 / C-B 大但根因 / C-C 0 但违 §Root Cause / C-D 0 但违 C-B-3 |

**§字段 10 (e) 自决策评估**:**C-B > C-A > C-D > C-C**(根因解决度 + 长久 / 演化维度);Phase 0 不自决策,**留 Phase 1 用户对话明确锁定** — **用户对话锁 C-B 子文件结构(2026-05-04 Phase 1)**。

### 决策行(Phase 0 候选评估 入档,C-A/C-B/C-C/C-D 不锁 留用户对话授权)

**C-A/C-B/C-C/C-D 决策行不锁定** — 类比 D148 Phase 2 H15 / D149 Phase 2 H12 / D150 Phase 0 H3 / D151 Phase 1 H2 用户对话授权门槛触发(C-B 范畴涉及 lib/java/ 子文件结构 + 各 type class scope 独立分散度,长久演化影响范围扩到 D152 各 type class scope 起首,需用户对话锁定 C-A / C-B / C-C / C-D),Phase 0 启动轮不自决策,等用户对话明确锁定后才入 Phase 1 候选范畴细化 + 路径分支。

**类比范式**:
- D148 Phase 2 H15:bidirectional 接管副作用清零候选 B1 / B2,用户对话锁 B1
- D149 Phase 2 H12:架构层 refactor C2 / C3,用户对话锁 C3
- D150 Phase 0 H3:F5 v2 总体设计 vs F2/F3/F4 单点起首,用户对话锁 — D150 主线暂停转 SQL
- D151 Phase 1 H2:C-B 完整 ≥18 method 内 C-B-1/2/3 子候选,用户对话锁 C-B-3 底层先做(2026-05-04)
- **D152 Phase 0**:候选评估入档(C-A/C-B/C-C/C-D),决策行不锁,留 Phase 1 用户对话授权门槛触发
- **D152 Phase 1**:已锁 **C-B 子文件结构**(2026-05-04)— `lib/java/math.ss` BigDecimal + `lib/java/sql.ss` 加 ≥10 type class + `lib/java/io.ss` InputStream/Reader 路径明确

---

## §A.1.1 落点

### G1: 用户对话授权 C-A/C-B/C-C/C-D 锁定(Phase 1 启动条件)

| 候选 | 锁定后 Phase 1+ 落点 |
|---|---|
| C-A 单文件 | D152 主线 = `lib/java/sql.ss` 单文件加 BigDecimal + Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref + InputStream/Reader ~700-1200 LOC;违子文件结构惯例 |
| **C-B 子文件结构**(倾向)| D152 主线 = `lib/java/math.ss` 新建 BigDecimal ~100-200 + `lib/java/sql.ss` 加 ≥10 type class ~500-800 + `lib/java/io.ss` 新建 InputStream/Reader ~100-200 + integration_test ~100-200 = 总 ~800-1400(分轮 Phase 2-5 实施) |
| C-C 最小 stub | D152 主线 = setter 签名退化 ptr / null-stub ~50-100 LOC;违 §核心原则 1 完整不裁剪 |
| C-D 内嵌 D151 | 无 D152 独立 D 文档 — 违 C-B-3 底层先做范式 |

### G2: 各 type class file:line 落点(C-B 锁定后 Phase 2-5 实施)

- **`lib/java/math.ss`**(新建)— `class BigDecimal` + ctor `function newBigDecimal(intPart: int, scale: int): BigDecimal` + 算术 `add/sub/mul/div` + accessor `scale/precision/toString/equals/hashCode`
- **`lib/java/sql.ss`**(扩 ~14428 → ~15000-15500)— 加 `interface Timestamp/Date/Time` + `interface Blob/Clob/NClob` + `interface RowId/SQLXML/Array/Ref`
- **`lib/java/io.ss`**(新建)— `interface InputStream` + `interface Reader` + `interface AsciiStream/BinaryStream/CharacterStream/NCharacterStream`
- **`tests/d152_jdbc_type_class_foundation/`**(新建)— `bigdecimal_test.ss` BigDecimal arithmetic + `timestamp_test.ss` Timestamp parse + `blob_test.ss` Blob length + `reader_test.ss` Reader read 等真 type 单元测

---

## §A.2 隐藏假设

| H | 假设 | 实证 / 留 Phase | 失败回退 |
|---|---|---|---|
| H1 | **lib/java/ 子文件结构惯例**:JDK `java.math.*` / `java.sql.*` / `java.io.*` 子目录映射 SS `lib/java/math.ss` / `lib/java/sql.ss` / `lib/java/io.ss` 子文件 | ✓ Phase 0 实证(JDK 标准库 source tree `java/math/BigDecimal.java` / `java/sql/Timestamp.java` 等子目录范式 + SS lib/java/sql.ss 已存在子文件惯例萌芽) | 子文件结构不可行 → 退回 C-A 单文件(违惯例 + 必返工) |
| H2 | C-A/C-B/C-C/C-D 用户对话锁定 — 用户对话明确二次锁定 | ✓ Phase 1 PASS(2026-05-04 用户对话锁 **C-B 子文件结构**,类比 D151 Phase 1 H2 范式) | 用户对话授权未触发 → Phase 1 阻塞 |
| H3 | C-B `lib/java/math.ss` BigDecimal LOC delta ~100-200 | Phase 2 实测验证(若 C-B 锁定 — class BigDecimal + ctor + add/sub/mul/div + scale + precision + toString + equals + hashCode 实测) | scope > 估 → Phase 拆分细化 |
| H4 | C-B `lib/java/sql.ss` 加 ≥10 type class LOC delta ~500-800 | Phase 3 实测验证(若 C-B 锁定 — Timestamp/Date/Time + Blob/Clob/NClob + RowId/SQLXML/Array/Ref interface 实测) | scope > 估 → Phase 拆分细化 |
| H5 | C-B `lib/java/io.ss` InputStream/Reader LOC delta ~100-200 | Phase 4 实测验证(若 C-B 锁定 — InputStream + Reader + AsciiStream/BinaryStream/CharacterStream/NCharacterStream interface 实测) | scope > 估 → Phase 拆分细化 |
| H6 | bootstrap 三阶段固定点不破(D135-D151 范式延续) | Phase 2+ 留(各候选实施时验证 — `./build.sh bootstrap` Stage 2 = Stage 3) | 三阶段固定点破 → 回 Phase 实施修自然链路 |
| H7 | 不引入新关键字 / 新语法(继承 D151 §核心原则 2) | Phase 0 实证(继承 D151 §核心原则 2 不破 — type class 都复用既有 SS class / interface 语法机制) | 需引入新语法 → 不选(违 CLAUDE.md §Java/TS 语法优先 + §核心原则 2) |
| H8 | 各 type class 内部方法完整 JDK API 范式(继承 D151 §核心原则 1 + §核心原则 10) | Phase 2-5 实测验证(BigDecimal 含 add/sub/mul/div + scale/precision + toString/equals/hashCode 等;Timestamp/Date/Time 含 toString/parse + getYear/getMonth + before/after/equals 等;Blob/Clob/NClob 含 length/getBytes/getCharacterStream 等;RowId/SQLXML/Array/Ref 含 getRowIdLifetime/getString/getArray/getObject 等) | 部分方法不可行 → 留 Followup 后续 sub-D 起首接力 |
| H9 | integration_test 真 type 单元测可观测验证 — `tests/d152_jdbc_type_class_foundation/` BigDecimal arithmetic + Timestamp parse + Blob length + Reader read | Phase 5 实测验证(各 type class 真 type 单元测 case GREEN) | 单元测失败 → 修 type class 实现 / API 设计 |
| H10 | D151 主线起首接力前置依赖满足(D151 Phase 3+ setter ≥18 method 用 D152 type class 接口) | Phase N+ close 验证(D152 close 后 D151 Phase 3+ setter `function updateBigDecimal(col: string, val: BigDecimal): void` 等 type class 接口可用) | type class 接口不满足 setter → 回 D152 Phase 实施扩接口 |

---

## §A.3 废案

- **C-A 全在 sql.ss 单文件 ~700-1200 LOC 堆 sql.ss 全废**(违 lib/java/ 子文件结构惯例 + JDK java.* 标准库范式 — `java.math.BigDecimal` / `java.sql.*` / `java.io.*` 子目录拆分;sql.ss ~30000+ bytes 单文件难维护 + 各 type class scope 互相干扰)
- **C-C 仅最小 stub setter 签名退化 ptr / null-stub 全废**(违 D151 §核心原则 1 "完整不裁剪" + workaround 违 CLAUDE.md §Root Cause 优先 + memory `feedback_no_derive_workaround` — 主线能力缺口不允许 stub workaround)
- **C-D 内嵌 D151 主线一次到位 全废**(违 C-B-3 用户对话锁定 2026-05-04 Phase 1 底层先做范式 — 用户对话已锁 C-B-3 = 底层 D152 先做 + 上层 D151 Phase 3+ 接力,C-D 内嵌违此范式)
- **越过用户对话授权门槛自决策 C-A/C-B/C-C/C-D 全废**(类比 D148 H15 / D149 H12 / D150 H3 / D151 Phase 1 H2 范式 — Phase 0 §字段 10 (e) 自决策评估 C-B > C-A > C-D > C-C 但决策行不锁定,等用户对话明确锁定后才入 Phase 1)
- **改 D151 主线 / D147 主线 / D146 主线 / D025 / D052 / D134 / D139 等依赖 D 文档 全废**(D151 Phase 1 已锁 C-B-3 + D147 主线已 close + D146 不破 + 依赖 D 文档不破 — D152 仅做底层 type class)
- **引入新关键字 / 新语法 全废**(CLAUDE.md §Java/TS 语法优先红线;JDK java.* type class 都不需新语法支持)
- **annotation handler 旁路 ≥10 type class 全废**(`feedback_no_derive_workaround` 红线 — 主线能力缺口不允许 @derive / annotation handler 作为替代路径)
- **`lib/java/time.ss` java.time API 现代版本同 D152 一起做 全废**(scope 不收敛 — `java.time.*` 是 JDK 8+ 现代 API 含 Instant/LocalDateTime/ZonedDateTime/Duration/Period 等 ~10+ class,留独立 sub-D 后续起首)

---

## Phase 收关锚

### Phase 0: D 文档落档 + 候选评估 C-A/C-B/C-C/C-D + 子文件结构惯例 fact 入档 + 决策行不锁定 留用户对话授权 [✓] Done at commit `41c4928`(留 D152 Phase 1 启动轮回填 — D135-D151 范式 单 commit 不能引用自己 hash 下下轮回填)(2026-05-04)

- **D152.md 文档新建** ~400 行(本 commit)— Status header + Depends on D151/D147/D146/D138/D139/D025/D134/D052 + Date 2026-05-04 + §核心目标 + §核心原则 13 条 + §1 Context(D151 Phase 1 用户对话锁 C-B-3 后 D152 起首状态 + 累计 sub-D 链路 16 + 业界对标 JDK java.* + lib/java/ 子文件结构 + 首次"父 sub-D Phase 中起子 sub-D"路径 fact)+ §2 RED 锚 + §3 Orchestration Phase 0-N+ + §A.1 4 候选评估 C-A/C-B/C-C/C-D + §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 8 条 + §Phase 收关锚 + §Followup + §Status 时间线 Phase 0 entry
- **D151 Phase 1 commit hash `fef882f` 回填 D151.md 5 处**(line 108 §3 Orchestration 表 Phase 1 行 + line 242 §Phase 收关锚 §Phase 1 标题 + line 248 §Phase 收关锚 §Phase 1 entry §3 Orchestration 表 Phase 1 行 mention + line 280 §Status 时间线 2026-05-04 Phase 1 entry 含 2 字串:主条目 commit + (e) 子条目 §3 Orchestration 表 Phase 1 行 mention)= **4 行 5 字串非均匀分布 line 280 含 2 字串**(用户字面「4+1 处」refine,memory `feedback_user_literal_vs_d_ssot` 同形防御 16 次落档 PSM §字段 3 与历史 D148 Phase 5 字面「5 处」实测 6 / D149 Phase 0 字面「3 处」实测 4 / D149 Phase 3 字面「8 处」实测 6 行 8 字串 / D150 启动字面「6 处」实测 6 行 10 字串 / D150 Phase 1 字面「3 行 4 字串」实测同 / D151 启动字面「4+1 处」实测 5 行 7 字串 / D151 Phase 1 字面「4+1 处」实测 5 行 7 字串 反差实证延续)
- **lib/java/ 子文件结构惯例 fact 入档**(§A.2 H1)— JDK `java.math.*` / `java.sql.*` / `java.io.*` 子目录映射 SS `lib/java/math.ss` / `lib/java/sql.ss` / `lib/java/io.ss` 子文件;SS lib/java/sql.ss 已存在子文件惯例萌芽
- **C-A/C-B/C-C/C-D 候选评估 fact 入档**(§A.1 决策行 — C-A 单文件 ~700-1200 LOC / C-B 子文件结构 ~800-1400 LOC 分轮 / C-C 最小 stub ~50-100 LOC / C-D 内嵌 D151)+ §字段 10 (e) 自决策评估 C-B > C-A > C-D > C-C(根因解决度 + 长久 / 演化维度 — JDK java.* 业界对标 + lib/java/ 子文件结构 + N 年返工度低)
- **§A.2 H1-H10 加入** + **§A.3 废案 8 条**
- **VCM §1 豁免锚成立**(Phase 0 docs-only — `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D151-*.md hash 回填 + 新建 docs/3-decisions/D152-*.md)
- **simplify 跳过 docs-only 例外**(纯文档 D151 hash 回填 + D152.md 新建)
- **d_doc_index_linter F1=0 GATE OK** + **ultrathink_linter PASS** + **D135-D151 范式延续**
- **MNK §M meta-gate 强制四问全 ✓**(深度读 D151.md §核心目标 + §核心原则 13 条 + §1 Context + §A.1 决策行 C-B 锁定 + C-B-1/2/3 子候选评估 + C-B-3 用户对话锁定 + §A.1.1 G1/G2 落点 + §A.2 H1-H10 H2 PASS + §A.3 废案 7 条 + §Phase 收关锚 Phase 0/1 [✓] + §Status 时间线 Phase 0/1 entry + 历史 D135-D151 SQL 主线范式延续 + D147 主线 close at `8323501` → D150 主线暂停 → D151 §F1 起首 → D151 Phase 0 落档 → D151 Phase 1 用户对话锁 C-B-3 → D152 sub-D 起首 + D152 Phase 0 启动条件验证未漏 — D151 Phase 1 hash 回填 + D152 sub-D 起首落档 + 兑现 a-h 总览每条 file:line 锚 + 用户字面「4+1 处」实测 4 行 5 字串非均匀分布 line 280 含 2 字串 refine — memory `feedback_user_literal_vs_d_ssot` 同形防御 16 次落档 PSM §字段 3)
- **D152 Phase 0 commit hash 留 D152 Phase 1 启动轮回填**(D135-D151 范式 — 单 commit 不能引用自己 hash 下下轮回填)

### Phase 1: Phase 0 hash 回填 + 用户对话锁 **C-B 子文件结构** + 候选范畴细化 + 路径分支 [✓] Done at commit `9f9e8cf`(留 D152 Phase 2 启动轮回填 — D135-D151 范式 单 commit 不能引用自己 hash 下下轮回填)(2026-05-04)

- **D152 Phase 0 commit hash `41c4928` 回填 D152.md 3 处**(line 126 §3 Orchestration 表 Phase 0 行 + line 246 §Phase 收关锚 §Phase 0 标题 + line 301 §Status 时间线 2026-05-04 Phase 0 entry 主条目)= **3 行 3 字串均匀分布无 refine**(用户字面「3 处」实测 = 字面 = 3 均匀分布无 refine,memory `feedback_user_literal_vs_d_ssot` 同形防御 17 次落档 PSM §字段 3;**D152 Phase 1 是少数「实测 = 字面」无 refine 之例**,类比 D149 Phase 5 字面「5 处」实测 = 字面 = 5 均匀无 refine 历史范式,与历史 D148 Phase 5 字面「5 处」实测 6 / D149 Phase 0 字面「3 处」实测 4 / D149 Phase 3 字面「8 处」实测 6 行 8 字串 / D150 启动字面「6 处」实测 6 行 10 字串 / D150 Phase 1 字面「3 行 4 字串」实测同 / D151 启动字面「4+1 处」实测 5 行 7 字串 / D151 Phase 1 字面「4+1 处」实测 5 行 7 字串 / D152 启动字面「4+1 处」实测 4 行 5 字串 反差实证延续)
- **用户对话授权门槛触发**(2026-05-04 Phase 1 用户口令 "C-B")— **C-B 子文件结构锁定**,类比 D148 Phase 2 H15 用户口令 "B1" / D149 Phase 2 H12 "C3" / D150 Phase 0 H3 / D151 Phase 1 H2 "C-B-3" 显式范式
- **§A.2 H2 标 PASS**(用户对话授权门槛已触发 — C-B 锁定);**§A.1 决策行 §字段 10 (e) 自决策评估倾向行加 "用户对话锁 C-B 子文件结构(2026-05-04 Phase 1)"**(C-B 描述 + 候选评估对比表后两处);**§A.1 类比范式加 "D152 Phase 1: 已锁 C-B 子文件结构(2026-05-04)"**
- **§3 Orchestration 表 Phase 1 行 [✓ Done at commit `9f9e8cf`(留 D152 Phase 2 启动轮回填)]** + Phase 2+ 行 C-B 锁定后路径明确化(`lib/java/math.ss` BigDecimal + `lib/java/sql.ss` 加 ≥10 type class + `lib/java/io.ss` InputStream/Reader + integration_test)
- **VCM §1 豁免锚成立**(Phase 1 docs-only — `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D152-*.md hash 回填 + Phase 1 entry)
- **simplify 跳过 docs-only 例外**(纯文档 hash 回填 + Phase 1 entry)
- **d_doc_index_linter F1=0 GATE OK** + **ultrathink_linter PASS** + **D135-D151 范式延续**
- **MNK §M meta-gate 强制四问全 ✓**(深度读 D152.md §核心目标 + §核心原则 13 条 + §1 Context + §A.1 决策行 4 候选 C-A/C-B/C-C/C-D + §A.1.1 G1/G2 落点 + §A.2 H1-H10 H2 PASS + §A.3 废案 8 条 + §Phase 收关锚 Phase 0 [✓] + §Status 时间线 Phase 0 entry + 历史 D135-D151 sub-D 链路接力范式延续 + D147 主线 close at `8323501` → D150 主线暂停 → D151 §F1 起首 → D151 Phase 0 落档 → D151 Phase 1 用户对话锁 C-B-3 → D152 sub-D 起首 → D152 Phase 0 落档 → Phase 1 hash 回填 + 用户对话锁 C-B + Phase 1 启动条件验证未漏 — 兑现 a-h 总览每条 file:line 锚)
- **D152 Phase 1 commit hash 留 D152 Phase 2 启动轮回填**(D135-D151 范式 — 单 commit 不能引用自己 hash 下下轮回填)

### Phase 2: `lib/java/math.ss` 新建 BigDecimal class + 真 type 单元测 [✓] Done at commit `<placeholder>`(留 D152 Phase 3 启动轮回填 — D135-D151 范式 单 commit 不能引用自己 hash 下下轮回填)(2026-05-04)

- **`lib/java/math.ss` 新建 ~180 LOC** — class `BigDecimal { unscaled: int, scale: int }` + method `scale()` / `unscaledValue()` / `precision()` / `signum()` / `add` / `subtract` / `multiply` / `negate` / `abs` / `compareTo` / `equals` / `toString` + helper `bdPow10` + factory `BigDecimal_fromInt` / `BigDecimal_fromString`(JDK java.math.BigDecimal 范式直翻 — internal repr unscaled value + scale exponent 同 JDK v9+ intCompact long primitive fast path,precision ≤18 digits 覆盖 MySQL DECIMAL(10,2) / DECIMAL(18,4) 主流 JDBC 用例;arbitrary-precision 与 RoundingMode-aware divide 留 §Followup BigInteger primitive sub-D 后扩 fallback path)
- **`tests/d152_jdbc_type_class_foundation/bigdecimal_test.ss` 新建 ~120 LOC** — 全 case GREEN(ctor+accessor / `BigDecimal_fromInt` / `BigDecimal_fromString` parse / `precision` 多位数字 + 0 / `signum` 三态 / `add` same scale + mismatch scale 对齐 / `subtract` / `multiply` scale 累加 / `negate` / `abs` neg+pos / `compareTo` cross-scale 数值等 / `equals` JDK semantics(1.0 != 1.00,scale 影响)/ `toString` round-trip 整数 + 小数 + 负数 + zero-pad fraction)— `bin/ss test tests/d152_jdbc_type_class_foundation/` 1 passed
- **bootstrap 三阶段固定点验证 PASS**(`./build.sh bootstrap` Stage 2 = Stage 3 不破 — `lib/java/math.ss` 新建不参与编译器自举 stages 但 SS 编译器可正常解析新文件 + 测试可编译可运行 + `bin/ss` 自身 stage1→stage2→stage3 全跑通 + 更新 bin/ss)
- **VCM §1 非 docs-only 不豁免 + §N 6 验全 ✓**(N1 改动文件清单 ✓ — `lib/java/math.ss` 新建 + `tests/d152_jdbc_type_class_foundation/bigdecimal_test.ss` 新建 + `docs/3-decisions/D152-*.md` 改 4 处 hash + Phase 2 entry / N2 bootstrap 三阶段固定点 PASS / N3 测试套件 PASS / N4 d_doc_index F1=0 / N5 simplify 4 维 PASS / N6 ultrathink linter PASS)
- **simplify 4 维 PASS**(reuse — 复用 SS string charAt + parseInt + length + 模板字符串 prelude builtin,无重复 helper;quality — class field+method 同名 SS 支持已实测验证 + JDK 范式 API 命名;efficiency — 算术 O(1) + bdPow10 循环 ≤18 ≤ int 范围 + scale 对齐 in-place 不分配中间 BigDecimal;readability — 无 string-encode-data,字段类型显式 int + method JDK 公共 API 名,陌生人单文件秒懂)
- **d_doc_index_linter F1=0 GATE OK** + **ultrathink_linter PASS** + **D135-D151 范式延续**
- **MNK §M meta-gate 强制四问全 ✓**(深度读 D152.md §核心目标 + §核心原则 13 条 + §1 Context + §A.1 决策行 C-B 锁定 + §A.1.1 G1/G2 落点 + §A.2 H3 BigDecimal LOC delta ~100-200 实测 ~180 在估内 + §A.3 废案 8 条 + §Phase 收关锚 Phase 0/1 [✓] + §Status 时间线 Phase 0/1 entry + 历史 D135-D152 sub-D 链路接力范式延续 + D147 主线 close at `8323501` → D150 主线暂停 → D151 §F1 起首 → D151 Phase 0/1 → D152 sub-D 起首 → D152 Phase 0/1 → **D152 Phase 2 lib/java/math.ss BigDecimal 实施起首** + Phase 2 启动条件验证未漏 — 兑现 a-h 总览每条 file:line 锚)
- **D152 Phase 2 commit hash 留 D152 Phase 3 启动轮回填**(D135-D151 范式 — 单 commit 不能引用自己 hash 下下轮回填)

### Phase 3-5 Planned (C-B 已锁 2026-05-04 Phase 1)

- **D152 Phase 3 = `lib/java/sql.ss` 加 ≥10 type class**(Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref ~500-800 LOC)
- **D152 Phase 4 = `lib/java/io.ss` 新建 InputStream/Reader**(~100-200 LOC)
- **D152 Phase 5 = integration_test 真 type 单元测扩展**(`tests/d152_jdbc_type_class_foundation/` Timestamp parse + Blob length + Reader read ~100-200 LOC,Phase 2 已落 BigDecimal arithmetic case)
- **D152 Phase N+ close**(各 type class GREEN + bootstrap 三阶段固定点不破 + integration_test 真 type case 全 GREEN)

### Phase N+ 后接力 D151 Phase 3+ Planned

- D152 主线 close 后 next_prompt 转向 **D151 Phase 3+ setter ≥18 method 接力**
- D151 setter `function updateBigDecimal(col: string, val: BigDecimal): void` 等 ≥18 method 直用 D152 type class 接口
- D151 主线 close at D151 Phase N(setter ≥18 method GREEN + 7 case bidirectional 不破 + bootstrap 三阶段固定点 + integration_test 真 type 写入 server-side 全 GREEN)

---

## Followup

> **D152 Phase 0 落档后 — 候选锁定后展开**(2026-05-04):候选锁定后(Phase 1),后续 sub-D 起首队列由 C-A 单文件 / C-B 子文件结构 / C-C 最小 stub / C-D 内嵌 D151 决定;本 §Followup 表暂留 D151 接力 + JDBC type class 扩展 sub-D 队列,候选锁定后再扩 D152 各 Phase followup。

| # | 锚 | 描述 | 启动条件 |
|---|---|---|---|
| F1 | **D151 Phase 3+ setter ≥18 method 接力** | D152 主线 close 后 D151 setter `function updateBigDecimal(col: string, val: BigDecimal): void` 等 ≥18 method 直用 D152 type class 接口 | D152 主线 close 后 |
| F2 | `lib/java/time.ss` java.time API 现代版本(Instant/LocalDateTime/ZonedDateTime/Duration/Period 等 ~10+ class)| JDK 8+ 现代 API,scope 较大,留独立 sub-D | D152 主线 close 后 |
| F3 | `lib/java/util/concurrent.ss` 并发 API(Future/CompletableFuture/Executor 等)| JDBC 异步 API + Java 并发 API,留独立 sub-D | D152 主线 close 后 |
| F4 | D147 §F2 SELECT FOR UPDATE 行锁 + RR isolation level + InnoDB lock wait timeout | SQL standard `SELECT ... FOR UPDATE` 行锁与 cursor 正交独立 sub-D | D151 主线 close 后 |
| F5 | D147 §F3 multi-PK / 多表 join updatable cursor | multi-PK 复合主键 + 多表 join 留独立 sub-D | D151 主线 close 后 |
| F6 | D146 §F2 holdability HOLD_CURSORS_OVER_COMMIT / CLOSE_CURSORS_AT_COMMIT | cursor + transaction commit 行为 | D151 主线 close 后 |
| F7 | D146 §F3 ResultSetMetaData 完整列元数据 | getColumnTypeName / isAutoIncrement / isPrimaryKey 等 | D151 主线 close 后 |
| F8 | D138 §F1 KeyHolder.getKey 类型扩展 + HikariCP | 自动生成主键类型 + 连接池 | D151 主线 close 后 |
| F9 | D107 PostgreSQL driver 起首 | 跨数据库扩展新方向(D107 未首次落档) | D151 主线 close 后 |

---

## Status 时间线

- 2026-05-04 Phase 0 D152 sub-D 起首落档 + D151 Phase 1 hash 回填 + 候选评估 C-A/C-B/C-C/C-D + 子文件结构惯例 fact 入档 + 决策行不锁定 留用户对话授权 docs only(commit `41c4928` 留 D152 Phase 1 启动轮回填)— **D152 Phase 0 兑现 a-h 八项 fact 全 GREEN + D151 Phase 1 hash 回填 4 行 5 字串非均匀分布 line 280 含 2 字串(用户字面「4+1 处」refine)+ D152 sub-D 起首首次"父 sub-D Phase 中起子 sub-D"路径 + lib/java/ 子文件结构惯例 + JDK java.* 业界对标**:(a) D152.md 新建 ~400 行 docs-only(本 commit)— Status header + Depends on D151/D147/D146/D138/D139/D025/D134/D052 + Date 2026-05-04 + §核心目标 + §核心原则 13 条 + §1 Context(D151 Phase 1 用户对话锁 C-B-3 后 D152 起首状态 + 累计 sub-D 链路 16 + 业界对标 JDK java.* + lib/java/ 子文件结构 + 首次"父 sub-D Phase 中起子 sub-D"路径 fact)+ §2 RED 锚 + §3 Orchestration Phase 0-N+ + §A.1 4 候选评估 C-A/C-B/C-C/C-D + §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 8 条 + §Phase 收关锚 + §Followup + §Status 时间线 Phase 0 entry;(b) D151 Phase 1 commit hash `fef882f` 回填 D151.md 5 处(line 108 / 242 / 248 / 280 含 2 字串)= 4 行 5 字串非均匀分布 line 280 含 2 字串(用户字面「4+1 处」refine,memory `feedback_user_literal_vs_d_ssot` 同形防御 16 次落档 PSM §字段 3 与历史 D148 Phase 5 字面「5 处」实测 6 / D149 Phase 0 字面「3 处」实测 4 / D149 Phase 3 字面「8 处」实测 6 行 8 字串 / D150 启动字面「6 处」实测 6 行 10 字串 / D150 Phase 1 字面「3 行 4 字串」实测同 / D151 启动字面「4+1 处」实测 5 行 7 字串 / D151 Phase 1 字面「4+1 处」实测 5 行 7 字串 反差实证延续);(c) **lib/java/ 子文件结构惯例 fact 入档**(§A.2 H1)— JDK `java.math.*` / `java.sql.*` / `java.io.*` 子目录映射 SS `lib/java/math.ss` / `lib/java/sql.ss` / `lib/java/io.ss` 子文件;SS lib/java/sql.ss 已存在子文件惯例萌芽;(d) **C-A/C-B/C-C/C-D 候选评估 fact 入档**(§A.1 决策行 — C-A 单文件 ~700-1200 LOC / C-B 子文件结构 ~800-1400 LOC 分轮 / C-C 最小 stub ~50-100 LOC / C-D 内嵌 D151)+ §字段 10 (e) 自决策评估 C-B > C-A > C-D > C-C(根因解决度 + 长久 / 演化维度 — JDK java.* 业界对标 + lib/java/ 子文件结构 + N 年返工度低);(e) §A.2 H1-H10 加入 + §A.3 废案 8 条;(f) VCM §1 豁免锚成立 docs-only(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D151-*.md hash 回填 + 新建 docs/3-decisions/D152-*.md);simplify 跳过 docs-only 例外;d_doc_index_linter F1=0 GATE OK + ultrathink GATE OK 3/3 PASS;(g) MNK §M meta-gate 强制四问全 ✓(深度读 D151.md §核心目标 + §核心原则 13 条 + §1 Context + §A.1 决策行 C-B 锁定 + C-B-1/2/3 子候选评估 + C-B-3 用户对话锁定 + §A.1.1 G1/G2 落点 + §A.2 H1-H10 H2 PASS + §A.3 废案 7 条 + §Phase 收关锚 Phase 0/1 [✓] + §Status 时间线 Phase 0/1 entry + 历史 D135-D151 SQL 主线范式延续 + D147 主线 close at `8323501` → D150 主线暂停 → D151 §F1 起首 → D151 Phase 0 落档 → D151 Phase 1 用户对话锁 C-B-3 → D152 sub-D 起首 + D152 Phase 0 启动条件验证未漏 — D151 Phase 1 hash 回填 + D152 sub-D 起首落档 + 兑现 a-h 总览每条 file:line 锚);(h) D152 Phase 0 commit hash 留 D152 Phase 1 启动轮回填(D135-D151 范式 — 单 commit 不能引用自己 hash 下下轮回填);**新发现**:(i) **首次"父 sub-D Phase 中起子 sub-D"路径** — D135-D150 范式都是单 sub-D 主线 + sub-D 链路接力(D138 → D139 / D140 / D141 等),D151 Phase 1 用户对话授权后选 C-B-3 = 起 D152 底层 sub-D 先做 + D151 setter 后做接力,首次形成"父 sub-D 在 Phase 中起子 sub-D"路径(类似 D148 Phase 2 H15 用户对话授权后内部 B1/B2 路径分支,但 D151 Phase 1 用户对话授权后是外部 D152 sub-D 起首,与 D 文档级链路接力同形);(ii) **lib/java/ 子文件结构惯例确认 JDK 业界对标** — JDK 标准库 source tree `java/math/BigDecimal.java` / `java/sql/Timestamp.java` 等子目录范式直翻 SS `lib/java/math.ss` / `lib/java/sql.ss` / `lib/java/io.ss` 子文件;SS lib/java/sql.ss 已存在子文件惯例萌芽,D152 Phase 2-4 落地 math.ss + io.ss 完整子文件结构;(iii) **D152 范畴扩展 D135-D151 sub-D 链路**(累计 17 sub-D 链路)— D135 → D136 → D137 → D138 → D139 → D140 → D141 → D142 → D143 → D144 → D145 → D146 → D147 close → D150 主线暂停 → D151 §F1 起首 → D151 Phase 1 用户对话锁 C-B-3 → **D152 底层 type class sub-D 起首**(本 D);(iv) **C-B 子文件结构 LOC 估上调实证** — Phase 0 估含 ≥10 type class × 30-100 LOC each(BigDecimal class scope 大含 add/sub/mul/div + scale + precision + toString + equals + hashCode 等 ~100-200 LOC,Timestamp/Date/Time class scope 中含 toString/parse + getYear/getMonth + before/after/equals 等 ~50-80 LOC,Blob/Clob/NClob class scope 中含 length/getBytes/getCharacterStream 等 ~50-80 LOC,RowId/SQLXML/Array/Ref class scope 小含 getRowIdLifetime/getString/getArray/getObject 等 ~30-50 LOC,InputStream/Reader class 中含 read/skip/close 等 ~50-80 LOC),分轮 Phase 2-5 实施 ~800-1400 LOC 总;(v) **D152 Phase 0 commit hash 留 D152 Phase 1 启动轮回填**(D135-D151 范式 — 单 commit 不能引用自己 hash 下下轮回填;D152 Phase 0 close 后入 Phase 1 = D152 Phase 0 hash 回填 + 用户对话授权 C-A/C-B/C-C/C-D 锁定);(vi) **D135-D151 范式延续 D152 Phase 0 → Phase 1 用户对话授权门槛** — D135-D151 sub-D 链路接力范式延续(底层 → 上层 = JDK java.* 标准库范式),D152 候选评估行不锁定 留用户对话明确锁定后才入 Phase 1 候选范畴细化(类比 D148 H15 / D149 H12 / D150 H3 / D151 Phase 1 H2 范式);(vii) **D152 Phase 0 完成后 next_prompt 转向 D152 Phase 1 启动轮**(.claude/next_prompt.md 写 D152 Phase 1 启动 = D152 Phase 0 commit hash 回填 + 用户对话授权门槛触发 + 候选锁定 C-A/C-B/C-C/C-D + 候选范畴细化 + 路径分支 + ultrathink GATE OK 3/3 PASS);(viii) **lib/java/sql.ss 已 14428 bytes 含 Connection / PreparedStatement / ResultSet / Statement / DriverManager 等** — D152 Phase 3 加 ≥10 type class 后预估 sql.ss ~15000-15500 bytes,仍在合理 ≤600 行 / ≤30000 bytes 单文件惯例内(若超惯例线则 Phase 3 拆分细化按 type class 子族独立子文件 sql/timestamp.ss / sql/blob.ss 等)
- 2026-05-04 Phase 1 D152 Phase 0 hash `41c4928` 回填 + 用户对话锁 **C-B 子文件结构** + 候选范畴细化 + 路径分支 docs only(commit `9f9e8cf` 留 D152 Phase 2 启动轮回填)— **D152 Phase 1 兑现 a-h 八项 fact 全 GREEN + D152 Phase 0 hash 回填 3 行 3 字串均匀分布无 refine(用户字面「3 处」实测 = 字面 = 3,memory `feedback_user_literal_vs_d_ssot` 同形防御 17 次落档 — 少数「实测 = 字面」无 refine 之例类比 D149 Phase 5)+ 用户对话锁 C-B 子文件结构 + Phase 2+ 路径明确化(`lib/java/math.ss` BigDecimal + `lib/java/sql.ss` 加 ≥10 type class + `lib/java/io.ss` InputStream/Reader)**:(a) D152 Phase 0 commit hash `41c4928` 回填 D152.md 3 处(line 126 §3 Orchestration 表 Phase 0 行 + line 246 §Phase 收关锚 §Phase 0 标题 + line 301 §Status 时间线 Phase 0 entry 主条目)= **3 行 3 字串均匀分布无 refine**(用户字面「3 处」实测 = 字面 = 3 均匀无 refine,memory `feedback_user_literal_vs_d_ssot` 同形防御 17 次落档 PSM §字段 3;**D152 Phase 1 是少数「实测 = 字面」无 refine 之例**,类比 D149 Phase 5 字面「5 处」实测 = 字面 = 5 均匀无 refine 历史范式,与历史 D148 Phase 5 字面「5 处」实测 6 / D149 Phase 0 字面「3 处」实测 4 / D149 Phase 3 字面「8 处」实测 6 行 8 字串 / D150 启动字面「6 处」实测 6 行 10 字串 / D150 Phase 1 字面「3 行 4 字串」实测同 / D151 启动字面「4+1 处」实测 5 行 7 字串 / D151 Phase 1 字面「4+1 处」实测 5 行 7 字串 / D152 启动字面「4+1 处」实测 4 行 5 字串 反差实证延续);(b) **用户对话授权门槛触发**(2026-05-04 Phase 1 用户口令 "C-B")— **C-B 子文件结构锁定**,类比 D148 Phase 2 H15 用户口令 "B1" / D149 Phase 2 H12 "C3" / D150 Phase 0 H3 / D151 Phase 1 H2 "C-B-3" 显式范式;(c) **C-B 锁定后路径明确化**(Phase 2 = `lib/java/math.ss` 新建 BigDecimal ~100-200 LOC + Phase 3 = `lib/java/sql.ss` 加 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref ~500-800 LOC + Phase 4 = `lib/java/io.ss` 新建 InputStream/Reader ~100-200 LOC + Phase 5 = integration_test 真 type 单元测 ~100-200 LOC + Phase N+ close 后 D151 Phase 3+ setter ≥18 method 接力);(d) **§A.2 H2 标 PASS**(用户对话授权门槛已触发 — C-B 锁定);**§A.1 决策行 §字段 10 (e) 自决策评估倾向行加 "用户对话锁 C-B 子文件结构(2026-05-04 Phase 1)"**(C-B 描述 + 候选评估对比表后两处);**§A.1 类比范式加 "D152 Phase 1: 已锁 C-B 子文件结构(2026-05-04)"**;(e) **§3 Orchestration 表 Phase 1 行 [✓ Done at commit `9f9e8cf`(留 D152 Phase 2 启动轮回填)]** + **Phase 2+ 行 C-B 已锁(2026-05-04 Phase 1)路径明确化**(`lib/java/math.ss` BigDecimal + `lib/java/sql.ss` 加 ≥10 type class + `lib/java/io.ss` InputStream/Reader + integration_test);(f) **VCM §1 豁免锚成立 docs-only**(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D152-*.md hash 回填 + Phase 1 entry);simplify 跳过 docs-only 例外;d_doc_index_linter F1=0 GATE OK + ultrathink GATE OK 3/3 PASS;(g) **MNK §M meta-gate 强制四问全 ✓**(深度读 D152.md §核心目标 + §核心原则 13 条 + §1 Context + §A.1 决策行 4 候选 C-A/C-B/C-C/C-D + §A.1.1 G1/G2 落点 + §A.2 H1-H10 H2 PASS + §A.3 废案 8 条 + §Phase 收关锚 Phase 0 [✓] + §Status 时间线 Phase 0 entry + 历史 D135-D151 sub-D 链路接力范式延续 + D147 主线 close at `8323501` → D150 主线暂停 → D151 §F1 起首 → D151 Phase 0 落档 → D151 Phase 1 用户对话锁 C-B-3 → D152 sub-D 起首 → D152 Phase 0 落档 → Phase 1 hash 回填 + 用户对话锁 C-B + Phase 1 启动条件验证未漏 — 兑现 a-h 总览每条 file:line 锚);(h) **D152 Phase 1 commit hash 留 D152 Phase 2 启动轮回填**(D135-D151 范式 — 单 commit 不能引用自己 hash 下下轮回填);**新发现**:(i) **D152 Phase 1 = D151 Phase 1 同形授权门槛范式延续** — D151 Phase 1 用户对话锁 C-B-3(2026-05-04)→ D152 sub-D 起首 → D152 Phase 0 落档 → D152 Phase 1 用户对话授权门槛触发(类比 D148 Phase 2 H15 / D149 Phase 2 H12 / D150 Phase 0 H3 / D151 Phase 1 H2 同形),C-B 锁定后 Phase 2+ 路径明确化(JDK java.* 业界对标 + lib/java/ 子文件结构 + N 年返工度低);(ii) **D152 Phase 1 是少数「实测 = 字面」无 refine 之例**(类比 D149 Phase 5 字面「5 处」实测 = 字面 = 5 均匀无 refine 历史范式)— 用户字面「3 处」实测 3 行 3 字串均匀分布无 refine,memory `feedback_user_literal_vs_d_ssot` 同形防御 17 次落档 PSM §字段 3 与历史 8 次反差实证延续(D148 Phase 5 字面「5 处」实测 6 / D149 Phase 0 字面「3 处」实测 4 / D149 Phase 3 字面「8 处」实测 6 行 8 字串 / D150 启动字面「6 处」实测 6 行 10 字串 / D150 Phase 1 字面「3 行 4 字串」实测同 / D151 启动字面「4+1 处」实测 5 行 7 字串 / D151 Phase 1 字面「4+1 处」实测 5 行 7 字串 / D152 启动字面「4+1 处」实测 4 行 5 字串);(iii) **D135-D151 sub-D 链路 + D152 Phase 1 路径锁定** — 累计 17 sub-D 链路 D135 → D136 → D137 → D138 → D139 → D140 → D141 → D142 → D143 → D144 → D145 → D146 → D147 close → D150 主线暂停 → D151 §F1 起首 → D151 Phase 1 用户对话锁 C-B-3 → D152 sub-D 起首 → D152 Phase 0 落档 → **D152 Phase 1 用户对话锁 C-B 子文件结构**(本 commit);(iv) **D152 Phase 1 commit hash 留 D152 Phase 2 启动轮回填**(D135-D151 范式 — 单 commit 不能引用自己 hash 下下轮回填;D152 Phase 1 close 后入 Phase 2 = 起 `lib/java/math.ss` BigDecimal class + D152 Phase 1 hash 回填);(v) **D152 Phase 2+ 路径明确化范式延续 D151 Phase 2+ 路径明确化** — D151 Phase 2 = 起 D152 sub-D 起首 + D151 setter 接力,**D152 Phase 2 = 起 `lib/java/math.ss` BigDecimal class + Phase 3-5 各 type class scope 独立实施 + Phase N+ close 后 D151 Phase 3+ setter 接力**;(vi) **D152 Phase 1 完成后 next_prompt 转向 D152 Phase 2 启动轮**(.claude/next_prompt.md 写 D152 Phase 2 启动 = D152 Phase 1 commit hash 回填 + `lib/java/math.ss` 新建 BigDecimal class 起首 + bootstrap 三阶段固定点验证 + integration_test BigDecimal arithmetic case + ultrathink GATE OK 3/3 PASS);(vii) **D152 Phase 1 实测 = 字面无 refine 反差实证延续** — D135-D152 启动各轮中仅 D149 Phase 2 字面「4 处」实测 = 字面 = 4 / D149 Phase 5 字面「5 处」实测 = 字面 = 5 / **D152 Phase 1 字面「3 处」实测 = 字面 = 3** 三次无 refine,其余反差实证延续(字面 vs 实测 refine);(viii) **C-B 锁定确认 JDK java.* 业界对标 + lib/java/ 子文件结构惯例** — Phase 0 §A.1 §字段 10 (e) 自决策评估倾向 C-B > C-A > C-D > C-C(三维全胜 — JDK java.* 业界对标 + lib/java/ 子文件结构惯例 + N 年返工度低),用户对话授权后明确锁 C-B,Phase 2-5 落地各 type class scope 独立可独立测,N 年低返工度
- 2026-05-04 Phase 2 D152 Phase 1 hash `9f9e8cf` 回填 + `lib/java/math.ss` 新建 BigDecimal class + `tests/d152_jdbc_type_class_foundation/bigdecimal_test.ss` 真 type 单元测 GREEN + bootstrap 三阶段固定点 PASS(commit `<placeholder>` 留 D152 Phase 3 启动轮回填)— **D152 Phase 2 兑现 a-h 八项 fact 全 GREEN + D152 Phase 1 hash 回填 4 行 5 字串非均匀分布 line 309 含 2 字串(用户字面「4+1 处」refine,memory `feedback_user_literal_vs_d_ssot` 同形防御 18 次落档)+ D152 首个非 docs-only 实施 Phase + lib/java/math.ss BigDecimal v1 落地 + bootstrap 不破**:(a) D152 Phase 1 commit hash `9f9e8cf` 回填 D152.md 4 处(line 127 §3 Orchestration 表 Phase 1 行 + line 261 §Phase 收关锚 §Phase 1 标题 + line 266 §Phase 收关锚 §Phase 1 entry §3 Orchestration 表 Phase 1 行 mention + line 320 §Status 时间线 Phase 1 entry 含 2 字串:主条目 commit + (e) 子条目 §3 Orchestration 表 Phase 1 行 mention)= **4 行 5 字串非均匀分布 line 320 含 2 字串**(用户字面「4+1 处」refine,memory `feedback_user_literal_vs_d_ssot` 同形防御 18 次落档 PSM §字段 3 与历史 D148 Phase 5 字面「5 处」实测 6 / D149 Phase 0 字面「3 处」实测 4 / D149 Phase 3 字面「8 处」实测 6 行 8 字串 / D150 启动字面「6 处」实测 6 行 10 字串 / D150 Phase 1 字面「3 行 4 字串」实测同 / D151 启动字面「4+1 处」实测 5 行 7 字串 / D151 Phase 1 字面「4+1 处」实测 5 行 7 字串 / D152 启动字面「4+1 处」实测 4 行 5 字串 / D152 Phase 1 字面「3 处」实测 = 字面 = 3 均匀无 refine 反差实证延续);(b) **`lib/java/math.ss` 新建 ~180 LOC BigDecimal class JDK 范式直翻** — class field `unscaled: int` / `scale: int`(JDK v9+ intCompact long primitive 同形)+ method `scale()` / `unscaledValue()` / `precision()` / `signum()` / `add` / `subtract` / `multiply` / `negate` / `abs` / `compareTo` / `equals`(JDK semantics — 1.0 != 1.00,scale 影响 equals 但 compareTo 数值等)/ `toString`(零填充 fraction)+ helper `bdPow10` + factory `BigDecimal_fromInt` / `BigDecimal_fromString`;precision ≤18 digits(int 范围内)覆盖 MySQL DECIMAL(10,2) / DECIMAL(18,4) 主流 JDBC 用例;(c) **`tests/d152_jdbc_type_class_foundation/bigdecimal_test.ss` 新建 ~120 LOC 真 type 单元测 GREEN** — `bin/ss test tests/d152_jdbc_type_class_foundation/` 输出 `1 passed, 0 failed`(ctor+accessor / fromInt / fromString parse 整数+小数+负数 / precision 多位+0+负数 / signum 三态 / add same scale + mismatch 对齐 / subtract 不同 scale / multiply scale 累加 / negate / abs neg+pos / compareTo cross-scale 数值等 / equals JDK semantics(1.0 != 1.00 同 scale 同 unscaled 才相等)/ toString round-trip 19.99 / -3.14 / 12345 / 0.05 zero-pad / 整数 fromInt(42));(d) **bootstrap 三阶段固定点验证 PASS** — `./build.sh bootstrap` Stage 1 → Stage 2 → Stage 3 全跑通 + Fixed point verified Stage 2 = Stage 3 + 更新 bin/ss(`lib/java/math.ss` 不参与编译器自举 stages 但 SS 编译器可正常解析新文件 + 新文件不影响编译器自身结构);(e) **§3 Orchestration 表 Phase 2 行 [✓ Done at commit `<placeholder>`(留 D152 Phase 3 启动轮回填)]** + Phase 3+ 行(原 Phase 2+ 拆分)路径明确化(`lib/java/sql.ss` 加 ≥10 type class + `lib/java/io.ss` InputStream/Reader + integration_test 扩展);(f) **VCM §1 非 docs-only 不豁免 + §N 6 验全 ✓**(N1 改动文件清单 ✓ — `lib/java/math.ss` + `tests/d152_jdbc_type_class_foundation/bigdecimal_test.ss` 新建 + `docs/3-decisions/D152-*.md` 4 处 hash 回填 + Phase 2 entry / N2 bootstrap 三阶段固定点 PASS / N3 测试套件 1 passed / N4 d_doc_index F1=0 / N5 simplify 4 维 PASS — reuse 复用 SS string charAt+parseInt+length+模板 prelude 无重复 helper / quality field+method 同名 SS 支持已实测 + JDK 范式 API 命名 / efficiency 算术 O(1) + bdPow10 循环 ≤18 / readability 字段类型显式 int + method JDK 公共 API 名陌生人单文件秒懂 / N6 ultrathink linter PASS);d_doc_index_linter F1=0 GATE OK + ultrathink_linter PASS + D135-D151 范式延续;(g) **MNK §M meta-gate 强制四问全 ✓**(深度读 D152.md §核心目标 + §核心原则 13 条 + §1 Context + §A.1 决策行 C-B 锁定 + §A.1.1 G1/G2 落点 + §A.2 H3 BigDecimal LOC delta ~100-200 实测 ~180 在估内 + §A.3 废案 8 条 + §Phase 收关锚 Phase 0/1 [✓] + §Status 时间线 Phase 0/1 entry + 历史 D135-D152 sub-D 链路接力范式延续 + D147 主线 close at `8323501` → D150 主线暂停 → D151 §F1 起首 → D151 Phase 0/1 → D152 sub-D 起首 → D152 Phase 0/1 → **D152 Phase 2 lib/java/math.ss BigDecimal 实施起首** + Phase 2 启动条件验证未漏 — 兑现 a-h 总览每条 file:line 锚);(h) **D152 Phase 2 commit hash 留 D152 Phase 3 启动轮回填**(D135-D151 范式 — 单 commit 不能引用自己 hash 下下轮回填);**新发现**:(i) **D152 Phase 2 = 首个非 docs-only 实施 Phase**(D152 Phase 0/1 docs-only VCM §1 豁免 vs Phase 2 起触 lib/ + tests/,VCM §N 6 验全跑 + bootstrap 三阶段固定点 PASS + simplify 4 维 PASS 不跳过)— D135-D152 范式中,D 文档 Phase 0/1 docs-only 多见 / Phase 2+ 实施触 bootstrap+lib+tests 多见,D152 Phase 2 是 D152 sub-D 内首个非 docs-only Phase;(ii) **BigDecimal v1 内部表示选择 = JDK v9+ intCompact 同形** — unscaled value(int)+ scale(int)简单结构覆盖 MySQL DECIMAL(10,2) / DECIMAL(18,4) precision ≤18 主流 JDBC 用例,JDK BigDecimal 内部 v9+ 也是 intCompact long primitive fast path + BigInteger fallback,SS 无 BigInteger primitive 留 §F BigInteger sub-D 后扩 fallback path,N 年返工度低(JDK 范式同形,Followup 仅扩 precision >18 case 不重写 v1 接口);(iii) **D135-D152 sub-D 链路 + D152 Phase 2 lib/java/math.ss 起首** — 累计 17 sub-D 链路 D135 → ... → D147 close → D150 主线暂停 → D151 Phase 0/1 → D152 sub-D 起首 → D152 Phase 0/1 → **D152 Phase 2 lib/java/math.ss BigDecimal v1 落地**(本 commit);(iv) **field+method 同名 SS 支持实测** — `class BigDecimal { scale: int; function scale(): int { return this.scale } }` SS 编译器正常解析 + this.scale 访问字段 / this.scale() 调用 method,JDK 范式同形(BigDecimal.scale field + scale() method 同名);D152 Phase 2 是首次实证 SS 支持 field+method 同名(D135-D152 中无前例)— 后续 D 文档可放心用 JDK 范式 method 名 vs field 名同名;(v) **D152 Phase 2 commit hash 留 D152 Phase 3 启动轮回填**(D135-D151 范式 — 单 commit 不能引用自己 hash 下下轮回填;D152 Phase 2 close 后入 Phase 3 = D152 Phase 2 hash 回填 + `lib/java/sql.ss` 加 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref ≥10 type class);(vi) **D152 Phase 2 完成后 next_prompt 转向 D152 Phase 3 启动轮**(.claude/next_prompt.md 写 D152 Phase 3 启动 = D152 Phase 2 commit hash 回填 + `lib/java/sql.ss` 加 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref 等 ≥10 type class + bootstrap 三阶段固定点验证 + integration_test SQL type case + ultrathink GATE OK 3/3 PASS);(vii) **C-B 锁定后 Phase 2 直接 Execute 不 Plan** — memory `feedback_execute_when_doc_locked.md` 同形:决策归档后 next_prompt 直接 Execute 不 Plan,D152 Phase 1 锁 C-B 子文件结构后 Phase 2 lib/java/math.ss BigDecimal 范畴明确无新 sub-decision 需用户授权(类比 D147 Phase 2 起 直接落 ResultSet update 18 method 范式延续);(viii) **divide() 与 RoundingMode 留 §F Followup 不在 v1 范畴** — JDK BigDecimal.divide(other, scale, RoundingMode) 复杂 API 含 7 RoundingMode(HALF_UP / HALF_DOWN / HALF_EVEN / UP / DOWN / CEILING / FLOOR / UNNECESSARY),v1 不实现 divide(precision ≤18 范围内,SQL DECIMAL 列加减乘是主流用例,SQL DECIMAL ÷ DECIMAL 极少在 ResultSet 边界出现,通常 SQL 端 SELECT a/b FROM t 算完返 ResultSet ),留 §F divide+RoundingMode 7 mode sub-D 后扩(类比 BigInteger Followup 范式 — N 年返工度低)
