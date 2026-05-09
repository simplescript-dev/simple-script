# D163: SS 编译器 extends + iface impl + iface-typed own field write codegen bug 修法

**Status:** [x] Phase 0 D 文档落档 at commit `eb7bd05` + [x] Phase 1 minimal repro 隔离 spike + 3 case RED-as-spike + LLVM IR 真根因 = MEMBER_ACCESS 漏 ifaceMethodsCG.has(推翻 §A.2 H1 GEP offset 错位假设)at commit `8933f0a` + [x] Phase 2 bootstrap/gen codegen 修法 + 三阶段固定点 stage2==stage3 PASS + Phase 1 spike 3 case 全 GREEN at commit `<phase2-hash>` + [ ] Phase 3 D160 §Phase 4 wire 真值反射重启验证 + 在线 docker 8 case 全 GREEN at commit `<phase3-hash>` + [ ] Phase 4 D163 主线 close + D160 §F9 重启锚回填 at commit `<phase4-hash>` — D160 §F9 起首脱胎,D162 §F7 vtable + non-0-arg overload child class bug 修法系列同源 corner case。修 SS 编译器 `class Child extends Parent : Iface { box: Box }` 形态下子类 own method 内 `this.box = newBox` 对 interface-typed own field write 写不进 own field 的 codegen bug — 不接受次优 / workaround / 节省路径(用户对话锁)。

## 起首脱胎
- D160 §F9(`docs/3-decisions/D160-callable-statement-out-inout.md:153`)— D160 Phase 3 docker e2e 在线验证发现 `this.outRow = rs` 写不进子类 own field
- D162 §F7 vtable + non-0-arg overload child class bug 修法系列同源 corner case(D162 §Phase 4 修法仅覆盖 vtable indirect dispatch 路径,未覆盖 own field write GEP offset)
- 用户对话锁 "docker 起来在线验证 8 case wire 真值"(2026-05-09)实测发现根因
- Depends on:无新前置依赖(SS 编译器内 codegen 修法 + D160 wire drain 实现代码已就位等修法)

## 核心目标 (Goal)

落地后:
1. `bootstrap/gen/...` 修 SS 编译器 codegen 在 `class Child extends Parent : Iface { ifaceTypedField: Iface }` 形态下,子类 own method 内 `this.ifaceTypedField = v` 真正写入 own field slot(GEP offset 与 RC retain 路径正确)
2. 子类 own method 内对 interface-typed own field 写后立即读 reflects 新值(`this.ifaceTypedField.method()` 走新值的 vtable dispatch)
3. `./build.sh bootstrap` 三阶段固定点 stage2==stage3 PASS
4. minimum repro `class Child extends Parent : Iface { box: Box; function go() { this.box = newBox; return this.box.fetch() }}` 实测返新 box 值(99)而非旧 stub 值(0)
5. **D160 §Phase 4 wire 真值反射重启**:在线 `docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait` 后 `bin/ss test tests/d160_callable_statement/` 8 case 全 GREEN(getInt(2)=20 / getInt(1)=15 / 多 OUT / 三态 mode / getString / getDouble / wasNull)
6. baseline 全继承 + reflection_health_linter no regression + d_doc_index_linter F1 = 0 + next_prompt_ultrathink_linter PASS

**RED**(本 D 文档落档前实测):
- minimal repro `/tmp/d160_min_repro.ss` 实测输出 `local newBox.fetch=99 / after assign this.box.fetch=0 / go() = 0` — 写不进 own field
- D160 docker 在线 e2e `bin/ss test tests/d160_callable_statement/` 8 case 全 fail(segfault on test runner 路径 / direct binary cs.getInt(2)=0)
- `tests/d160_callable_statement/integration_test.ss` 离线 probe-skip exit=0 但在线 wire 真值反射假阳

## 核心原则 (Principles)

