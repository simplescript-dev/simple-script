# D151: ResultSet Update Setter Type Extension — 完整 JDBC 4.3 §15.2.5 ≥18 method (BigDecimal / Timestamp / Date / Time / Bytes / Float / Short / Byte / Object / Blob / Clob / NClob / RowId / SQLXML / Array / Ref / Stream)

**Status:** Phase 0 落档(D147 主线 close at `8323501` + D147 §F1 line 218 起首 + 用户对话锁 C-B 完整 JDBC 4.3 §15.2.5 ≥18 method + 底层依赖链实证 ≥10 type class 缺(`lib/java/` 仅 `sql.ss` 14428 bytes 无 `math.ss`/`io.ss`/`time.ss` + `lib/java/sql.ss` 无 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref + `lib/` 无 BigDecimal,grep 0 命中)+ C-B-1/2/3 子候选评估 fact 入档(C-B-1 一次到位 / C-B-2 仅 setter / C-B-3 底层先做)+ §字段 10 (e) 自决策评估 C-B-3 ≥ C-B-1 > C-B-2 + 决策行不锁定 留用户对话授权门槛触发(类比 D148 Phase 2 H15 / D149 Phase 2 H12 / D150 Phase 0 H3 范式)+ docs only(VCM §1 豁免锚成立)+ d_doc_index F1=0 GATE OK + ultrathink GATE OK + simplify 跳过 docs-only 例外)— **D147 §F1 起首 D151 sub-D**;后续 D151 Phase 1 = 用户对话授权 C-B-1/2/3 锁定 + Phase 0 hash 回填 + 候选范畴细化 + 路径分支(C-B-1 D151 主线 ≥10 type class + ≥18 setter 一次到位 / C-B-2 D151 主线仅 setter + D152-D161 底层接力 / C-B-3 D151' 底层先做 + D151 setter 后做)。

**Depends on:** D147(updatable cursor + ResultSet update 6 核心 setter,Phase 5 close at `8323501`,本 D 起 §F1 扩展类型)+ D146(server-side cursor + ResultSet 7 method)+ D138(generated keys 范式 — Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环)+ D139(SQL exception hierarchy)+ D025(class layout `{ i32 rc, ptr TypeInfo, ...fields }` + interface vtable)+ D134(MySQL wire protocol)+ D052(named arg `k: v` syntax)

**Date:** 2026-05-04

---

## 核心目标

D147 §F1 line 218 "updateXxx 6 setter 扩展类型(BigDecimal / Timestamp / Date / Time / Bytes / Float / Short / Byte)" sub-D 起首,实测 D147 §F1 字面 8 类型 vs JDBC 4.3 §15.2.5 ≥18 method scope refine(memory `feedback_user_literal_vs_d_ssot` 同形防御 14 次落档);按 CLAUDE.md §Root Cause 优先 + D147 §核心原则 1 "完整 JDBC 4.3 §15 ResultSet Update 18 method,不裁剪",**用户对话锁 C-B 完整 JDBC 4.3 §15.2.5 ≥18 method**。

**第一性需求**:
- JDBC 4.3 §15.2.5 ResultSet 完整 SQL type setter ≥18 method 缺 ≥22(D147 主线 6 核心 + D147 §F1 字面 8 + JDBC 4.3 ≥4 额外 = ≥18 method 完整;实际 ≥22 含 updateObject/Blob/Clob/NClob/RowId/SQLXML/Array/Ref/AsciiStream/BinaryStream/CharacterStream/NCharacterStream/NString 等)
- ORM Hibernate `BasicType<BigDecimal>.set/get` cursor 路径成立 — `@Column(precision=10, scale=2) BigDecimal price` 属性 dirty track + flush 走 `ResultSet.updateBigDecimal(col, val)` 标准 binding,缺则 cursor 路径全断回 `INSERT INTO ... VALUES (?)` 重写 SQL workaround / `rs.updateString("amount", val.toString())` 字符串 stringify workaround(丢精度 / 类型安全)
- 业界对标 MySQL Connector/J `UpdatableResultSet` 实现 ≥18 method 全扩(GA 5.0+ 范式,JDK java.* 标准库支撑),SS 仅 6 核心是节省路径
- N 年返工度:仅 8 字面 ≠ JDBC 4.3 §15.2.5 完整 — 剩余 ≥4 额外 method 后续仍需 sub-D 起首,返工度高 → C-B 完整一次到位低返工度

**底层依赖链实证**(§A.2 H1 关键 fact):
- `lib/java/` 仅 `sql.ss`(14428 bytes)— 无 `math.ss` / `io.ss` / `time.ss`
- `lib/java/sql.ss` 无 Timestamp / Date / Time / Blob / Clob / NClob / RowId / SQLXML / Array / Ref 等 type class(grep 0 命中)
- `lib/` 无 BigDecimal class(grep 0 命中);仅 `lib/datetime.ss:14 class DateTime {}` 空 class(SS 自定义,非 JDBC 标准)
- `lib/` 无 InputStream / Reader / AsciiStream / BinaryStream / CharacterStream class

**底层依赖链实证后子候选**(C-B 锁定后内部分):
- **C-B-1**: D151 主线 = ≥18 setter 接口 + ≥10 底层 type class 一次到位(scope ~640-1370 LOC,业界对标 JDK java.* 标准库一次到位)
- **C-B-2**: D151 主线 = 仅 ≥18 setter + ptr / null-stub,底层 type class 留 D152-D161 sub-D 接力(scope ~70-150 LOC,N 年返工度高 — setter 签名改类型)
- **C-B-3**: 底层 type class 先做 sub-D D151',然后 D151 setter 起首(底层依赖链顺序 — 业界对标"先底层再上层")

**不在范畴**:
- ❌ C-A 仅 8 类型(已废 — 用户对话锁 C-B,§A.3)
- ❌ C-C 数据层 patch / stringify workaround(已废 — 违反 §Root Cause 优先 + memory `feedback_no_derive_workaround`,§A.3)
- ❌ C-D 合入 D146 §F3 ResultSetMetaData(已废 — scope 不收敛 + 跨 D 依赖,§A.3)
- ❌ 越过用户对话授权门槛自决策 C-B-1/2/3(类比 D148 H15 / D149 H12 / D150 H3 范式,Phase 0 不锁子候选,等用户对话二次授权)

---

## 核心原则

(继承 CLAUDE.md + D147 §核心原则 13 条):

1. **完整 JDBC 4.3 §15.2.5 ResultSet Update setter 不裁剪**(继承 D147 §核心原则 1)— ≥18 method 完整,含 BigDecimal/Timestamp/Date/Time/Bytes/Float/Short/Byte 8 + Object/Blob/Clob/NClob/RowId/SQLXML/Array/Ref ≥8 + AsciiStream/BinaryStream/CharacterStream/NCharacterStream/NString ≥5
2. **不引入新关键字 / 新语法**(继承 D147 §核心原则 1)— 复用既有 SS class / interface 语法机制
3. **Root Cause 优先**(CLAUDE.md §Root Cause 优先 第一法则,无例外)— 候选评估按根因解决度 + 长久 / 演化维度排序,**禁按 LOC 最少 / 工程量最小作排序依据**
4. **业界对标**(CLAUDE.md §长久 / 演化维度)— MySQL Connector/J `UpdatableResultSet` ≥18 method 完整范式 + JDK `java.math.BigDecimal` / `java.sql.Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref` / `java.io.InputStream/Reader` 标准库一次到位
5. **N 年返工度低**(CLAUDE.md §长久 / 演化维度)— C-B 完整 ≥18 method 一次到位 vs C-A 仅 8 字面 ≥4 method 后续 sub-D 起首返工度高
6. **底层依赖链先决**(CLAUDE.md §长久 / 演化维度 + memory `feedback_root_cause_no_cost.md` §8)— Phase 0 已实证 ≥10 底层 type class 缺,Phase 1 用户对话锁 C-B-1/2/3 子候选时倾向 C-B-3(底层先做)≥ C-B-1(一次到位)> C-B-2(仅 setter)
7. **bootstrap 隔离破例 D135-D150 范式同位例外** — D151 Phase 0 docs-only 不动 bootstrap(VCM §1 豁免锚成立);Phase 1+ 实施各独立 commit
8. **决策行不锁定 留用户对话授权门槛触发**(类比 D148 Phase 2 H15 / D149 Phase 2 H12 / D150 Phase 0 H3 授权范式)— Phase 0 启动轮 C-B 锁定,但 C-B-1/2/3 子候选不自决策,等用户对话明确锁定后才入 Phase 1 候选范畴细化
9. **driver-side 模拟范式延续**(继承 D147 §核心原则 3)— `MysqlBinaryResultSet` via `writeCol` stringify pattern(`prepared.ss:666-675` 范式)直翻新 ≥22 setter
10. **3 implementor 同步降级 stub**(继承 D147 §核心原则 11)— `MysqlResultSet` text 协议 no-op + `GeneratedKeyResultSet` synthetic no-op + `MysqlBinaryResultSet` 真实现
11. **Phase 计划独立 commit**(继承 D147 §核心原则 11)— Phase 0-N+ 独立 commit
12. **integration_test 扩 cases 真 type 写入 server-side**(继承 D147 §核心原则 12)— 扩 D147 `tests/d147_updatable_cursor/integration_test.ss` 加 BigDecimal/Timestamp/Bytes 等真 type case 或新建 `tests/d151_resultset_update_type_extension/`
13. **SS 编译器扩仅按需**(继承 D147 §核心原则 13)— Phase 0 不预判,Phase 1+ 实测 spike 走假设破裂回路 fallback

---

## §1 Context

### D147 主线 close 后 §F1 起首状态(commit `8323501`)

- ✓ **D147 主线 GREEN** — JDBC 4.3 §15 ResultSet Update 6 核心 setter + CURSOR_TYPE_FOR_UPDATE 0x02 + driver-side 模拟范式(close at commit `8323501`)
- ✓ **D147 §F1 line 218 起首条件具备** — D147 主线 close 后 §Followup F1 RED 启动条件 = JDBC 4.3 §15.2.5 ≥18 method 缺 ≥22 实证(`grep -c "function update<X>" lib/java/sql.ss` = 6 现状,目标 ≥18)
- ⚠ **底层 type class 缺实证**(§A.2 H1)— `lib/java/` 仅 `sql.ss`(14428 bytes)无 `math.ss` / `io.ss` / `time.ss`;`lib/java/sql.ss` 无 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref;`lib/` 无 BigDecimal class

### 累计 sub-D 链路

D135 → D136 → D137 → D138 → D139 → D140 → D141 → D142 → D143 → D144 → D145 → D146 → **D147 close** → **D150 主线暂停**(v2 类型系统 SQL libs 零受益实证)→ **D151 起 §F1 sub-D**

### 业界对标

- **MySQL Connector/J `UpdatableResultSet`** — ≥18 method 完整 SQL type setter 一次到位(GA 5.0+ 范式,JDK java.* 标准库支撑)
- **JDK java.math.BigDecimal / java.sql.Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref / java.io.InputStream/Reader** — 标准库一次到位,setter 接口可直用
- **PostgreSQL JDBC pgjdbc** — 同 JDK 标准库一次到位范式
- **Oracle ojdbc** — 同范式 + 自有 OracleType 扩展(本 D 不做)

SS 当前 lib/java/ 仅 sql.ss(14428 bytes)— 无 math.ss / io.ss / time.ss,底层 type class 全缺 → C-B 完整 ≥18 method 起首前需先做底层 type class sub-D 或同时落

---

## §2 RED 锚

D151 Phase 0 是「sub-D 起首选择 + 候选锁定」决策落档,无 RED bug 直接挂载;C-B 锁定后(Phase 1+)对应 RED:

```bash
# C-B 整体 setter RED(目标 ≥18):
grep -c "function updateBigDecimal\|function updateTimestamp\|function updateDate\|function updateTime\|function updateBytes\|function updateFloat\|function updateShort\|function updateByte\|function updateObject\|function updateBlob\|function updateClob\|function updateNClob\|function updateRowId\|function updateSQLXML\|function updateArray\|function updateRef\|function updateAsciiStream\|function updateBinaryStream\|function updateCharacterStream" /root/code/simplescript-dev/simple-script/lib/java/sql.ss
# 当前 = 0
# 目标 ≥ 18

# 底层 type class RED(C-B-1 / C-B-3 子候选):
grep -rn "class BigDecimal\|class Timestamp\|class Blob\|class Clob\|class NClob\|class RowId\|class SQLXML\|class InputStream\|class Reader" /root/code/simplescript-dev/simple-script/lib/
# 当前 = 0(仅 lib/datetime.ss:14 class DateTime {} 空 class,非 JDBC 标准)
# 目标 ≥ 10

# C-B-2 子候选无底层 type class RED(setter 用 ptr / null-stub 不依赖)
```

---

## §3 Orchestration

| Phase | 内容 | 落点 | 完成判据 |
|---|---|---|---|
| **Phase 0** [✓ Done at commit `<placeholder>`(留 D151 Phase 1 启动轮回填 — D135-D150 范式 单 commit 不能引用自己 hash 下下轮回填)] | D 文档落档 + 候选锁定 C-B + 底层依赖链实证 + C-B-1/2/3 子候选评估 fact 入档 + 决策行不锁定 留用户对话授权 | D151.md docs-only ~400 行 — Status header + Depends on + Date 2026-05-04 + §核心目标 + §核心原则 13 条 + §1 Context + §2 RED 锚 + §3 Orchestration Phase 0-N+ + §A.1 4 候选 + C-B 内 C-B-1/2/3 子候选评估 + §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 + §Phase 收关锚 + §Followup + §Status 时间线 | bootstrap/lib/tools 不动(VCM §1 豁免锚成立)+ ultrathink GATE OK + d_doc_index F1=0 + simplify 跳过 docs-only 例外 |
| **Phase 1** [ ] Planned | 用户对话锁 C-B-1/2/3 子候选 + Phase 0 hash 回填 + 候选范畴细化(底层 type class scope) | 用户答 `C-B-1` / `C-B-2` / `C-B-3` 锁定后 — 候选范畴细化 + 后续 Phase 路径明确 + Phase 0 hash 回填本 D 文档 | 用户对话授权门槛 PASS + 候选范畴细化 + 后续 Phase 路径明确 |
| **Phase 2+** Planned | 路径分支 — C-B-1 一次到位 / C-B-2 仅 setter / C-B-3 底层先做 | 待 Phase 1 用户授权后定:C-B-1 锁定 → D151 主线 = ≥10 底层 type class + ≥18 setter + 3 implementor + integration_test 分阶段实施;C-B-2 锁定 → D151 主线 = ≥18 setter + ptr / null-stub + 3 implementor + integration_test ptr edge,底层 type class 留 D152-D161 sub-D 起首接力;C-B-3 锁定 → 起 D151' 底层 type class sub-D 先做(`lib/java/math.ss BigDecimal` + `lib/java/sql.ss` 加 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref + `lib/java/io.ss` 加 InputStream/Reader)+ D151 setter 起首接力 | 路径明确后展开 |

**Phase 间依赖**: Phase 0 → 1(用户对话授权 C-B 子候选门槛触发)→ Phase 2+(路径分支:C-B-1 一次到位 / C-B-2 仅 setter / C-B-3 底层先做)

**LOC delta 估**(C-B 子候选):
- **C-B-1 一次到位**: ~640-1370 LOC(setter ~70 + ≥10 底层 type class × 30-100 = 300-1000 + implementor 同步 ~70 + integration_test ~200)
- **C-B-2 仅 setter**: ~70-150 LOC(setter ~70 + implementor stub ~70 + integration_test ~10 ptr / null edge)
- **C-B-3 底层先做**: ~300-1000 LOC(D151' 底层 type class)+ ~70-150 LOC(D151 setter)= 总 ~370-1150 LOC(分轮)

---

## §A.1 决策行

### C-A: 仅扩 D147 §F1 字面 8 类型(BigDecimal/Timestamp/Date/Time/Bytes/Float/Short/Byte)

**已废**(§A.3):用户对话锁 C-B 完整 JDBC 4.3 §15.2.5 ≥18 method,C-A 是节省路径(仅 8 < ≥18)违反 §核心原则 1 "完整不裁剪"

### C-B: 完整 JDBC 4.3 §15.2.5 ≥18 method(✓ 用户对话锁定 2026-05-04)

**起 D151 主线**:接口扩 ≥18 setter(8 字面 + ≥10 额外 updateObject/Blob/Clob/NClob/RowId/SQLXML/Array/Ref/AsciiStream/BinaryStream/CharacterStream/NCharacterStream/NString 等)+ 3 implementor 同步 + integration_test 扩 cases。

**§字段 10 (e) 自决策评估**(C-B vs 其他):
- **根因解决度**:**高**(完整 JDBC 4.3 §15.2.5 ≥18 method 一次到位 — D147 §核心原则 1 "完整不裁剪"延续)
- **长久 / 演化维度**:**高**(底层依赖链 — 实证 ≥10 底层 type class 缺,需先做或同时做;业界对标 MySQL Connector/J `UpdatableResultSet` ≥18 method 完整范式;N 年返工度 — 一次到位低返工)

**底层依赖链实证后 C-B 子候选**(留 Phase 1 用户对话二次授权):

| 子候选 | 主线范畴 | LOC delta | 长久 / 演化 | 业界对标 | 决策倾向 |
|---|---|---|---|---|---|
| **C-B-1 一次到位** | setter ≥18 + ≥10 底层 type class + 3 implementor + integration_test | ~640-1370 | 高(底层 + 上层同时落) | JDK java.* 标准库一次到位 | **倾向**(底层 + 上层一次到位 — 单 sub-D 完成) |
| C-B-2 仅 setter | setter ≥18 + ptr / null-stub + 3 implementor + integration_test ptr edge | ~70-150 | 中(setter 签名改类型 N 年返工) | ❌ JDK java.* 标准库未先落 setter | 不倾向(setter 签名 ptr / null 是 workaround 违反 §核心原则 1) |
| **C-B-3 底层先做** | D151'(新建)= ≥10 底层 type class + D151 = setter ≥18 | ~370-1150(分轮) | 高(底层先 + 上层后) | JDK java.* 业界对标"先底层再上层" | **倾向**(底层依赖链先决 — 业界对标终局范式) |

**§字段 10 (e) 自决策评估**(C-B 子候选):**C-B-3 ≥ C-B-1 > C-B-2**(根因解决度 + 长久 / 演化维度 — 底层依赖链先决 + 业界对标 + N 年返工度);Phase 0 不自决策,等 Phase 1 用户对话锁定。

### C-C: 数据层 patch / stringify workaround

**已废**(§A.3):违反 CLAUDE.md §Root Cause 优先 + memory `feedback_no_derive_workaround`(主线能力缺口不允许 stringify workaround)

### C-D: 合入 D146 §F3 ResultSetMetaData

**已废**(§A.3):scope 不收敛(setter 扩 + metadata 是两不同 API 层)+ 跨 D 依赖(D146 §F3 起首先决条件)

### 候选评估 4 维度对比表

| 维度 | C-A 仅 8 | **C-B 完整 ≥18**(锁定)| C-C stringify | C-D 合入 D146 §F3 | 决策倾向 |
|---|---|---|---|---|---|
| **根因解决度** | 中(仅 8 < ≥18)| **高**(完整 ≥18)| 低(workaround)| 中(scope 不收敛)| **C-B > C-A > C-D > C-C** |
| **长久 / 演化:底层依赖链** | 中(setter 8 独立)| **高**(setter ≥18 + ≥10 type class 总扩)| 低(无 setter 扩)| 中(依赖 D146 §F3)| **C-B > C-A/C-D > C-C** |
| **长久 / 演化:业界对标** | 中(部分 8 类型)| **高**(MySQL Connector/J ≥18 完整 + JDK java.*)| ❌(无 stringify 业界范式)| 中(分散 setter / metadata)| **C-B > C-A/C-D > C-C** |
| **长久 / 演化:N 年返工度** | 高(剩 ≥4 各自 sub-D)| **低**(一次到位)| 高(workaround 必返工)| 中(D146 §F3 起首条件)| **C-B > C-A/C-D > C-C** |
| **scope LOC delta** | ~150-300 | ~640-1370(C-B-1)/ ~70-150(C-B-2)/ ~370-1150(C-B-3 分轮)| 0(workaround 文档备忘)| 混合(setter + metadata) | C-A 中 / C-B 大但根因 / C-C 0 但违 §Root Cause / C-D 中 |

**§字段 10 (e) 自决策评估**:**C-B > C-A > C-D > C-C**(根因解决度 + 长久 / 演化维度);用户对话已锁 C-B(2026-05-04)。

### 决策行(Phase 0 锁 C-B,C-B 子候选 C-B-1/2/3 不锁 留用户对话授权)

**用户对话锁 C-B**(2026-05-04)— Phase 0 启动轮用户口令 "C-B"。

**C-B 子候选 C-B-1/2/3 决策行不锁定** — 类比 D148 Phase 2 H15 / D149 Phase 2 H12 / D150 Phase 0 H3 用户对话授权门槛触发(C-B 范畴涉及底层 type class scope 决定 + 阶段实施分散度,长久演化影响范围扩到 D152-D161 多 sub-D 起首,需用户对话锁定 C-B-1 / C-B-2 / C-B-3),Phase 0 启动轮不自决策,等用户对话明确锁定后才入 Phase 1 候选范畴细化 + 路径分支。

**类比范式**:
- D148 Phase 2 H15:bidirectional 接管副作用清零候选 B1 / B2,用户对话锁 B1
- D149 Phase 2 H12:架构层 refactor C2 / C3,用户对话锁 C3
- D150 Phase 0 H3:F5 v2 总体设计 vs F2/F3/F4 单点起首,用户对话锁 — D150 主线暂停转 SQL
- **D151 Phase 0**:C-B 已锁(2026-05-04)
- **D151 Phase 1**:C-B-1/2/3 子候选留用户对话锁

---

## §A.1.1 落点

### G1: 用户对话授权 C-B 子候选锁定(Phase 1 启动条件)

| 子候选 | 锁定后 Phase 1+ 落点 |
|---|---|
| **C-B-1 一次到位** | D151 主线 = ≥10 底层 type class(`lib/java/math.ss BigDecimal` + `lib/java/sql.ss` 加 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref + `lib/java/io.ss` 加 InputStream/Reader)+ ≥18 setter + 3 implementor + integration_test;Phase 2-N+ 分阶段实施 |
| C-B-2 仅 setter | D151 主线 = ≥18 setter + ptr / null-stub + 3 implementor + integration_test ptr edge case;底层 type class 留 D152-D161 sub-D 起首接力(N 年返工度高 — setter 签名改类型) |
| **C-B-3 底层先做** | D151'(新建 D 编号待定 — 可能 D152)= ≥10 底层 type class sub-D 先做 + D151 setter ≥18 起首接力;业界对标"先底层再上层"终局范式 |

### G2: Phase 0 hash 回填 + 路径分支后子 D 文档创建

- **D151 Phase 1**:Phase 0 commit hash 回填本 D 文档(D135-D150 范式延续 — 单 commit 不能引用自己 hash 下下轮回填)
- **C-B-1 锁定** → D151 主线 ≥10 底层 type class + ≥18 setter Phase 2-N+ 分阶段实施
- **C-B-2 锁定** → D151 主线 ≥18 setter + ptr / null-stub Phase 2 起首 + D152-D161 底层 type class sub-D 接力
- **C-B-3 锁定** → 新建 D152(底层 type class sub-D)先做 Phase 2 起首 + D151 setter 接力

---

## §A.2 隐藏假设

| H | 假设 | 实证 / 留 Phase | 失败回退 |
|---|---|---|---|
| H1 | **底层 type class 缺**:`lib/java/` 仅 `sql.ss`(14428 bytes)无 `math.ss` / `io.ss` / `time.ss`;`lib/java/sql.ss` 无 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref;`lib/` 无 BigDecimal class | ✓ Phase 0 实证(grep 0 命中,仅 `lib/datetime.ss:14 class DateTime {}` 空 class 非 JDBC 标准) | 底层 type class 已落 → C-B-2 仅 setter 路径成立 LOC ~70 |
| H2 | C-B 用户对话锁 C-B-1/C-B-2/C-B-3 子候选 — 用户对话明确二次锁定 | Phase 1 留(用户对话明确锁定 C-B-1/2/3 后才入 Phase 2+) | 用户对话授权未触发 → Phase 1 阻塞 |
| H3 | C-B-1 一次到位 LOC delta ~640-1370 | Phase 1+ 实测验证(若 C-B-1 锁定 — `lib/java/math.ss` BigDecimal + `lib/java/sql.ss` 加 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref + `lib/java/io.ss` 加 InputStream/Reader 实测) | scope > 估 → Phase 拆分细化 |
| H4 | C-B-2 仅 setter LOC delta ~70-150 | Phase 1+ 实测验证(若 C-B-2 锁定 — `lib/java/sql.ss` interface ResultSet 加 ≥18 setter + 3 implementor stub) | scope > 估 → Phase 拆分细化 |
| H5 | C-B-3 底层先做 LOC delta ~370-1150(分轮) | Phase 1+ 实测验证(若 C-B-3 锁定 — 新建 D152 底层 type class sub-D + D151 setter sub-D 接力) | scope > 估 → Phase 拆分细化 |
| H6 | bootstrap 三阶段固定点不破(D135-D150 范式延续) | Phase 2+ 留(各候选实施时验证 — `./build.sh bootstrap` Stage 2 = Stage 3) | 三阶段固定点破 → 回 Phase 1 修自然链路 |
| H7 | 不引入新关键字 / 新语法(继承 D147 §核心原则 13) | Phase 0 实证(继承 D147 §核心原则 1 不破 — 底层 type class + setter 都复用既有 SS class / interface 语法机制) | 需引入新语法 → 不选(违 CLAUDE.md §Java/TS 语法优先 + §核心原则 2) |
| H8 | `MysqlBinaryResultSet` via `writeCol` stringify pattern(`prepared.ss:666-675` 范式)可直翻 ≥22 setter — `writeCol(col, "" + val)` / `writeCol(col, val.toString())` | Phase 2-N+ 实测验证(BigDecimal.toString / Timestamp.toString / Bytes hex encode 等) | stringify 失败 → 部分 setter 走 binary protocol 直接 encode(setBigDecimalDecimal binary 范式) |
| H9 | integration_test 扩 cases 真 type 写入 server-side 可观测验证 — UPDATE/INSERT BigDecimal/Timestamp/Bytes 等 + 外部 SELECT 验值 | Phase 2-N+ 实测验证(docker MySQL `DECIMAL(10,2) / TIMESTAMP / VARBINARY(255)` schema 真 type 字段) | server-side 验值失败 → 修 driver-side stringify / encode 逻辑 |
| H10 | D147 主线 6 setter 不破(继承 D147 §核心目标 单一判据 7 case 7 形态) | Phase 2-N+ 留(扩 setter 不动 D147 6 核心 setter + integration_test 7 case 全 GREEN) | D147 主线 7 case 破 → 回 Phase 2 修兼容性 |

---

## §A.3 废案

- **C-A 仅扩 D147 §F1 字面 8 类型全废**(用户对话锁 C-B 完整 ≥18 method;C-A 是节省路径违反 §核心原则 1 "完整不裁剪")
- **C-C 数据层 patch / stringify workaround 全废**(违反 CLAUDE.md §Root Cause 优先 + memory `feedback_no_derive_workaround`;主线能力缺口不允许 stringify workaround)
- **C-D 合入 D146 §F3 ResultSetMetaData 全废**(scope 不收敛 — setter 扩 + metadata 是两不同 API 层 + 跨 D 依赖 D146 §F3 先决条件)
- **越过用户对话授权门槛自决策 C-B-1/2/3 全废**(类比 D148 Phase 2 H15 / D149 Phase 2 H12 / D150 Phase 0 H3 范式 — Phase 0 §字段 10 (e) 自决策评估 C-B-3 ≥ C-B-1 > C-B-2 但决策行不锁定,等用户对话明确锁定后才入 Phase 1)
- **改 D147 主线 / D146 主线 / D025 / D052 / D134 / D139 等依赖 D 文档全废**(D147 主线已 close + D146 不破 + 依赖 D 文档不破 — D151 仅 §F1 扩展)
- **引入新关键字 / 新语法全废**(CLAUDE.md §Java/TS 语法优先红线;JDBC 4.3 §15.2.5 setter + JDK java.* type class 都不需新语法支持)
- **annotation handler 旁路 ≥10 type class 全废**(`feedback_no_derive_workaround` 红线 — 主线能力缺口不允许 @derive / annotation handler 作为替代路径)

---

## Phase 收关锚

### Phase 0: D 文档落档 + 候选锁定 C-B + 底层依赖链实证 + C-B-1/2/3 子候选评估 fact 入档 + 决策行不锁定 留用户对话授权 [✓] Done at commit `<placeholder>`(留 D151 Phase 1 启动轮回填 — D135-D150 范式 单 commit 不能引用自己 hash 下下轮回填)(2026-05-04)

- **D151.md 文档新建** ~400 行(本 commit)— Status header + Depends on D147/D146/D138/D139/D025/D134/D052 + Date 2026-05-04 + §核心目标 + §核心原则 13 条 + §1 Context(D147 主线 close 后 §F1 起首状态 + 累计 sub-D 链路 + 业界对标 + 底层 type class 缺实证)+ §2 RED 锚 + §3 Orchestration Phase 0-N+ + §A.1 4 候选评估 + C-B 内 C-B-1/2/3 子候选评估 + §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 7 条 + §Phase 收关锚 + §Followup + §Status 时间线 Phase 0 entry
- **D147 §Followup F1 line 218 标 D151 起首** — D147.md edit 加 "(D151 起首 at commit `<placeholder>` 留下下轮回填,2026-05-04 用户对话锁 C-B 完整 + 底层依赖链实证)" 标
- **底层依赖链实证 fact 入档**(§A.2 H1)— `lib/java/` 仅 `sql.ss`(14428 bytes)无 `math.ss` / `io.ss` / `time.ss`;`lib/java/sql.ss` 无 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref;`lib/` 无 BigDecimal class(grep 0 命中,仅 `lib/datetime.ss:14 class DateTime {}` 空 class 非 JDBC 标准)
- **C-B-1/2/3 子候选评估 fact 入档**(§A.1 决策行 — C-B-1 一次到位 / C-B-2 仅 setter / C-B-3 底层先做三子候选评估表 + §字段 10 (e) 自决策评估 C-B-3 ≥ C-B-1 > C-B-2 + 决策行不锁定 留用户对话授权门槛触发)
- **§A.2 H1-H10 加入** + **§A.3 废案 7 条**
- **VCM §1 豁免锚成立**(Phase 0 docs-only — `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D147-*.md §Followup F1 标 + 新建 docs/3-decisions/D151-*.md)
- **simplify 跳过 docs-only 例外**(纯文档 D147 §F1 标 + D151.md 新建)
- **d_doc_index_linter F1=0 GATE OK** + **ultrathink_linter PASS** + **D135-D150 范式延续**
- **MNK §M meta-gate 强制四问全 ✓**(深度读 D147.md §核心目标 line 27-60 + §核心原则 1-13 line 64-78 + §A.1 line 82-90 决策行 C2 选 + §A.2 H1-H7 + §A.3 line 108-116 废案 7 条 + §Phase 收关锚 Phase 0-5 全 [✓] line 122-209 + §Followup F1-F7 line 214-225 + 历史 D135-D150 SQL 主线范式延续 + Phase 0 启动条件验证未漏 — D147 主线 close at `8323501` 后 D147 §F1 line 218 直接 followup 起首 + 底层依赖链实证 ≥10 type class 缺 + C-B-1/2/3 子候选 fact 入档 + 用户对话授权门槛触发(类比 D148 H15 / D149 H12 / D150 H3 范式)+ 兑现 a-h 总览每条 file:line 锚)
- **D151 Phase 0 commit hash 留 D151 Phase 1 启动轮回填**(D135-D150 范式 — 单 commit 不能引用自己 hash 下下轮回填)

### Phase 1+ Planned

- 用户对话授权门槛触发 + C-B 子候选锁定(C-B-1 / C-B-2 / C-B-3)
- C-B-1 锁定 → D151 主线 = ≥10 底层 type class + ≥18 setter Phase 2-N+ 分阶段实施
- C-B-2 锁定 → D151 主线 = ≥18 setter + ptr / null-stub Phase 2 起首 + D152-D161 底层 type class sub-D 接力
- C-B-3 锁定 → 新建 D152 底层 type class sub-D 先做 Phase 2 起首 + D151 setter 接力

---

## Followup

> **D151 Phase 0 落档后 — 候选锁定后展开**(2026-05-04):候选锁定后(Phase 1),后续 sub-D 起首队列由 C-B-1 一次到位(D151 主线分阶段)/ C-B-2 仅 setter + 底层 type class D152-D161 接力 / C-B-3 D152 底层先做 + D151 setter 后做 决定;本 §Followup 表暂留 SQL 主线 followup 队列(D147 §F2/F3 / D146 §F2/F3 / D138 §F1 / D107 等)候选锁定后再扩 D151 各阶段 followup。

| # | 锚 | 描述 | 启动条件 |
|---|---|---|---|
| F1 | D147 §F2 SELECT FOR UPDATE 行锁 + RR isolation level + InnoDB lock wait timeout | SQL standard `SELECT ... FOR UPDATE` 行锁与 cursor 正交独立 sub-D | D151 主线 close 后 |
| F2 | D147 §F3 multi-PK / 多表 join updatable cursor | 本 D 仅最小子集(单表 SELECT 单 PK);multi-PK 复合主键 + 多表 join 留独立 sub-D | D151 主线 close 后 |
| F3 | D146 §F2 holdability HOLD_CURSORS_OVER_COMMIT / CLOSE_CURSORS_AT_COMMIT | cursor + transaction commit 行为 | D151 主线 close 后 |
| F4 | D146 §F3 ResultSetMetaData 完整列元数据 | getColumnTypeName / isAutoIncrement / isPrimaryKey 等 | D151 主线 close 后 |
| F5 | D138 §F1 KeyHolder.getKey 类型扩展 + HikariCP | 自动生成主键类型 + 连接池 | D151 主线 close 后 |
| F6 | D107 PostgreSQL driver 起首 | 跨数据库扩展新方向(D107 未首次落档) | D151 主线 close 后 |

---

## Status 时间线

- 2026-05-04 Phase 0 D 文档落档 + 候选锁定 C-B + 底层依赖链实证 + C-B-1/2/3 子候选评估 fact 入档 + 决策行不锁定 留用户对话授权 docs only(commit `<placeholder>` 留 D151 Phase 1 启动轮回填)— **D151 Phase 0 兑现 a-h 八项 fact 全 GREEN + D147 主线 close at `8323501` 后 D147 §F1 line 218 起首 + 用户对话锁 C-B 完整 JDBC 4.3 §15.2.5 ≥18 method + D135-D150 范式延续**:(a) D151.md 新建 ~400 行 docs-only(本 commit)— Status header + Depends on D147/D146/D138/D139/D025/D134/D052 + Date 2026-05-04 + §核心目标 + §核心原则 13 条 + §1 Context + §2 RED 锚 + §3 Orchestration Phase 0-N+ + §A.1 4 候选 + C-B 内 C-B-1/2/3 子候选评估 + §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 7 条 + §Phase 收关锚 + §Followup + §Status 时间线;(b) D147 §Followup F1 line 218 标 D151 起首(hash `<placeholder>` 留下下轮回填);(c) **底层依赖链实证 fact 入档**(§A.2 H1)— `lib/java/` 仅 `sql.ss`(14428 bytes)无 `math.ss` / `io.ss` / `time.ss`;`lib/java/sql.ss` 无 Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/Array/Ref;`lib/` 无 BigDecimal class(grep 0 命中,仅 `lib/datetime.ss:14 class DateTime {}` 空 class 非 JDBC 标准);(d) **C-B-1/2/3 子候选评估 fact 入档**(§A.1 决策行 — C-B-1 一次到位 ~640-1370 LOC / C-B-2 仅 setter ~70-150 LOC / C-B-3 底层先做 ~370-1150 LOC 分轮)+ §字段 10 (e) 自决策评估 C-B-3 ≥ C-B-1 > C-B-2(底层依赖链先决 + 业界对标 + N 年返工度);(e) §A.2 H1-H10 加入 + §A.3 废案 7 条;(f) VCM §1 豁免锚成立 docs-only(`git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D147-*.md §Followup F1 标 + 新建 docs/3-decisions/D151-*.md);simplify 跳过 docs-only 例外;d_doc_index_linter F1=0 GATE OK + ultrathink GATE OK 3/3 PASS;(g) MNK §M meta-gate 强制四问全 ✓(深度读 D147.md §核心目标 line 27-60 + §核心原则 1-13 line 64-78 + §A.1 line 82-90 决策行 C2 选 + §A.2 H1-H7 + §A.3 line 108-116 废案 7 条 + §Phase 收关锚 Phase 0-5 全 [✓] line 122-209 + §Followup F1-F7 line 214-225 + 历史 D135-D150 SQL 主线范式延续 + Phase 0 启动条件验证未漏);(h) D151 Phase 0 commit hash 留 D151 Phase 1 启动轮回填(D135-D150 范式 — 单 commit 不能引用自己 hash 下下轮回填);**新发现**:(i) D147 主线 close 后 D151 起首延续 D135-D150 SQL 主线范式 — D147 主线 close at `8323501` → D150 主线暂停(v2 类型系统 SQL 零受益)→ D151 起首 commit `<placeholder>` 范式延续(单 commit 不能引用自己 hash 下下轮回填);(ii) **底层依赖链实证 fact 关键** — Phase 0 grep 0 命中证明 ≥10 底层 type class 缺,改变 C-B 实际范畴 = setter 接口 + ≥10 type class 总扩,LOC 估上调到 ~640-1370(原 PSM §字段 10 估 400-800 上调 — 原估未含底层 type class scope);(iii) **C-B 子候选 C-B-1/2/3 不在原 PSM §字段 10 候选评估** — Phase 0 实测后才显化(原 PSM 仅 C-A/C-B/C-C/C-D 4 候选,C-B 实测后内部分裂为 C-B-1 一次到位 / C-B-2 仅 setter / C-B-3 底层先做),需用户对话二次授权(类比 D149 Phase 2 C2 vs C3 在 Phase 1 实测后才显化范式延续);(iv) **D147 §F1 字面 vs 实测 vs JDBC 标准三层 refine** — 字面"6 setter 扩展类型"(口号 6,实际"扩展" implies new types)vs 实测列举 8 类型(BigDecimal/Timestamp/Date/Time/Bytes/Float/Short/Byte)vs JDBC 4.3 §15.2.5 ≥18 method scope — memory `feedback_user_literal_vs_d_ssot` 同形防御 14 次落档 PSM §字段 3,与历史"字面 vs 实测"refine 反差实证延续(D148 Phase 5 字面"5 处"实测 6 / D149 Phase 0 字面"3 处"实测 4 / D149 Phase 3 字面"8 处"实测 6 行 8 字串 / D150 启动字面"6 处"实测 6 行 10 字串非均匀分布);(v) D135-D150 sub-D 链路 + D151 起首选择 — 累计 15 sub-D 链路 D135 → D136 → D137 → D138 → D139 → D140 → D141 → D142 → D143 → D144 → D145 → D146 → D147 close → D150 主线暂停 → D151 起 §F1 sub-D + 候选锁定后路径分支(C-B-1 一次到位 / C-B-2 仅 setter / C-B-3 底层先做);(vi) D151 Phase 0 commit hash 留 D151 Phase 1 启动轮回填(D135-D150 范式 — 单 commit 不能引用自己 hash 下下轮回填);(vii) Phase 0 文档路径错误教训防御 — D151 sub-D 候选评估 file:line 锚必须 grep 验证后再写(memory `feedback_d026_d027_phantom_anchor.md` 同形教训 — 引用任一锚必先 ls 验真身,本 D 文档 Phase 0 candidate 评估 file:line 锚全部 grep 验证后写)+ next_prompt 自闭环(.claude/next_prompt.md 写 D151 Phase 1 启动 = D151 Phase 0 commit hash 回填 + 用户对话授权门槛触发 + 候选锁定 C-B-1/2/3 + 候选范畴细化 + 路径分支 + ultrathink GATE OK 3/3 PASS)
