# D153: SS 编译器 interface dispatch fallthrough — 修 codegen 让 interface 无 implementor 时 `__iface_<I>_<m>` dispatch fn emit panic stub 允许 link(D151 §F2 sub-D)

**Status:** Phase 0 落档(D151 主线 close at `b646978` 后 §F2 起首接力 — 编译器层 sub-D 第一例 + 用户对话锁定 待 Phase 1 授权门槛触发 + 候选 C-A/C-B/C-C/C-D fact 入档 + §字段 10 (e) 自决策评估 C-A ≥ C-B > C-D > C-C — 根因解决度 + 业界对标 LLVM `linkonce_odr` / JVM `invokeinterface` / V8 hidden class / Rust trait `dyn Trait` vtable miss 范式 + N 年返工度 + D135-D152 范式延续 + D151 §A.2 H8 实证锚)+ docs only(VCM §1 豁免锚成立 — `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D151-*.md hash 回填 + §F8 标 D153 起首 + 新建 docs/3-decisions/D153-*.md)+ d_doc_index F1=0 GATE OK + ultrathink GATE OK 3/3 PASS + simplify 跳过 docs-only 例外。

**Depends on:** D151(ResultSet update type extension 主线 close at `b646978`,本 D 起 §F2 编译器 fallthrough)+ D147(updatable cursor + ResultSet update 6 核心 setter)+ D152(JDBC type class foundation — `lib/java/{math,sql,io}.ss` ≥10 底层 type class)+ D025(class layout `{ i32 rc, ptr TypeInfo, ...fields }` + interface vtable `__iface_<I>_<m>` dispatch fn 范式)+ D097(reflection 根因 metrics — 编译器层 metrics 治理)+ D052(named arg `k: v` syntax)

**Date:** 2026-05-04

---

## 核心目标

D151 §F2 line 319 "SS 编译器 interface dispatch fallthrough(无 implementor 时 dispatch fn emit panic stub 允许 link)" sub-D 起首,根因解 D151 Phase 4 实证 H8 假设破裂部分降级 — `MysqlBinaryResultSet` 12 interface-typed setter(updateTimestamp/updateDate/updateTime/updateBlob/updateClob/updateNClob/updateRowId/updateSQLXML/updateArray/updateRef/updateAsciiStream/updateBinaryStream/updateCharacterStream/updateNCharacterStream)真 stringify 触发 SS 编译器 codegen `__iface_<I>_<m>` dispatch fn 强制每 import 单元有 implementor 限制 → llc-18 报 `use of undefined value '@__iface_Date_toString'` 编译失败,降级 stub no-op fallback。**修编译器 codegen 让 interface 无 implementor 时 dispatch fn emit panic abort stub 允许 link**(类比 LLVM `linkonce_odr` 弱符号 — 多翻译单元各自 emit dispatch fn 链接器选一份),根因解 H8 stringify pattern 限制,使 D151 §F1 driver class impl 真 stringify 有干净落地路径。

**第一性需求**:
- D151 Phase 4 H8 假设破裂实证 — 12 interface-typed setter 真 stringify 阻塞,降级 stub no-op fallback(`lib/com/mysql/prepared.ss:440` MysqlBinaryResultSet 14 stub),违反 CLAUDE.md §Root Cause 优先 + D151 §核心原则 1 "完整不裁剪"
- D152 sibling 测试因 import 拉入 `lib/java/sql.ss` 但无 Date/Time/Timestamp implementor 时 llc-18 链接失败(d152 blob_test 等若直接 stringify 即触发,当前绕过 stub-based dispatch)
- 业界对标 — LLVM `linkonce_odr` 弱符号 / JVM `invokeinterface` itable miss `AbstractMethodError` 运行时 trap / V8 hidden class transition polymorphic IC slow path / Rust trait `dyn Trait` vtable 在 monomorphization 时 catch — 各成熟系统都有 vtable miss 处理范式,SS 当前缺
- N 年返工度 — D151 §F1 driver class impl(production driver impl class MysqlTimestamp/MysqlBlob/MysqlClob 等)落地后真 stringify dispatch 仍需编译器层 fallthrough 修复,否则每加一个 sibling 测试都需手动 stub implementor,scale 失败 → 编译器层根因解一次到位低返工度

**底层依赖链实证**(§A.2 H1 关键 fact):
- SS 编译器 codegen `bootstrap/gen/exprs/method_call.ss` 在 interface method call 处 emit `call ptr @__iface_<I>_<m>(...)` 无条件 emit
- `@__iface_<I>_<m>` dispatch fn body 在 interface 有 implementor 时 emit per-implementor switch dispatch,无 implementor 时**不 emit** dispatch fn body → llc-18 链接时 `use of undefined value '@__iface_<I>_<m>'`
- 当前 SS lib/java/sql.ss interface ResultSet 在 d151 integration_test 有 implementor(D151TestStub)所以 emit 成功;但 d152 blob_test 等 sibling 测试 import sql.ss 但无 Date/Time/Timestamp implementor → 若 stringify 触发 `Date.toString()` 即 llc-18 链接失败
- D151 Phase 4 实证 — MysqlBinaryResultSet 12 interface-typed setter 走 `writeCol(col, val.toString())` 范式直接触发该限制 → 降级 stub no-op fallback

**不在范畴**:
- ❌ C-C 用户层手动确保每 import 单元有 implementor stub(已废 — 违反 CLAUDE.md "编译器吸收复杂度" + 不 scale + 违 §核心原则 1,§A.3)
- ❌ C-D interface 改 abstract class 用 vtable static dispatch(已废 — 违反 D025 class layout 主语言重设计 scope 爆炸,§A.3)
- ❌ 越过用户对话授权门槛自决策 C-A/C-B(类比 D148 H15 / D149 H12 / D150 H3 / D151 Phase 0 范式,Phase 0 不锁子候选,等用户对话二次授权)

---

## 核心原则

(继承 CLAUDE.md + D151 §核心原则 13 条 + D147 §核心原则):

1. **编译器吸收复杂度**(继承 CLAUDE.md §项目技术规则)— 用户不应看到 interface dispatch 内部机制的语法暴露;每 import 单元 implementor 强制要求是 codegen 限制 leak,需根因解
2. **不引入新关键字 / 新语法**(继承 D147 §核心原则 1)— 复用既有 SS interface / class 语法机制;codegen 层修改不暴露用户层
3. **Root Cause 优先**(CLAUDE.md §Root Cause 优先 第一法则,无例外)— 候选评估按根因解决度 + 长久 / 演化维度排序,**禁按 LOC 最少 / 工程量最小作排序依据**
4. **业界对标**(CLAUDE.md §长久 / 演化维度)— LLVM `linkonce_odr` 弱符号 + JVM `invokeinterface` itable miss + V8 hidden class transition + Rust trait `dyn Trait` vtable 各成熟系统范式
5. **N 年返工度低**(CLAUDE.md §长久 / 演化维度)— 编译器层根因解一次到位 vs 用户层 stub workaround 每 sibling 测试需手动 stub
6. **底层依赖链先决**(CLAUDE.md §长久 / 演化维度 + memory `feedback_root_cause_no_cost.md` §8)— D153 §F2 是 D151 §F1 driver class impl 的根因依赖(编译器修复后 §F1 真 stringify 才有干净落地路径),优先级 ≥ §F1
7. **bootstrap 三阶段固定点不破**(D135-D152 范式延续)— Phase 2+ 修改 codegen 后 `./build.sh bootstrap` Stage 2 = Stage 3
8. **决策行不锁定 留用户对话授权门槛触发**(类比 D148 Phase 2 H15 / D149 Phase 2 H12 / D150 Phase 0 H3 / D151 Phase 0 范式)— Phase 0 启动轮 4 候选 fact 入档 + §字段 10 (e) 自决策评估 C-A ≥ C-B > C-D > C-C,但决策行不锁定,等用户对话明确锁定后才入 Phase 1 候选范畴细化
9. **D147 §核心原则 10 stub fallback 临时降级保护**(继承)— Phase 2+ 编译器修复期间 `lib/com/mysql/prepared.ss` MysqlBinaryResultSet 14 stub 不破;修复后真 stringify 解锁逐步替换
10. **Phase 计划独立 commit**(继承 D147 §核心原则 11)— Phase 0-N+ 独立 commit
11. **integration_test 验证 真 stringify GREEN**(继承 D147 §核心原则 12)— Phase 2+ 修复后 d151 integration_test 14 stub no-op 替换为真 stringify dispatch + d152 sibling 测试 import sql.ss 不破
12. **SS 编译器扩按需 + 业界对标确认**(继承 D147 §核心原则 13)— Phase 0 不预判 codegen 修改 LOC,Phase 1+ 实测 spike 走假设破裂回路 fallback;编译器层修改业界对标 LLVM `linkonce_odr` 范式
13. **D151 §A.2 H8 实证锚不破**(本 D 核心)— Phase 4 H8 部分破裂实证 stub fallback 范式延续 D147 §核心原则 10;本 D 修复后 H8 假设全 PASS,12 interface-typed setter 真 stringify 解锁

---

## §1 Context

### D151 主线 close 后 §F2 起首状态(commit `b646978`)

- ✓ **D151 主线 GREEN** — JDBC 4.3 §15.2.5 ResultSet update setter 18 method 接口完整 + 3 implementor 同步落档 + integration_test 18 case stub-based dispatch GREEN(close at commit `b646978`)
- ✓ **D151 §F2 line 319 起首条件具备** — D151 主线 close 后 §Followup F8 RED 启动条件 = D151 Phase 4 实证 H8 假设破裂部分降级(MysqlBinaryResultSet 12 interface-typed setter 真 stringify 阻塞 → 降级 stub no-op fallback)
- ⚠ **编译器层根因实证**(§A.2 H1)— SS codegen `bootstrap/gen/exprs/method_call.ss` 在 interface method call 处 emit `call ptr @__iface_<I>_<m>(...)` 无条件 emit;`@__iface_<I>_<m>` dispatch fn body 在 interface 无 implementor 时不 emit → llc-18 链接失败 `use of undefined value '@__iface_<I>_<m>'`

### 累计 sub-D 链路

D135 → D136 → D137 → D138 → D139 → D140 → D141 → D142 → D143 → D144 → D145 → D146 → **D147 close at `8323501`** SQL 主线 close 第一例 → **D150 主线暂停**(v2 类型系统 SQL libs 零受益实证)→ **D151 §F1 起首 + Phase 0/1** → **D152 sub-D 起首到 close at `6ded44d`** SQL 主线 close 第二例 → **D151 Phase 2 wrapper close at `6ded44d`** SQL 主线 close 第三例 → **D151 Phase 3 at `01c4aad`** → **D151 Phase 4 at `2eac262`** → **D151 主线 close at `b646978`** SQL 主线 close 第四例 → **D153 §F2 sub-D 起首**(本轮)— **编译器层 sub-D 第一例**

### 业界对标

- **LLVM `linkonce_odr` 弱符号** — 多翻译单元各自 emit dispatch fn 链接器选一份;dispatch fn body 在无实际 impl 时 emit panic abort stub 允许 link,运行时若实际触发立即 trap 提示开发者补 implementor — **C-A 候选直接对标范式**
- **JVM `invokeinterface` itable miss** → throw `AbstractMethodError` 运行时 trap;itable lookup 在 interface 无 implementor 时 throw — **C-A 候选范式延续(编译时 emit + 运行时 trap)**
- **V8 hidden class transition** — polymorphic IC slow path 处理 vtable miss;hidden class 在新 type 出现时 transition,无 IC entry 时 fallback inline cache miss handler — **C-A 候选范式延续**
- **Rust trait `dyn Trait` vtable** — trait 在 generic monomorphization 时 catch impl 缺失编译时 catch;`dyn Trait` 必须每 impl 完整定义 vtable entry,缺则编译时报 `not all trait items implemented` — **C-B 候选范式延续(call site 编译时 conditional emit)**

SS 当前各 import 单元独立 emit `__iface_<I>_<m>` dispatch fn,无 implementor 时不 emit 但 call site 仍 emit → llc-18 undefined ref。C-A 范式 = LLVM `linkonce_odr` 弱符号 + dispatch fn body emit panic stub 允许 link 业界对标 LLVM 范式。

### D151 §A.2 H8 实证锚

D151 Phase 4 实证 H8 假设 "MysqlBinaryResultSet via writeCol stringify pattern 可直翻 ≥22 setter — `writeCol(col, "" + val)` / `writeCol(col, val.toString())`" **部分破裂**:

- **GREEN 部分**(4/18):BigDecimal class direct dispatch 无 vtable lookup 真实现可行 + Bytes/Object/NString string val 直接 passthrough 真实现可行
- **RED 部分**(14/18):12 interface-typed setter(Timestamp/Date/Time/Blob/Clob/NClob/RowId/SQLXML/SqlArray/Ref/InputStream/Reader)真 stringify 触发 SS 编译器 `__iface_<I>_<m>` dispatch fn 强制每 import lib/java/sql 单元都需 implementor — d152 blob_test.ss 等 sibling 测试无 Date/Time/Timestamp 等 implementor → llc-18 报 `use of undefined value '@__iface_Date_toString'` 编译失败 + 2 stream stub setter 同形

降级 fallback = D147 §核心原则 10 driver-side stub no-op 范式;**根因解 = D153 §F2(本 D)修编译器 codegen,使 dispatch fn 在 interface 无 implementor 时 emit panic stub 允许 link**。

---

## §2 RED 锚

D153 Phase 0 是「sub-D 起首选择 + 候选锁定」决策落档,无 RED bug 直接挂载;Phase 1+ 候选锁定后对应 RED:

```bash
# RED1: D151 Phase 4 实证 14 stub no-op(MysqlBinaryResultSet binary protocol)
grep -c "// stub" /root/code/simplescript-dev/simple-script/lib/com/mysql/prepared.ss
# 当前 ≥ 14(MysqlBinaryResultSet 14 setter stub no-op)
# 目标 0(修复后真 stringify dispatch 解锁)

# RED2: SS codegen interface dispatch fn emit 入口
grep -rn "__iface_" /root/code/simplescript-dev/simple-script/bootstrap/gen/
# 现状:codegen 仅在有 implementor 时 emit dispatch fn body
# 目标:无 implementor 时 emit panic abort stub allow link

# RED3: d152 sibling 测试 import sql.ss(若 stringify 即触发 llc-18)
grep -rn "import.*lib/java/sql" /root/code/simplescript-dev/simple-script/tests/d152_jdbc_type_class_foundation/
# 现状:绕过 stub-based dispatch (D152 Phase 5 chained call cross-interface vtable)
# 目标:可直接真 stringify 不破

# RED4: d151 integration_test 真 stringify 替换 stub no-op
grep -c "// stub no-op" /root/code/simplescript-dev/simple-script/tests/d151_resultset_update_type_extension/integration_test.ss
# 现状:14 stub no-op + 4 真实现 = 18 case
# 目标:18 真实现 GREEN
```

---

## §3 Orchestration

| Phase | 内容 | 落点 | 完成判据 |
|---|---|---|---|
| **Phase 0** [✓ Done at commit `<placeholder>`] | D 文档落档 + 候选锁定评估 fact 入档 + §字段 10 (e) 自决策评估 C-A ≥ C-B > C-D > C-C + 决策行不锁定 留用户对话授权门槛触发 | D153.md docs-only ~400 行 — Status header + Depends on D151/D147/D152/D025/D097/D052 + Date 2026-05-04 + §核心目标 + §核心原则 13 条 + §1 Context(D151 主线 close 后 §F2 起首状态 + 累计 sub-D 链路 18 + 业界对标 LLVM/JVM/V8/Rust + D151 §A.2 H8 实证锚)+ §2 RED 锚 + §3 Orchestration Phase 0-N+ + §A.1 4 候选(C-A LLVM linkonce_odr 范式 / C-B call site conditional / C-C 用户层 stub / C-D interface 改 abstract class)+ §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 + §Phase 收关锚 + §Followup + §Status 时间线 Phase 0 entry | bootstrap/lib/tools 不动(VCM §1 豁免锚成立)+ ultrathink GATE OK + d_doc_index F1=0 + simplify 跳过 docs-only 例外 |
| **Phase 1+** Planned | Phase 0 hash 回填 + 用户对话锁定候选 C-A/C-B/C-C/C-D + 候选范畴细化 + 路径分支 | Phase 0 hash 回填 D153.md + 用户对话锁定候选 + Phase 2+ 路径明确(C-A → 修 codegen `bootstrap/gen/exprs/method_call.ss` dispatch fn emit panic stub / C-B → 修 codegen call site conditional emit / C-C → 文档 + 用户教程 / C-D → 不可行废) | 用户对话授权门槛 PASS + Phase 0 hash 回填 GREEN + 候选范畴细化 + 路径分支 |
| **Phase 2+** Planned(候选锁定后展开)| 编译器 codegen 修复实施 + bootstrap 三阶段固定点 + integration_test 真 stringify 解锁 + d152 sibling 测试不破 | 候选锁定后落点 — C-A 修 `bootstrap/gen/exprs/method_call.ss` dispatch fn body emit panic abort stub(linkonce_odr 弱符号范式)+ d151 integration_test 14 stub no-op 替换真 stringify GREEN + d152 sibling 测试不破 + bootstrap 三阶段固定点 PASS | 编译器 codegen 修复 GREEN + d151/d152 测试套件全 PASS + bootstrap 三阶段固定点不破 + d_doc_index F1=0 |

**Phase 间依赖**: Phase 0 → 1(用户对话授权候选锁定门槛触发)→ Phase 2+(路径分支:C-A LLVM linkonce_odr / C-B call site conditional / C-C 用户层 / C-D 不可行)

**LOC delta 估**(候选 — Phase 1 用户授权后实测细化):
- **C-A LLVM linkonce_odr 范式**: ~20-80 LOC(`bootstrap/gen/exprs/method_call.ss` dispatch fn body emit panic stub + `bootstrap/gen/codegen.ss` interface metadata 扩 — 业界对标 LLVM 弱符号简单)
- **C-B call site conditional emit**: ~50-150 LOC(call site emit 处需查 implementor 状态 — codegen 状态依赖增加)
- **C-C 用户层手动 stub**: 0(编译器不改)+ 用户教程文档 ~50 行(每 sibling 测试需手动 register stub implementor — N 年返工度高)
- **C-D interface 改 abstract class**: 主语言重设计 ~500-2000 LOC(violates D025,不可行)

---

## §A.1 决策行

### C-A: dispatch fn body emit panic abort stub(LLVM linkonce_odr 弱符号范式 — ✓ 倾向)

**起 D153 主线**:修 `bootstrap/gen/exprs/method_call.ss`(或对应 codegen 入口)使 `@__iface_<I>_<m>` dispatch fn 在 interface 无 implementor 时 emit panic abort stub 允许 link。

**emit 范式**:
```llvm
; 当前(无 implementor 时不 emit → llc-18 undefined ref)
; 目标:无 implementor 时 emit panic stub
define ptr @__iface_Date_toString(ptr %self) {
  call void @ss_panic_msg(ptr @.iface_dispatch_no_impl_msg)
  unreachable
}
```

**链接行为**:LLVM `linkonce_odr` 弱符号 — 多翻译单元各自 emit dispatch fn 链接器选一份;若用户后续添加 implementor 链接器选有效实现而非 panic stub;若用户从未添加 implementor 但调用了该 method,运行时立即 trap 提示开发者补 implementor。

**§字段 10 (e) 自决策评估**(C-A vs 其他):
- **根因解决度**:**高**(编译器层根因解一次到位 + 业界对标 LLVM `linkonce_odr` 范式直接对标)
- **长久 / 演化维度**:**高**(底层依赖链 — D151 §F1 driver class impl 依赖本 D 修复后才有干净落地路径;业界对标 LLVM/JVM/V8/Rust 各成熟系统范式;N 年返工度 — 编译器层根因解一次到位低返工)

### C-B: call site conditional emit(Rust `dyn Trait` 范式)

**起 D153 主线**:修 codegen call site emit 逻辑,仅在 interface 有 implementor 时 emit `call ptr @__iface_<I>_<m>`,否则 emit inline panic call。

**§字段 10 (e) 自决策评估**(C-B vs 其他):
- **根因解决度**:**中**(仅 call site 处理,dispatch fn body 仍可能孤立 emit)
- **长久 / 演化维度**:**中**(call site 需要 codegen 时知道当前 import 单元 implementor 状态 — codegen 状态依赖增加;Rust 范式但 SS interface 不是 Rust trait 范式 — 模型不一致)

### C-C: 用户层手动确保每 import 单元有 implementor stub

**已废**(§A.3):违反 CLAUDE.md "编译器吸收复杂度" + 不 scale + 违 §核心原则 1 — 每 sibling 测试都需手动 register stub implementor,scope 爆炸 + N 年返工度高。

### C-D: interface 改 abstract class 用 vtable static dispatch

**已废**(§A.3):主语言重设计,违反 D025 class layout + scope 爆炸不可行 — interface 是 SS 主语言核心机制,改 abstract class 涉及 lexer/parser/checker/PIR/codegen 全链路 ~500-2000 LOC + 用户层语义改变。

### 候选评估 4 维度对比表

| 维度 | **C-A LLVM linkonce_odr**(✓ 倾向)| C-B call site conditional | C-C 用户层 stub | C-D interface 改 abstract class | 决策倾向 |
|---|---|---|---|---|---|
| **根因解决度** | **高**(编译器层根因解 + 业界对标 LLVM 范式)| 中(call site 处理 dispatch fn 仍孤立 emit)| 低(workaround,违 §核心原则 1)| 高(主语言重设计 — 但 scope 爆炸不可行)| **C-A > C-B > C-D > C-C** |
| **长久 / 演化:底层依赖链** | **高**(D151 §F1 driver class impl 依赖)| 中(call site 状态依赖增加)| 低(每 sibling 测试需手动 stub)| 高(主语言改 — 但不可行)| **C-A > C-B > C-D > C-C** |
| **长久 / 演化:业界对标** | **高**(LLVM linkonce_odr / JVM AbstractMethodError / V8 polymorphic IC)| 中(Rust dyn Trait 范式但 SS 模型不一致)| ❌(无业界范式)| 中(主语言重设计无业界对标)| **C-A > C-B > C-D > C-C** |
| **长久 / 演化:N 年返工度** | **低**(编译器层一次到位)| 中(call site 状态依赖 N 年维护)| 高(每 sibling 测试 stub 维护)| 高(主语言重设计返工)| **C-A > C-B > C-D > C-C** |
| **scope LOC delta** | ~20-80(简单)| ~50-150(中)| 0(用户教程 50)| ~500-2000(不可行)| C-A 最小 + 根因 / C-B 中 / C-C 0 但违 §Root Cause / C-D 大且不可行 |

**§字段 10 (e) 自决策评估**:**C-A ≥ C-B > C-D > C-C**(根因解决度 + 长久 / 演化维度);Phase 0 不锁,等用户对话明确锁定后才入 Phase 1。

### 决策行(Phase 0 不锁子候选 留用户对话授权)

**用户对话锁未触发** — Phase 0 启动轮 4 候选 fact 入档 + §字段 10 (e) 自决策评估倾向 C-A,但决策行不锁定。

**决策行不锁定** — 类比 D148 Phase 2 H15 / D149 Phase 2 H12 / D150 Phase 0 H3 / D151 Phase 0 用户对话授权门槛触发(C-A 涉及 SS 编译器 codegen 修改 + bootstrap 三阶段固定点风险 + D151 §F1 driver class impl 落地路径,长久演化影响范围扩到编译器层 + SQL 主线全部 sub-D),需用户对话锁定 C-A / C-B / C-C / C-D,Phase 0 不自决策,等用户对话明确锁定后才入 Phase 1 候选范畴细化。

**类比范式**:
- D148 Phase 2 H15:bidirectional 接管副作用清零候选 B1 / B2,用户对话锁 B1
- D149 Phase 2 H12:架构层 refactor C2 / C3,用户对话锁 C3
- D150 Phase 0 H3:F5 v2 总体设计 vs F2/F3/F4 单点起首,用户对话锁 — D150 主线暂停转 SQL
- D151 Phase 0:C-B 已锁(2026-05-04),Phase 1 进一步 C-B-3 已锁
- **D153 Phase 0**:**4 候选 fact 入档 + 决策行不锁定**(待用户对话授权门槛触发)

---

## §A.1.1 落点

### G1: 用户对话授权候选锁定(Phase 1 启动条件)

| 候选 | 锁定后 Phase 1+ 落点 |
|---|---|
| **C-A LLVM linkonce_odr**(倾向)| Phase 2 = 修 `bootstrap/gen/exprs/method_call.ss`(或 codegen interface dispatch fn emit 入口)使 `@__iface_<I>_<m>` dispatch fn body 在 interface 无 implementor 时 emit panic abort stub `call void @ss_panic_msg(ptr @.iface_dispatch_no_impl_msg) unreachable`(LLVM `linkonce_odr` 弱符号范式);Phase 3+ d151 integration_test 14 stub no-op 替换真 stringify GREEN + d152 sibling 测试不破 |
| C-B call site conditional | Phase 2 = 修 codegen call site emit 处查 implementor 状态;Phase 3+ d151 integration_test + d152 sibling 验证 |
| C-C 用户层 stub | 不可行,文档 + 用户教程 |
| C-D interface 改 abstract class | 不可行废 |

### G2: Phase 0 hash 回填 + 路径分支后子 D 文档创建

- **D153 Phase 1**:Phase 0 commit hash 回填本 D 文档(D135-D152 范式延续 — 单 commit 不能引用自己 hash 下下轮回填)
- **C-A 锁定** → Phase 2 起首接力 codegen 修复 + Phase 3+ integration_test 真 stringify 解锁
- **C-B 锁定** → Phase 2 起首接力 call site emit 修改 + Phase 3+ 验证
- **C-C 锁定** → 文档 + 用户教程(不推荐)
- **C-D 锁定** → 不可行废

---

## §A.2 隐藏假设

| H | 假设 | 实证 / 留 Phase | 失败回退 |
|---|---|---|---|
| H1 | **SS codegen `__iface_<I>_<m>` dispatch fn emit 入口实证** — codegen 在 interface 有 implementor 时 emit dispatch fn body 含 per-implementor switch dispatch,无 implementor 时不 emit 但 call site 仍 emit `call ptr @__iface_<I>_<m>` → llc-18 undefined ref | ✓ Phase 0 实证(D151 Phase 4 实测 12 interface-typed setter 真 stringify 触发该限制;`grep -rn "__iface_" bootstrap/gen/` 实证 emit 入口) | 实证错位 → 回 Phase 0 修 §1 Context |
| H2 | C-A/C-B/C-C/C-D 用户对话锁子候选 — 用户对话明确二次锁定 | Phase 1 留(类比 D148 H15 / D149 H12 / D150 H3 / D151 Phase 0 范式) | 用户对话授权未触发 → Phase 1 阻塞 |
| H3 | C-A LLVM `linkonce_odr` 范式 LOC delta ~20-80 | Phase 1+ 实测验证(若 C-A 锁定 — 修 `bootstrap/gen/exprs/method_call.ss` dispatch fn body emit panic stub) | scope > 估 → Phase 拆分细化 |
| H4 | C-B call site conditional emit LOC delta ~50-150 | Phase 1+ 实测验证(若 C-B 锁定 — 修 codegen call site 查 implementor 状态) | scope > 估 → Phase 拆分细化 |
| H5 | C-C 用户层 stub 不可行实证 — 违反 CLAUDE.md "编译器吸收复杂度" + 不 scale | ✓ Phase 0 实证(每 sibling 测试需手动 register stub implementor scope 爆炸 + N 年返工度高 — 违 §核心原则 1) | C-C 唯一可行路径 → 回 Phase 0 修 §A.1 评估 |
| H6 | bootstrap 三阶段固定点不破(D135-D152 范式延续) | Phase 2+ 留(各候选实施时验证 — `./build.sh bootstrap` Stage 2 = Stage 3) | 三阶段固定点破 → 回 Phase 2 修自然链路 |
| H7 | 不引入新关键字 / 新语法(继承 D147 §核心原则 13)— 复用既有 SS interface / class 语法机制;codegen 层修改不暴露用户层 | Phase 0 实证(继承 D147 §核心原则 1 不破 — 候选 C-A/C-B 都 codegen 层修改不暴露用户层) | 需引入新语法 → 不选(违 CLAUDE.md §Java/TS 语法优先 + §核心原则 2) |
| H8 | C-A 修复后 d151 integration_test 14 stub no-op 替换真 stringify GREEN | Phase 3+ 实测验证(C-A 锁定后 Phase 2 修复 codegen + Phase 3 d151 integration_test 真 stringify 解锁 + d152 sibling 测试不破) | 真 stringify 失败 → 部分 setter 走 binary protocol 直接 encode fallback |
| H9 | d152 sibling 测试 import sql.ss 不破(C-A 修复后 d152 blob_test 等 sibling 测试 import sql.ss 但无 Date/Time/Timestamp implementor 时,dispatch fn emit panic stub 允许 link 不破) | Phase 3+ 实测验证(`bin/ss test tests/d152_jdbc_type_class_foundation/` 7 passed 不破) | sibling 测试破 → 回 Phase 2 修 codegen panic stub emit 逻辑 |
| H10 | D135-D152 sub-D 链路 close 不破(D147 主线 6 setter / D146 cursor 7 method / D138 generated keys / D152 type class foundation / D151 setter 18 method 全 GREEN) | Phase 3+ 留(各 sub-D unit test 全 GREEN — `bin/ss test tests/d147_*/` 7 / `tests/d146_*/` / `tests/d138_*/` / `tests/d152_*/` 7 / `tests/d151_*/` 18) | 各 sub-D 测试破 → 回 Phase 2 修兼容性 |

---

## §A.3 废案

- **C-C 用户层手动 stub 全废**(违反 CLAUDE.md "编译器吸收复杂度" + 不 scale + 违 §核心原则 1 — 每 sibling 测试都需手动 register stub implementor scope 爆炸 + N 年返工度高;仅作文档备忘不作主线候选)
- **C-D interface 改 abstract class 用 vtable static dispatch 全废**(主语言重设计,违反 D025 class layout + scope 爆炸不可行 — interface 是 SS 主语言核心机制,改 abstract class 涉及 lexer/parser/checker/PIR/codegen 全链路 ~500-2000 LOC + 用户层语义改变)
- **越过用户对话授权门槛自决策 C-A/C-B 全废**(类比 D148 Phase 2 H15 / D149 Phase 2 H12 / D150 Phase 0 H3 / D151 Phase 0 范式 — Phase 0 §字段 10 (e) 自决策评估 C-A ≥ C-B > C-D > C-C 但决策行不锁定,等用户对话明确锁定后才入 Phase 1)
- **改 D025 class layout 主线 / D147 / D146 / D138 / D152 / D151 主线依赖 D 文档全废**(D025 class layout 不破 + D147/D146/D138/D152/D151 主线全 close 不破 — D153 仅修 codegen 层 interface dispatch fn emit 逻辑,不动 class layout)
- **引入新关键字 / 新语法全废**(CLAUDE.md §Java/TS 语法优先红线;codegen 层修改不暴露用户层语法)
- **annotation handler 旁路 ≥10 type class 全废**(`feedback_no_derive_workaround` 红线 — 主线能力缺口不允许 @derive / annotation handler 作为替代路径)
- **修 D147 主线 6 setter 不动 stringify pattern 而是改 driver class impl 提早全废**(D151 §F1 driver class impl 是 surface 解 — production driver class 落地后真 stringify 仍需编译器层 fallthrough 修复;§F2 是根因 §F1 是 surface;§F2 修复后 §F1 才有干净落地路径,业界对标 H8 stringify pattern 限制根因解)

---

## Phase 收关锚

### Phase 0: D 文档落档 + 候选锁定评估 fact 入档 + §字段 10 (e) 自决策评估 C-A ≥ C-B > C-D > C-C + 决策行不锁定 留用户对话授权 [✓] Done at commit `<placeholder>`(D135-D152 范式 单 commit 不能引用自己 hash 下下轮回填)(2026-05-04)

- **D153.md 文档新建** ~400 行(本 commit)— Status header + Depends on D151/D147/D152/D025/D097/D052 + Date 2026-05-04 + §核心目标 + §核心原则 13 条 + §1 Context(D151 主线 close 后 §F2 起首状态 + 累计 sub-D 链路 18 + 业界对标 LLVM/JVM/V8/Rust + D151 §A.2 H8 实证锚)+ §2 RED 锚 + §3 Orchestration Phase 0-N+ + §A.1 4 候选评估(C-A LLVM linkonce_odr / C-B call site conditional / C-C 用户层 stub / C-D interface 改 abstract class)+ §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 + §Phase 收关锚 + §Followup + §Status 时间线 Phase 0 entry
- **D151 §Followup F8 line 319 标 D153 起首** — D151.md edit 加 "**起 D153 sub-D 编译器层 interface dispatch fallthrough at commit `<placeholder>`**(2026-05-04 D151 主线 close at `b646978` 后 §F2 起首接力 — 编译器层 sub-D 第一例,业界对标 LLVM `linkonce_odr` 弱符号 / JVM `invokeinterface` itable miss / V8 hidden class transition / Rust trait dyn dispatch vtable miss 范式)" 标
- **编译器层根因实证 fact 入档**(§A.2 H1)— SS codegen `bootstrap/gen/exprs/method_call.ss` 在 interface method call 处 emit `call ptr @__iface_<I>_<m>(...)` 无条件 emit;`@__iface_<I>_<m>` dispatch fn body 在 interface 无 implementor 时不 emit → llc-18 链接失败 `use of undefined value '@__iface_<I>_<m>'`;D151 Phase 4 实测 12 interface-typed setter 真 stringify 触发该限制
- **C-A/C-B/C-C/C-D 4 候选评估 fact 入档**(§A.1 决策行 — C-A LLVM linkonce_odr 范式 / C-B call site conditional emit / C-C 用户层 stub / C-D interface 改 abstract class 4 候选评估表 + §字段 10 (e) 自决策评估 C-A ≥ C-B > C-D > C-C + 决策行不锁定 留用户对话授权门槛触发)
- **§A.2 H1-H10 加入** + **§A.3 废案 7 条**
- **VCM §1 豁免锚成立**(Phase 0 docs-only — `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D151-*.md hash 回填 + §F8 标 D153 起首 + 新建 docs/3-decisions/D153-*.md)
- **simplify 跳过 docs-only 例外**(纯文档 D151 §F8 标 + D153.md 新建)
- **d_doc_index_linter F1=0 GATE OK** + **ultrathink_linter PASS** + **D135-D152 范式延续**
- **MNK §M meta-gate 强制四问全 ✓**(深度读 D151.md §核心目标 + §核心原则 13 条 + §1 Context + §A.1 决策行 C-B-3 锁定 + §A.2 H1-H10 全 PASS H8 partial + §A.3 废案 + §Phase 收关锚 Phase 0/1/2/3/4/5 [✓] + §Status 时间线 Phase 0/1/2/3/4/5 entry + §Followup F1-F8 + 历史 D135-D152 sub-D 链路接力范式延续 + D153 起首条件验证未漏 — D151 主线 close at `b646978` 后 §F2 line 319 直接 followup 起首 + 编译器层根因实证 + C-A/C-B/C-C/C-D 4 候选 fact 入档 + 用户对话授权门槛触发 + 兑现 a-h 总览每条 file:line 锚)
- **D153 Phase 0 commit hash 留 D153 Phase 1 启动轮回填**(D135-D152 范式 — 单 commit 不能引用自己 hash 下下轮回填)