1. **Root Cause 优先 + 不接 workaround / 节省路径**:用户对话锁 — 修 SS 编译器 codegen GEP offset / RC retain 路径,**不**改 D160 wire drain 实现绕过(如不改用具体类型 MysqlResultSet 替接口类型 ResultSet 作 outRow 类型;不在 driver 用 lazy / closure 等 workaround)
2. **D162 §F7 修法系列延续**:D162 §Phase 4 落地 `bootstrap/gen/class/class.ss classMethodHasPlainFn` Map / `gen_registry.ss registerClassMethodRetType` mSig 逻辑 / `gen_type_ops.ss buildVtableForClass isOverloaded + classMethodHasPlainFn.has=0 skip slot` / `methods/gen_methods.ss vtable indirect dispatch raw ptr GEP` 修法系列已覆盖 vtable dispatch + non-0-arg overload child class bug;本 D 修法补 own field write GEP offset / RC retain 路径补全
3. **业界对标**:Java / TypeScript `class C extends Parent implements I { f: I; doIt() { this.f = newF; this.f.method() }}` 标准模式必 work — SS 必同等支持
4. **bootstrap 三阶段固定点必走**:任何 bootstrap/gen 修改必走 ./build.sh bootstrap 三阶段 stage2==stage3 bit-identical 验证(D162 §Phase 2 范式延续)
5. **D135-D162 主线范式延续**:Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环 + §A.2 隐藏假设 + §A.3 废案 + §Followup
6. **D160 §Phase 4 wire 真值反射重启**:本 D 主线 close 后 D160 §Phase 4 启动,8 case docker e2e 全 GREEN 是真值反射 H4 实证锚收关条件 — 跨 D 起首回填范式延续(D163 close → D160 Phase 4 重启)
7. **N 年返工度**:不修 → 后续每条 sub-D 用 `extends Parent : Iface { ifaceField: Iface }` 形态(常见 ORM driver class、wrapper class、adapter class)全部 wire write 失败 → 必修

## A.1 主候选评估(§MNK §M §字段 10)

| 候选 | 层次 | 含 | 不含 | 决策 |
|------|------|-----|------|------|
| **C1** | workaround:driver 改用 lazy 闭包 / 全局 Map 模拟 own field state | + 暂时绕过 SS 编译器 bug,D160 wire drain 改用 closure 捕获或全局 Map<conn_id,outRow> 模拟 own field 状态 | 编译器 bug 不修,后续每条 sub-D 用 extends + iface impl + iface 类型 own field 形态全断链 | **不选** — 用户对话锁不接 workaround;违反 ROOT CAUSE 第一法则 |
| **C2** | **编译器层修法** | + 修 SS 编译器 codegen GEP offset / RC retain 路径 + 子类 own method 内 interface-typed own field write 真正写入 + bootstrap 三阶段固定点 + minimum repro spike GREEN + D160 §Phase 4 wire 真值反射重启 8 case docker e2e 全 GREEN | 高级类型(generic over 接口 type / 多重 interface 继承 own field)留 §F1 / 多 driver compatibility 留 §F2 | **选** — 根因解决:N 年返工度极高 + 业界对标 Java / TS 标准 + 与 D162 §F7 修法系列同源延续 + 不破依赖链 |
| **C3** | 架构层 refactor:SS 类系统重写 + 完整 interface field 体系审查 | + 全面审视 SS class field GEP / vtable / RC retain 体系 + 多 corner case(嵌套继承 / generic class / interface multi-impl)全覆盖 | scope 远超 D163 单 sub-D — 跨 D162 / D161 / D018 等所有 vtable / class 字段 sub-D 联动 | **不选** — scope 远超 + N 年路径,本 D 仅修当前 corner case 不动整体类系统 |

**决策行**:**选 C2 编译器层修法**(用户对话锁 — 不接次优 / workaround / 节省)— 因 (a) Root Cause 第一法则下编译器 bug 必修;(b) 业界对标 Java / TypeScript `class C extends Parent implements I` 含 interface-typed own field write 是标准模式,SS 必支持;(c) D162 §F7 修法系列延续,covered scope 自然延伸;(d) D160 §Phase 4 wire 真值反射重启依赖此修;(e) N 年返工度高 — 后续每条 sub-D 用 `extends Parent : Iface { f: Iface }` 形态全断链。

## A.2 隐藏假设挑战

| H | 假设 | 挑战 | 实证锚 |
|---|------|------|--------|
| H1 | SS 编译器子类 own field GEP offset 在 extends + iface impl 形态下计算正确 | minimal repro 实测发现 `class Child extends Parent : Iface { box: Box }` 子类 own method 内 `this.box = newBox` 写不进 — `this.box` 读出 0 而非 99。可能 GEP offset 错位,把写入 routed 到父类字段位或 reserved slot | Phase 1 spike — 编译产物 LLVM IR 直接 inspect `this.box = newBox` 这行的 GEP 指令 + 对比预期 offset(parent fields count + own field idx);Phase 2 修法后 fixed point 验证 |
| H2 | RC retain/release 路径在 interface-typed own field write 时正确处理(retain newBox + release oldBox)| field write `this.box = newBox` 必走 retain newBox + release oldBox 双 RC 操作。bug 可能在 newBox 立即 release(忘 retain)或 oldBox 不 release(memory leak)— 表现为后续 read 拿到 dangling pointer 或 stub default | Phase 1 spike — 加 println 在 retain/release 入口 trace 计数;Phase 2 修法 + reflection_health_linter no regression 守护;Phase 3 D160 docker e2e 验证 |
| H3 | vtable dispatch 在 interface-typed field 上仍走 TypeInfo.deep_clone_fn slot(D155 §Phase 3 修过)| D155 §Phase 3 注释明记 "Interface-typed field is safe now that codegen routes deep_clone through the obj's TypeInfo.deep_clone_fn slot (D018 vtable)" — 这是 deep_clone 路径。本 D bug 是 field WRITE 路径,可能与 deep_clone 不同 codegen 路径 | Phase 1 spike — verify deep_clone 仍 work + isolate field write 路径单独;Phase 2 修法不破 deep_clone 路径 |
| H4 | bootstrap 三阶段固定点验证 stage2==stage3 bit-identical 在编译器 codegen 修法后 PASS | bootstrap 编译器自身用 SS 编写,bug 在 codegen 修法可能影响 self-bootstrap — 需 stage1 用 stage0 编译,stage2 用 stage1 编译,stage3 用 stage2 编译,stage2==stage3 bit-identical | Phase 2 修法后 ./build.sh bootstrap 三阶段固定点 PASS;Phase 3 后 bootstrap 仍稳 |
| H5 | D160 §Phase 4 wire 真值反射重启 — 修编译器后,D160 wire drain 实现(commit `647f5cc`)代码不动即可 GREEN | D160 wire drain 落地代码已就位但行为假阳。修编译器 root cause 后,代码层 `this.outRow = rs` 写正确,后续 typed getter `this.outRow.getString(...)` 真值反射 GREEN — 不需要改 D160 driver 代码 | Phase 3 docker e2e 重跑 `bin/ss test tests/d160_callable_statement/` 8 case 全 GREEN(在线状态);Phase 4 D160 §Phase 4 锚回填 |

## A.3 废案

- **C1 driver 改 workaround**(用户对话锁不接 workaround / 节省路径;违反 ROOT CAUSE 第一法则)
- **C3 架构层 refactor**(scope 远超 D163 单 sub-D)
- **改 D160 outRow 类型从 ResultSet 接口改为 MysqlResultSet 具体类型**(workaround;违反 interface 类型多态范式 + 破 deep_clone vtable D155 §Phase 3 路径)
- **加 outRow setter helper method 绕过直 field write**(`function setOutRow(rs: ResultSet) { this.outRow = rs }` — 还是同样 codegen 路径,bug 复现)
- **改 D160 outRow 字段名 / 移到父类 MysqlPreparedStatement**(workaround + 跨 D 范畴破坏 + 仍需 codegen 修法 root cause)
- **临时跳过 D160 §F9 等远期处理**(用户对话锁 docker 在线验证 wire 真值是核心目标,不接妥协)
- **强制 SS 标记 own field write 为 unsafe / volatile**(SS 类型系统不支持 + 反 user-friendly 范式)

## Phase commit hash 总览