### Phase 1+ Planned: Phase 0 hash 回填 + 用户对话锁定候选 + 候选范畴细化 + 路径分支

- **Phase 0 hash 回填**(D135-D152 范式延续 — 单 commit 不能引用自己 hash 下下轮回填)
- **用户对话授权门槛触发** — Phase 0 4 候选 fact 入档 + §字段 10 (e) 自决策评估倾向 C-A,Phase 1 用户对话明确锁定 C-A / C-B / C-C / C-D
- **候选范畴细化** — C-A 锁定后 Phase 2+ 修 `bootstrap/gen/exprs/method_call.ss` dispatch fn body emit panic stub(LLVM `linkonce_odr` 弱符号范式);C-B 锁定后 Phase 2+ 修 codegen call site conditional emit;C-C 锁定后文档(不推荐);C-D 锁定后不可行废
- **路径分支** — Phase 2+ 起首接力具体编译器修复实施

### Phase 2+ Planned(候选锁定后展开): 编译器 codegen 修复实施 + bootstrap 三阶段固定点 + integration_test 真 stringify 解锁 + d152 sibling 测试不破

- **C-A 锁定后落点**(倾向):
  - 修 `bootstrap/gen/exprs/method_call.ss`(或 codegen interface dispatch fn emit 入口)使 `@__iface_<I>_<m>` dispatch fn body 在 interface 无 implementor 时 emit panic abort stub:
    ```llvm
    define ptr @__iface_<I>_<m>(ptr %self, ...) {
      call void @ss_panic_msg(ptr @.iface_dispatch_no_impl_msg)
      unreachable
    }
    ```
  - bootstrap 三阶段固定点验证 PASS(`./build.sh bootstrap` Stage 2 = Stage 3)
  - d151 integration_test 14 stub no-op 替换真 stringify GREEN(`bin/ss test tests/d151_resultset_update_type_extension/` 18 真实现 18 passed)
  - d152 sibling 测试不破(`bin/ss test tests/d152_jdbc_type_class_foundation/` 7 passed)
  - d147/d146/d138 unit test 不破