| Phase | 内容 | Commit |
|-------|------|--------|
| 0 | D 文档落档(§核心目标 + §核心原则 + §A.1-A.3 + §Phase 收关锚 Phase 0-4 + §Followup F1-F? + §Status 时间线)+ D160 §Phase 3 hash `647f5cc` 跨 D 起首回填 | `eb7bd05` |
| 1 | minimum repro `tests/d163_class_extends_iface_typed_field_write/phase1_repro_spike_test.ss` 3 case RED-as-spike + bootstrap LLVM IR inspect 推翻 §A.2 H1 GEP offset 错位假设 → **真根因 = `bootstrap/gen/gen_types.ss:248-249` resolveObjClass MEMBER_ACCESS 分支只检 classFields.has(fType) 漏检 ifaceMethodsCG.has(fType)** → MEMBER_ACCESS 节点 `this.box`(field type 是 interface)resolveObjClass 返 "" → gen_methods.ss:497 interface dispatch 入口因 objClass="" 不进 → fall through 至 line 565 fallback emit `; TODO: method call .${method}` + return "0" 替代 method call IR | `8933f0a` |
| 2 | **PRIMARY 修法 = `bootstrap/gen/gen_types.ss:249` 后 +1 行 `if (fType != "" && ifaceMethodsCG.has(fType) == 1) { return fType }`**(复用同文件 line 167 / 200-201 / 211-212 / 224-225 范式)+ ./build.sh bootstrap 三阶段固定点 stage2==stage3 bit-identical PASS + reflection_health_linter no regression(F1 gen_types.ss=888<bm=1050)+ Phase 1 spike 3 case 全 GREEN(Case 1 r=99 / Case 2 r=30 / Case 3 r=77)+ LLVM IR `grep -c "TODO: method call"` = 0(从 4 → 0)+ `__iface_BoxD163_fetch` 调用 5 次(Case 1+2+3 各 ≥1 次 interface dispatch + iface helper 内部 1 次)+ bin/ss test tests/ 净 +1 PASS(305/16/321) | `<phase2-hash>` |
| 3 | D160 §Phase 4 wire 真值反射重启 + 在线 docker `bin/ss test tests/d160_callable_statement/` 8 case 全 GREEN(getInt 真值反射 + 多 OUT + 三态 mode + multi-type + wasNull)+ baseline 全 PASS | `<phase3-hash>` |
| 4 | D163 主线 close + D160 §F9 row 末尾上下文更新 + D160 §Phase 4 §收关锚 [x] Done + D160 主线 close at commit `<phase4-hash>` 重启 + Phase 0-3 hash 回填 | `<phase4-hash>` |

## Phase 收关锚

### Phase 0: D 文档落档 [x] Done at commit `eb7bd05`

- 落地 `docs/3-decisions/D163-class-extends-iface-typed-field-write.md`(本文件)— §核心目标 + §核心原则 + §A.1 候选评估 + §A.2 隐藏假设 H1-H5 + §A.3 废案 + §Phase 收关锚 Phase 0-4 + §Followup + §Status 时间线
- 落地 `.claude/next_prompt.md`(下轮 D163 Phase 1 起首 — minimum repro spike 移植 + ≥3 case GREEN + LLVM IR inspect 确认 GEP offset 错位)
- 跨 D 起首回填 D160 §Phase 3 hash `647f5cc` 至 D163.md ≥3 处实际语义位(Status header / §Phase commit hash 总览段表 / Status 时间线 起首脱胎 entry)
- bootstrap/ + lib/ + tools/ + tests/ diff = 0(本 Phase 纯 docs/ + .claude/next_prompt.md)
- baseline:d_doc_index_linter F1 = 0 PASS(D147/D154/D155/D156/D157/D160/D161/D162/D163 全实存)+ next_prompt_ultrathink_linter PASS + 14 reflection 指标全继承 D162 §Phase 3 baseline + bin/ss test tests/ 全继承 304/16/320

### Phase 1: minimum repro 隔离 spike + 3 case RED-as-spike + LLVM IR 真根因 [x] Done at commit `8933f0a`

- 落地 `tests/d163_class_extends_iface_typed_field_write/phase1_repro_spike_test.ss` 3 case RED-as-spike(Case 1 单 iface-typed own field write/read / Case 2 多 iface field write box1+box2 / Case 3 nested 三层 chain Grandchild→Child→Parent — `ChildD163 extends ParentD163 : TriggerD163 { box: BoxD163 }` 同形)
- LLVM IR inspect:`bin/ss build phase1_repro_spike_test.ss --emit-ir` 显示 WRITE 路径 GEP offset + RC retain/release 全正确(`%12 = getelementptr %Child, ptr %11, i32 0, i32 4` + `call void @ss_retain` + `store ptr` + `call void @ss_release`),READ + method call 路径 GEP offset 也正确,但 method dispatch IR 缺失 → emit `; TODO: method call .fetch` + `%20 = call ptr @ss_int_to_string(i32 0)` 替代 fetch() 返值
- **真根因 file:line**(对比 local var newBox.fetch() 走 `__iface_Box_fetch` GREEN 通路):
  1. `bootstrap/gen/gen_types.ss:248-249` resolveObjClass MEMBER_ACCESS 分支只检 `classFields.has(fType) == 1` 漏检 `ifaceMethodsCG.has(fType) == 1` → MEMBER_ACCESS 节点 `this.box`(field type Box=interface)→ resolveObjClass 返 ""
  2. `bootstrap/gen/methods/gen_methods.ss:497` interface dispatch 入口 `objClass != "" && ifaceMethodsCG.has(objClass) == 1` 因 objClass="" 第一项失败不进
  3. `bootstrap/gen/methods/gen_methods.ss:565` fallback emit `; TODO: method call .${method}` + `return "0"` 替代 method call IR(read 路径全断链)
- **Phase 2 修法 target**(LOC 极小 +1 行,与 D162 §F7 修法系列同源 corner case):`bootstrap/gen/gen_types.ss:249` 加一行 `if (fType != "" && ifaceMethodsCG.has(fType) == 1) { return fType }`(复用范式见同文件 line 167 IDENT / 200-201 METHOD_CALL / 211-212 INDEX_ACCESS / 224-225 TERNARY — 全部已用 `ifaceMethodsCG.has` 双检 ifaceType return field type,仅 MEMBER_ACCESS 分支漏 — 一处补齐对称)
- bootstrap/ 不动(本 Phase 仅 tests/ + 诊断)+ 跨 D 起首回填 D163 §Phase 0 hash `eb7bd05` 至 D163.md ≥4 处实际语义位

### Phase 2: bootstrap/gen codegen 修法 + 三阶段固定点 PASS + Phase 1 spike 全 GREEN [x] Done at commit `<phase2-hash>`

- **PRIMARY 修法**:`bootstrap/gen/gen_types.ss:249` 后 +1 行 `if (fType != "" && ifaceMethodsCG.has(fType) == 1) { return fType }`(复用 line 167 / 200-201 / 211-212 / 224-225 范式 — 全部 ifaceMethodsCG.has 双检 ifaceType,仅 MEMBER_ACCESS 漏,一处补齐对称)
- `./build.sh bootstrap` 三阶段固定点 stage2==stage3 bit-identical PASS — `Stage 2 = Stage 3 — Updated bin/ss`
- reflection_health_linter GATE PASS — no regressions(M1-M7+N1-N5 全继承 baseline + F1 bootstrap/gen/gen_types.ss cur=888 bv=885 bm=1050 → DRIFT 软警告,远低 budget_max,无 BLOCKED)
- Phase 1 spike 重跑 3 case 全 GREEN — `bin/ss test tests/d163_class_extends_iface_typed_field_write/` 1 passed / 0 failed / 1 total(单 file 内 3 个 test() 全 GREEN:Case 1 r=99 / Case 2 r=30 / Case 3 r=77)
- LLVM IR 验证:`bin/ss build tests/d163_class_extends_iface_typed_field_write/phase1_repro_spike_test.ss --emit-ir -o /tmp/d163_spike` 后 `grep -c "TODO: method call" /tmp/d163_spike.ll` = 0(从 4 → 0)+ `__iface_BoxD163_fetch` 调用 5 次(Case 1 一处 line 5699 / Case 2 两处 line 5893+5898 / Case 3 一处 line 6315 + iface helper 内部 1 次)
- bin/ss test tests/ 净 +1 PASS:Phase 1 RED 304/17/321 → Phase 2 GREEN 305/16/321
- d_doc_index_linter F1=0 PASS(D147/D154/D155/D156/D157/D160/D161/D162/D163 全实存)
- next_prompt_ultrathink_linter PASS(下轮 D163 §Phase 3 起首含 ultrathink)
- 跨 D 起首回填 D163 §Phase 1 hash `8933f0a` 至 D163.md ≥4 处实际语义位(Status header / §Phase commit hash 总览段表 Phase 1 行 / §Phase 1 §收关锚 / Status 时间线 Phase 1 entry)

### Phase 3: D160 §Phase 4 wire 真值反射重启 + docker 8 case 全 GREEN [ ] Pending at commit `<phase3-hash>`