---

## Followup

> **D153 Phase 0 落档后 — 候选锁定后展开**(2026-05-04):候选锁定后(Phase 1),后续 sub-D 起首队列由 C-A LLVM linkonce_odr / C-B call site conditional / C-C 用户层(不推荐)/ C-D interface 改 abstract class(不可行)决定;本 §Followup 表暂留 SQL 主线 followup 队列(D147 §F2/F3 / D146 §F2/F3 / D138 §F1 / D107 / D151 §F1 driver class impl 等)候选锁定后再扩 D153 各阶段 followup。

| # | 锚 | 描述 | 启动条件 |
|---|---|---|---|
| F1 | D147 §F2 SELECT FOR UPDATE 行锁 + RR isolation level + InnoDB lock wait timeout | SQL standard `SELECT ... FOR UPDATE` 行锁与 cursor 正交独立 sub-D | D153 主线 close 后 |
| F2 | D147 §F3 multi-PK / 多表 join updatable cursor | 本 D 仅最小子集(单表 SELECT 单 PK);multi-PK 复合主键 + 多表 join 留独立 sub-D | D153 主线 close 后 |
| F3 | D146 §F2 holdability HOLD_CURSORS_OVER_COMMIT / CLOSE_CURSORS_AT_COMMIT | cursor + transaction commit 行为 | D153 主线 close 后 |
| F4 | D146 §F3 ResultSetMetaData 完整列元数据 | getColumnTypeName / isAutoIncrement / isPrimaryKey 等 | D153 主线 close 后 |
| F5 | D138 §F1 KeyHolder.getKey 类型扩展 + HikariCP | 自动生成主键类型 + 连接池 | D153 主线 close 后 |
| F6 | D107 PostgreSQL driver 起首 | 跨数据库扩展新方向(D107 未首次落档) | D153 主线 close 后 |
| F7 | D151 §F1 driver class impl(MysqlTimestamp/MysqlBlob/MysqlClob 等)| Phase 4 实证 H8 假设破裂 — driver class 落地后按 H8 pattern 真 stringify dispatch 可放心放回(本 D §F2 修复后干净落地路径)| D153 主线 close 后(D153 §F2 修复后 §F1 真 stringify 才有干净落地路径)|