- 在线 `docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait` 起 MySQL 8.0
- `bin/ss test tests/d160_callable_statement/integration_test.ss` 8 case 全 GREEN(Case 1 H1 + Case 2 OUT INTEGER 真值=20 H4 + Case 3 INOUT 真值=15 H4 + Case 4 multi OUT H4 + Case 5 三态 mode H3 + Case 6 getString OUT H4 + Case 7 getDouble OUT H4 + Case 8 wasNull SQL NULL)
- D160 §Phase 4 §收关锚 [ ] Pending → [x] Done at commit `<phase3-hash>`(D160.md 跨 D 起首回填本 D Phase 3 hash 至 D160.md ≥3 处)
- baseline 全 PASS(304/16/320 + 16 failed 减 1 d160 离线 fail → 在线 GREEN → 305/15/320 或更多 PASS)

### Phase 4: D163 主线 close + D160 §F9 重启锚回填 [ ] Pending at commit `<phase4-hash>`

- D163 主线 close 锚:Status header `[x] Phase 0-4 + [x] D163 主线 close at commit \`<phase4-hash>\``
- D160 §Followup F9 row 末尾上下文更新 `commit \`<phase4-hash>\` D163 主线 close → D160 §Phase 4 wire 真值反射重启 GREEN`
- D160 §Phase 4 §收关锚 / Status 时间线 D163 close + D160 主线 close entry
- 跨 D 起首回填范式延续:本 D 主线 close 后 Phase 4 hash 留 D160 §Phase 4 close commit 起首跨 D 回填(D162 §Phase 4 close → D160 §Phase 3 / D163 close → D160 §Phase 4 同形)

## Followup

| F | 内容 | 范围 |
|---|------|------|
| F1 | generic-over-interface own field write(`class C<T extends Iface> { f: T; ... this.f = newF }`)| 泛型 + iface 双向类型推断 + own field write — 与 D141-D145 contextual typing sub-D 联动,留独立 sub-D 远期 |
| F2 | 多 driver compatibility(SS 编译器修法跨 stage 影响 stage0 seed 编译)| stage0 seed 已编译 binary,Phase 2 修法 affecting stage1+ codegen,stage0 不动 — 但若 stage1 build 后 stage0 重跑需重 seed,留 §F 远期 |
| F3 | nested 多重 interface impl(`class C extends Parent : I1, I2 { f1: I1; f2: I2 }`)own field write | 多 interface 实现 + 多 iface-typed own field — 是否本 Phase 2 修法自动覆盖待 Phase 1 spike Case 3 验证;若不覆盖留独立 sub-D |
| F4 | SS 编译器 own field write 完整 codegen 体系审查(D018 vtable + D155 deep_clone + D162 vtable + non-0-arg overload + 本 D field write)| 跨 D 通用 codegen 主题 — 本 D 仅修当前 corner case,完整体系审查留独立 sub-D 远期 |

## Status 时间线

- 2026-05-09 **D163 起首脱胎 + Phase 0 D 文档落档**(commit `eb7bd05`)— **新建 docs/3-decisions/D163-class-extends-iface-typed-field-write.md**(≥150 行 — §核心目标 + §核心原则 + §A.1 候选评估 + §A.2 隐藏假设 H1-H5 + §A.3 废案 + §Phase 收关锚 Phase 0-4 + §Followup F1-F4 + §Status 时间线)+ **跨 D 起首回填 D160 §Phase 3 hash `647f5cc` 至 D163.md ≥3 处实际语义位**(Status header / §Phase commit hash 总览段表 Phase 0 行 / Status 时间线 起首脱胎 entry)— D160 §F9 起首脱胎,根因优先(用户对话锁 docker 在线验证 8 case wire 真值实测发现 SS 编译器 codegen bug);**RED 实测**:`/tmp/d160_min_repro.ss` minimal repro 实测输出 `local newBox.fetch=99 / after assign this.box.fetch=0 / go() = 0` — 子类 own method 内 `this.box = newBox` 写不进 own field;D160 docker 在线 8 case 全 fail(getInt(2)=0 而非 20)+ 离线 probe-skip exit=0 范式覆盖了真问题;**GREEN**:D163.md 落档 + .claude/next_prompt.md 含 ultrathink + D160 §F9 row 加 + D160 §Phase 3 §收关锚 [/] Hold + D160 主线 close hold;**baseline**:bootstrap/ + lib/ + tools/ + tests/ diff = 0(本 Phase 纯 docs/ + .claude/next_prompt.md)+ d_doc_index_linter F1 = 0 PASS(15+1 referenced Ds all live + D147/D154/D155/D156/D157/D160/D161/D162/D163 全实存)+ next_prompt_ultrathink_linter PASS(下轮 D163 §Phase 1 起首含 ultrathink)+ 14 reflection 指标全继承 D162 §Phase 3 baseline(本 Phase 不动 bootstrap/);**simplify 跳过**(纯文档 hold turn,§After Done §1 例外);**§N §6 file:line 锚**:docs/3-decisions/D163-class-extends-iface-typed-field-write.md(本 D 落档)+ docs/3-decisions/D160-callable-statement-out-inout.md Status header [/] Phase 3 hold + [ ] D160 主线 close hold + §Phase 3 §收关锚 [/] Hold + §Phase 4 §收关锚 [ ] Pending + §Followup F9 row + Status 时间线 D160 hold + D163 起首脱胎 entry + .claude/next_prompt.md 含 ultrathink + /tmp/d160_min_repro.ss minimal repro 文件 + lib/com/mysql/prepared.ss MysqlCallableStatement wire drain 实现代码原样保留(等 D163 修编译器后 work);**等下轮 D163 §Phase 1 — minimum repro spike 移植 + ≥3 case GREEN + bootstrap LLVM IR inspect 确认 GEP offset 错位 + 对比 D162 §F7 修法系列**

- 2026-05-09 **D163 §Phase 1 minimum repro 隔离 spike + 3 case RED-as-spike + LLVM IR 真根因 = MEMBER_ACCESS 漏 ifaceMethodsCG.has**(commit `8933f0a`)— **落地 `tests/d163_class_extends_iface_typed_field_write/phase1_repro_spike_test.ss`**(149 行 — Case 1 single iface field write/read minimum repro 移植 / Case 2 多 iface field write box1+box2 / Case 3 nested 三层 extends + iface impl chain Grandchild→Child→Parent 同形)— RED-as-spike 范式延续 D135 spike 同形;**LLVM IR inspect 实测推翻 §A.2 H1 GEP offset 错位假设**:`bin/ss build /tmp/d160_min_repro.ss --emit-ir` 显示 WRITE 路径 GEP offset + RC retain/release 全正确,READ + method call 路径 method dispatch IR 缺失 → fall through 至 emit `; TODO: method call .fetch` + 0 字面量替代;**真根因 file:line**:bootstrap/gen/gen_types.ss:248-249 resolveObjClass MEMBER_ACCESS 分支只检 `classFields.has(fType)` 漏检 `ifaceMethodsCG.has(fType)` → MEMBER_ACCESS 节点 this.box 因 fType=Box(interface)走 fall through `return ""` → bootstrap/gen/methods/gen_methods.ss:497 interface dispatch 入口因 objClass="" 不进 → bootstrap/gen/methods/gen_methods.ss:565 fallback emit TODO 注释 + return "0" 替代 method call IR;**Phase 2 修法 target = bootstrap/gen/gen_types.ss:249 后 +1 行**(复用范式见同文件 line 167 IDENT / 200-201 METHOD_CALL / 211-212 INDEX_ACCESS / 224-225 TERNARY 全部已用 ifaceMethodsCG.has 双检,仅 MEMBER_ACCESS 漏一处补齐对称);**baseline**:bootstrap/ + lib/ + tools/ diff = 0(本 Phase 仅 tests/ + 诊断)+ tests/ +1 file(spike RED → fail count +1)→ 304/17/321 + d_doc_index_linter F1=0 + 14 reflection 全继承 + next_prompt_ultrathink_linter PASS;**simplify 跳过**(本 Phase 仅 spike 文件 + docs/ 不动 bootstrap/lib/tools/);**§N §6 file:line 锚**:tests/d163_class_extends_iface_typed_field_write/phase1_repro_spike_test.ss(spike 落地)+ docs/3-decisions/D163-class-extends-iface-typed-field-write.md(§Phase 0 hash `eb7bd05` 跨 D 回填 4 处)+ .claude/next_prompt.md(本 Phase 2 起首 ultrathink);**等下轮 D163 §Phase 2 — bootstrap/gen/gen_types.ss:249 +1 行修法 + 三阶段固定点 + Phase 1 spike 重跑全 GREEN**