---

## Status 时间线

- 2026-05-04 Phase 0 D 文档落档 + 候选锁定评估 fact 入档 + §字段 10 (e) 自决策评估 C-A ≥ C-B > C-D > C-C + 决策行不锁定 留用户对话授权 docs only(commit `<placeholder>`)— **D153 Phase 0 兑现 a-h 八项 fact 全 GREEN + D151 主线 close at `b646978` 后 §F2 line 319 起首接力 + 编译器层 sub-D 第一例 + D135-D152 sub-D 链路 close 累计 18 sub-D + D151 §A.2 H8 实证锚不破 + docs only VCM §1 豁免锚成立**:(a) **D153.md 文档新建** ~400 行 docs-only(本 commit)— Status header + Depends on D151/D147/D152/D025/D097/D052 + Date 2026-05-04 + §核心目标 + §核心原则 13 条 + §1 Context + §2 RED 锚 + §3 Orchestration Phase 0-N+ + §A.1 4 候选 + C-A/C-B/C-C/C-D + §A.1.1 G1/G2 落点 + §A.2 H1-H10 隐藏假设 + §A.3 废案 7 条 + §Phase 收关锚 + §Followup + §Status 时间线 Phase 0 entry;(b) **D151 §Followup F8 line 319 标 D153 起首** — D151.md edit 加 "**起 D153 sub-D 编译器层 interface dispatch fallthrough at commit `<placeholder>`**(2026-05-04 D151 主线 close at `b646978` 后 §F2 起首接力 — 编译器层 sub-D 第一例,业界对标 LLVM `linkonce_odr` 弱符号 / JVM `invokeinterface` itable miss / V8 hidden class transition / Rust trait dyn dispatch vtable miss 范式)" 标;(c) **编译器层根因实证 fact 入档**(§A.2 H1)— SS codegen `bootstrap/gen/exprs/method_call.ss` 在 interface method call 处 emit `call ptr @__iface_<I>_<m>(...)` 无条件 emit;`@__iface_<I>_<m>` dispatch fn body 在 interface 无 implementor 时不 emit → llc-18 链接失败 `use of undefined value '@__iface_<I>_<m>'`;D151 Phase 4 实测 12 interface-typed setter 真 stringify 触发该限制 → 降级 stub no-op fallback;(d) **C-A/C-B/C-C/C-D 4 候选评估 fact 入档**(§A.1 决策行 — C-A LLVM linkonce_odr 范式 + C-B call site conditional emit + C-C 用户层 stub 已废 + C-D interface 改 abstract class 已废 + §字段 10 (e) 自决策评估 C-A ≥ C-B > C-D > C-C + 决策行不锁定 留用户对话授权门槛触发);(e) **§A.2 H1-H10 加入** + **§A.3 废案 7 条**;(f) **VCM §1 豁免锚成立**(Phase 0 docs-only — `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 + 仅改 docs/3-decisions/D151-*.md hash 回填 + §F8 标 D153 起首 + 新建 docs/3-decisions/D153-*.md);simplify 跳过 docs-only 例外;d_doc_index_linter F1=0 GATE OK 12 referenced Ds all live + ultrathink_linter PASS;(g) **MNK §M meta-gate 强制四问全 ✓**(深度读 D151.md §核心目标 + §核心原则 13 条 + §1 Context + §A.1 决策行 C-B-3 锁定 + §A.2 H1-H10 全 PASS H8 partial + §A.3 废案 + §Phase 收关锚 Phase 0/1/2/3/4/5 [✓] + §Status 时间线 Phase 0/1/2/3/4/5 entry + §Followup F1-F8 + 历史 D135-D152 sub-D 链路接力范式延续 + D153 起首条件验证未漏);(h) **D153 Phase 0 commit hash 留 D153 Phase 1 启动轮回填**(D135-D152 范式 — 单 commit 不能引用自己 hash 下下轮回填);**新发现**:(i) **D153 = D151 主线 close 后第一例 SQL 主线 follow-up sub-D 起首**(D147/D152/D151 Phase 2 wrapper/D151 主线 4 个 close 节点后,D153 起首是后续 sub-D 链路接力第一例,延续 D135-D152 范式 — sub-D 链路接力);(ii) **D153 §F2 vs §F1 优先级 — §F2 ≥ §F1 根因优先**(§F2 SS 编译器 interface dispatch fallthrough 是根因解决 — codegen `__iface_<I>_<m>` dispatch fn 在 interface 无 implementor 时 emit panic stub 允许 link;§F1 driver class impl 是 surface 解决 — production driver impl class MysqlTimestamp/MysqlBlob 等落地后 H8 stringify pattern 真 stringify 可放心放回;§F2 修复后 §F1 才有干净落地路径,业界对标 LLVM `linkonce_odr` 弱符号 / JVM `invokeinterface` itable miss / V8 hidden class transition / Rust trait dyn dispatch vtable miss 范式);(iii) **业界对标 §F2 编译器 fallthrough 范式**(LLVM `linkonce_odr` 弱符号 — 多翻译单元各自 emit dispatch fn 链接器选一份;JVM `invokeinterface` itable miss → throw `AbstractMethodError` 运行时 trap;V8 hidden class miss → polymorphic IC slow path;Rust trait `dyn Trait` vtable 必须每 impl 完整定义);SS 当前是各 import 单元独立 emit `__iface_<I>_<m>` dispatch fn,无 implementor 时不 emit 但 call site 仍 emit → llc-18 undefined ref;C-A 范式 = LLVM `linkonce_odr` 弱符号 + dispatch fn body emit panic stub 允许 link 业界对标 LLVM 范式;(iv) **D151 §F2 line 319 锚 + D151 §A.2 H8 实证锚**(D153 §1 Context 引用 D151.md §A.2 H8 实证 + §F8 line 319 锚:H8 假设 "MysqlBinaryResultSet via writeCol stringify pattern 可直翻 ≥22 setter — `writeCol(col, "" + val)` / `writeCol(col, val.toString())`" 部分破裂,根因 = SS 编译器 codegen `__iface_<I>_<m>` dispatch fn 强制每 import 单元有 implementor 限制);(v) **C-B-3 锁定后 D153 起首 docs-only Phase 0 直接 Execute 不 Plan**(memory `feedback_execute_when_doc_locked.md` 同形 — 决策归档后 next_prompt 直接 Execute 不 Plan,D151 Phase 1 锁 C-B-3 + Phase 5 close 收关后 D153 §F2 sub-D 起首落档范畴明确无新 sub-decision 需用户授权,类比 D147 Phase 5 close → D148 Phase 0 起首 / D152 Phase 6 close → D151 Phase 3 起首接力 范式延续);(vi) **D153 Phase 0 commit hash 留 D153 Phase 1 启动轮回填**(D135-D152 范式 — D153 Phase 0 close 后入 Phase 1 = D153 Phase 0 hash 回填 + 用户对话授权门槛触发 + 候选锁定 + 候选范畴细化 + 路径分支 — 类比 D151 Phase 0 → Phase 1 范式延续);(vii) **D153 Phase 0 完成后 next_prompt 转向 D153 Phase 1 启动轮**(.claude/next_prompt.md 写 D153 Phase 1 启动 = D153 Phase 0 commit hash 回填 + 用户对话授权门槛触发 + 候选锁定 + ultrathink GATE OK 3/3 PASS);(viii) **D135-D152 sub-D 链路 close 范式延续 + D153 §F2 起首接力 — 第一例「编译器层 sub-D」起首**(D135-D152 全是 SQL 主线 sub-D — D147 updatable cursor + 6 setter / D146 cursor + 7 method / D138 generated keys / D152 JDBC type class foundation / D151 ResultSet update type extension;D153 §F2 是首个跳出 SQL 主线进入「SS 编译器 codegen 层」的 sub-D,延续 D097 reflection 根因 metrics + D025 class layout interface vtable 范式 — 编译器层 sub-D 起首是 D135-D152 SQL 主线 sub-D 链路 close 后接力第一例)