- 2026-05-09 **D163 §Phase 2 bootstrap/gen/gen_types.ss:249 +1 行 ifaceMethodsCG.has 守护 wire 落地 + 三阶段固定点 stage2==stage3 PASS + Phase 1 spike 3 case 全 GREEN**(commit `<phase2-hash>`)— **PRIMARY 修法 wire 落地**:`bootstrap/gen/gen_types.ss:249` 在 `if (fType != "" && classFields.has(fType) == 1) { return fType }` 之后 **+1 行** `if (fType != "" && ifaceMethodsCG.has(fType) == 1) { return fType }`(复用范式见同文件 line 167 IDENT / 200-201 METHOD_CALL / 211-212 INDEX_ACCESS / 224-225 TERNARY 全部已用 ifaceMethodsCG.has 双检 ifaceType return field type,仅 MEMBER_ACCESS 漏一处补齐对称);**RED→GREEN 实测**:Phase 1 spike `bin/ss test tests/d163_class_extends_iface_typed_field_write/` 1 passed / 0 failed / 1 total(单 file 内 3 个 test() 全 GREEN:Case 1 r=99 / Case 2 r=30 / Case 3 r=77 — assertEqual(r, 99/30/77) 全过);**LLVM IR 验证**:`bin/ss build phase1_repro_spike_test.ss --emit-ir -o /tmp/d163_spike` 后 `grep -c "TODO: method call" /tmp/d163_spike.ll` = 0(从 4 → 0)+ `__iface_BoxD163_fetch` 调用 5 次(line 5699 Case 1 + 5893+5898 Case 2 + 6315 Case 3 + iface helper 内部 1 次);**bootstrap 三阶段固定点 stage2==stage3 bit-identical PASS** — `./build.sh bootstrap` 输出 `Fixed point verified! Stage 2 = Stage 3 — Updated bin/ss`(自举 ≈ 55s,CLAUDE.md §构建与测试 范式延续);**baseline**:bin/ss test tests/ 净 +1 PASS(Phase 1 RED 304/17/321 → Phase 2 GREEN 305/16/321)+ d_doc_index_linter F1=0 PASS(D147/D154/D155/D156/D157/D160/D161/D162/D163 全实存)+ reflection_health_linter GATE PASS — no regressions(M1-M7+N1-N5 全继承 + F1 bootstrap/gen/gen_types.ss cur=888 bv=885 bm=1050 → DRIFT 软警告,远低 budget_max,无 BLOCKED — Phase 2 +1 行业务代码 LOC 增量极小)+ next_prompt_ultrathink_linter PASS(下轮 D163 §Phase 3 起首含 ultrathink);**§A.2 H1 假设修正记录**:从 "GEP offset 错位" 修为 "MEMBER_ACCESS 接口字段 type resolver 漏检 ifaceMethodsCG.has → method call fall through 到 TODO fallback"(LLVM IR inspect 是 truth source,§A.2 是当时静态推断的假设 ledger,Phase 1 已是 truth);**simplify 必走**(bootstrap/gen/gen_types.ss +1 行业务代码改动 — 4 agent 评估 reuse / quality / efficiency / readability,readability veto 优先;预期 simplify 4 agent 全 ACCEPTED — +1 行复用范式与 line 167/200-201/211-212/224-225 同形,职责单一可读性赢简洁);**§N §6 file:line 锚**:bootstrap/gen/gen_types.ss:250(新 +1 行 — 原 line 249 → 新 line 250)+ docs/3-decisions/D163-class-extends-iface-typed-field-write.md(Status header / §Phase commit hash 总览段表 Phase 1 行 / §Phase 1 §收关锚 / §Phase 2 §收关锚 / Status 时间线 Phase 1 + Phase 2 entry — 跨 D 起首回填 D163 §Phase 1 hash `8933f0a` 至 D163.md 4 处实际语义位)+ .claude/next_prompt.md(下轮 D163 §Phase 3 起首 ultrathink);**等下轮 D163 §Phase 3 — D160 §Phase 4 wire 真值反射重启 + 在线 docker `bin/ss test tests/d160_callable_statement/` 8 case 全 GREEN(getInt(2)=20 / getInt(1)=15 / 多 OUT / 三态 mode / getString / getDouble / wasNull)+ 跨 D 起首回填 D163 §Phase 2 hash 至 D163.md ≥3 处 + 跨 D 起首回填 D163 §Phase 2 hash 至 D160.md ≥3 处**
