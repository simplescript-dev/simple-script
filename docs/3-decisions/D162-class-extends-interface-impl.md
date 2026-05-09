# D162: class extends class + interface impl — D025 walk classParents 漏检修根因

**Status:** [x] Phase 0 D 文档落档 at commit `418fe5d` + [x] Phase 1 parser 验证 extends + : 组合语法 + ≥3 case spike GREEN at commit `<phase1-hash>` + [ ] Phase 2 checker walk classParents 修法 + ≥6 case codegen spike GREEN at commit `<phase2-hash>` + [ ] Phase 3 D160 Phase 2 真 extends 形态回退验证 + ≥12 case spike GREEN at commit `<phase3-hash>` + [ ] Phase 4 D162 主线 close + D160 §F8 跨 D 起首回填 at commit `<phase4-hash>` — D161 主线 close → D160 Phase 1 重启 → D162 起首脱胎,D135-D161 编译器/SQL 主线范式延续。修 SS 编译器 `bootstrap/checker/check_class.ss:62-94 checkInterfaceImpl` D025 vtable check 漏 walk classParents 链根因 — `class MysqlCallableStatement extends MysqlPreparedStatement : CallableStatement` 触发 12 处 `missing method 'executeUpdate' / 'executeQuery' / ...` 假阳报错(父类 MysqlPreparedStatement 已实现 13 PreparedStatement method,checkInterfaceImpl 不 walk classParents 不识别)— 不接受 re-declare 13 method workaround / composition pattern 替代 / D025 check 跳过 walk 节省。

## 起首脱胎
- D161 主线 close at commit `6cfb300`(interface extends 编译器路径)→ D160 Phase 1 重启 at commit `3bd4d61`(interface CallableStatement extends PreparedStatement 21 own method 形态)→ D160 Phase 2 落地实测发现 `class C extends Parent : Interface` 触发 D025 vtable check 假阳 → D162 起首脱胎(class extends class + interface impl 编译器路径)
- D135-D161 编译器层 + SQL 主线范式延续(Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环 + §A.2 隐藏假设挑战 + §A.3 废案 + §Followup)
- Depends on:D161(interface extends 编译器路径主线 close — parser parseInterfaceDecl 加 EXTENDS + ifaceParents Map + walk parent chain merge)+ D025(vtable check 范式 — check_class.ss checkInterfaceImpl 强制 implementor class 必须实现 interface methods)+ D071(abstract method walk classParents 修法范式 — check_class.ss checkAbstractImpl 已 walk classParents 链合并 concrete method 集合,本 D 是其在 interface vtable check 端的姊妹修法)
- D160 Phase 2 hold 等本 D 主线 close 后回头落地 — `class MysqlCallableStatement extends MysqlPreparedStatement : CallableStatement` 真 extends 形态(继承父类 14 字段 + 13 PreparedStatement method,加 3 own 字段 + 21 own method + getParameterMetaData override),自动满足 D025 vtable check

## 核心目标 (Goal)

落地后:
1. `bootstrap/checker/check_class.ss:62-94 checkInterfaceImpl` 加 walk classParents 链 — 子类 implementor class 走 `class C extends Parent : Interface` 时,checkerError 假阳消除(父类 own methods 自动满足子类 interface vtable)
2. `class C extends Parent : Interface` 组合语法 parser 范式锚定(parseClassDecl line 427-441 已支持,但仓内首次系统性使用 — D162 §A.2 H1 实证锚)
3. 多层 chain(`class GrandChild extends Child : Interface` 其中 Child extends Parent)走 classParents 链全集传递(Phase 2 ≥6 case codegen spike 验证)
4. 子类 override 父类 method 时 D025 走子类签名(子赢 — Phase 2 §A.2 H3 实证)
5. 父类已实现 method 子类不必 re-declare 即满足 D025(`class C extends Parent : Interface` 的根因解决路径,与 D161 walk-ifaceParents 同形 — 本 D 是 walk-classParents 的姊妹修法)
6. D160 Phase 2 真 extends 形态回退验证(`class MysqlCallableStatement extends MysqlPreparedStatement : CallableStatement` 编译通过 + Phase 2 spike ≥12 case GREEN + bin/ss test tests/ baseline 全继承)
7. D025 negative anchor 验证(`class BadChild extends Parent : Interface { 仅父类不实现 + 子类不实现的 method }` → exit=1 stderr 含 missing method 错误 — 走 walk classParents 后仍强制全集实现)
8. `./build.sh bootstrap` 三阶段固定点 stage2==stage3(checker.ss 改动必走 self-bootstrap 验证 — §A.2 H5)+ `bin/ss test tests/` baseline 全继承 + reflection_health_linter 全 14 指标无 regression + d_doc_index_linter F1 = 0 + next_prompt_ultrathink_linter PASS

**RED**(本 D 文档落档前实测):
- `ls docs/3-decisions/D162-class-extends-interface-impl.md` = ENOENT(D162 不存在,起首必新建)
- `bin/ss build prepared.ss with class MysqlCallableStatement extends MysqlPreparedStatement : CallableStatement` 实测 = exit=1 stderr 含 12 处 `error: class 'MysqlCallableStatement' missing method '<X>' required by interface 'CallableStatement'`(executeUpdate / executeQuery / getGeneratedKeys / getLastInsertId / close / setInt / setLong / setString / setDouble / setBoolean / setNull / setFetchSize 全 13 inherited PreparedStatement method 假阳报错 — 父类已全实现)
- `grep -nE "function checkInterfaceImpl" bootstrap/checker/check_class.ss` 实测 = 62(line 62-94 主体,classMethods 仅本类 own,无 walk classParents)
- `grep -c "<phase4-hash>" docs/3-decisions/D161-interface-extends.md` 实测 = 0(D161 Phase 4 hash `6cfb300` 已回填,本 D 起首不需回填 D161)
- `grep -c "<D162-phase0-hash>" docs/3-decisions/D160-callable-statement-out-inout.md` 实测 ≥1(D160 Status 时间线 D162 起首脱胎 entry 待本 Phase 0 commit 回填)

## 核心原则 (Principles)

1. **修编译器根因不接 workaround / 节省路径**(用户对话锁不接次优;CLAUDE.md "Root Cause 优先 — 不接受次优 / workaround / 节省" 第一法则):D160 Phase 2 不允许 re-declare 13 method workaround,不允许走 composition pattern 规避 extends,不允许跳过 D025 check 让 walk 假错放过 — 真 extends 形态走 D025 walk classParents 修根因
2. **复用 D161 walk-ifaceParents 修法范式**:D161 §Phase 2 加 walk ifaceParents 链 merge ifaceMethods 是子接口走父接口 method 集合的修法;本 D 是其镜像 — implementor class 走 walk classParents 链 merge ownMethods 满足 interface vtable
3. **复用 D071 walk-classParents 修法范式**:`bootstrap/checker/check_class.ss:97 checkAbstractImpl` 已实现 walk classParents 合并 concrete methods 满足 abstract method 强制实现要求,本 D 是其在 interface vtable check 端的姊妹修法 — checkInterfaceImpl 应同步 walk
4. **bootstrap fixed-point 自举安全**:checker 改动必走 self-bootstrap 三阶段 stage2==stage3 bit-identical(§A.2 H5)— 本 D 不动 codegen / parser,仅改 checker 单文件,自举影响范围小
5. **dispatch 时已 walk classParents,本 D 仅补 check 假阳**:实际 dispatch 路径(method_call.ss)走 classParents chain 命中父类 method,wire 端可执行;D025 check 端假阳是 check_class.ss checkInterfaceImpl 单点缺陷 — 本 D 仅修 check 端,不动 dispatch 端
6. **D135-D161 主线范式延续**:Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环 + §A.2 隐藏假设 + §A.3 废案 + §Followup
7. **D025 negative anchor 不削弱 walk 后**:walk classParents 合并后,父类 + 子类全集仍未实现 interface method 必须 exit=1 — 不允许 walk 让真错放过,Phase 2 spike _negative test doc-anchor 验证
8. **scope 限单 sub-D**:本 D 仅修 checkInterfaceImpl 单函数 + 加 helper walk(~15-30 LOC),不引入 codegen 改动 / parser 改动 / 全局 method-collection refactor — `class C extends A, B`(多继承)留 §Followup F2 远期
9. **业界对标 Java + TS extends + implements 必须正确处理父类 method 满足子类 interface**:Java `class C extends Parent implements I` 父类 own methods 自动满足子类 interface vtable;TS `class C extends Parent implements I` 同形;Kotlin `class C : Parent(), I` 同形 — SS `class C extends Parent : Interface` 必须达到同样语义,本 D 是必需的根因补齐(N 年返工度 100%,后续每条 sub-D class extends class + : interface 必依赖)

## A.1 主候选评估(§MNK §M §字段 10)

| 候选 | 层次 | 含 | 不含 | 决策 |
|------|------|-----|------|------|
| **C1** | 数据层 patch | + 在 D160 内 re-declare 13 PreparedStatement method workaround(子类显式重新声明每个 method 复制父类同体)| 编译器层无修;后续每条 `class C extends Parent : Interface` 必继续 re-declare workaround;CLAUDE.md "Root Cause 优先 — 同一个 workaround 出现第二次必须停下修根因" 第一法则触发(D160 Phase 2 是首次,但单 D 内重复 13 次 ≫ 2 次门槛 + 类型已知必复 5+ 次后续 sub-D)| **不选** — 用户对话锁不接次优 / workaround / 节省;CLAUDE.md 第一法则触发;Java/TS 业界对标必修编译器 |
| **C2** | **接口层 trap(根因)** | + bootstrap/checker/check_class.ss checkInterfaceImpl 加 walk classParents 链合并 ownMethods + parentMethods 集合后再校验 interface vtable + Phase 1 parser 验证 extends + : 组合语法可执行 + Phase 2 ≥6 case codegen spike(单层 + 多层 chain + override + 同名不同 paramSig + multi-iface + D025 negative anchor)+ Phase 3 D160 Phase 2 真 extends 形态回退验证 ≥12 case GREEN | 多继承 `class C extends A, B`(SS 不支持多继承,留 §F2 远期)+ codegen 端显式 merge methods(method_call.ss 已 walk chain dispatch,本 D 仅修 check 端假阳,留 §F1 远期)+ abstract method walk(D071 已修,本 D 仅 interface vtable 端补齐) | **选** — 根因解决:CLAUDE.md "Root Cause 优先" 第一法则 + Java/TS 业界对标必修(`extends Parent implements I` 父类 own methods 自动满足子类 interface vtable)+ D161 walk-ifaceParents 修法范式延续(本 D 是其镜像 — walk-classParents)+ D071 walk-classParents 修法范式延续(checkAbstractImpl 已 walk,本 D 在 checkInterfaceImpl 同步)+ N 年返工度 100%(后续每条 sub-D class extends class + : interface 必依赖)+ scope 中等可控(单函数 + 单 helper ~15-30 LOC + Phase 1-3 spike + Phase 4 close)+ D135-D161 主线范式延续 |
| **C3** | 架构层 refactor | + checkInterfaceImpl 完整 + 全局统一 method-collection 抽象(walk classParents + walk ifaceParents 一并处理)+ codegen 端显式 merge methods + multi-extends `class C extends A, B` 多继承支持 + D025 check 跳过 walk 让 abstract / final 修饰符控制 | spec 100%;Java + TS + Kotlin + Scala 全语法套件;多继承 + Wrapper.unwrap 跨 D 通用 + abstract / final 修饰符全套 | **不选** — scope 远超 D162 单 sub-D(LOC > 1000;多继承独立 sub-D + 全局抽象 + abstract/final 修饰符独立 sub-D + Wrapper.unwrap 跨 D 通用) |

**决策行**:**选 C2 接口层 trap(根因)** — 因 (a) CLAUDE.md "Root Cause 优先" 第一法则 + 不接次优 / workaround / 节省路径(D160 Phase 2 不允许 re-declare 13 method workaround);(b) Java/TS 业界对标(`class C extends Parent implements I` 父类 own methods 自动满足子类 interface vtable 是 Java + TS + Kotlin + Scala 全部支持的核心特性,SS 缺它必拖累后续每条 sub-D 用 class extends class + : interface 形态);(c) D161 walk-ifaceParents 修法范式镜像(D161 §Phase 2 加 walk ifaceParents 链 merge ifaceMethods 是子接口走父接口 method 集合的修法;本 D 是其姊妹 — implementor class 走 walk classParents 链 merge ownMethods 满足 interface vtable);(d) D071 walk-classParents 修法范式延续(checkAbstractImpl 已实现 walk classParents 合并 concrete methods 满足 abstract method 强制实现要求,本 D 是其在 interface vtable check 端的姊妹修法 — checkInterfaceImpl 应同步 walk);(e) **N 年返工度 100%**:不做 → 每条 `class C extends Parent : Interface` 形态全部 re-declare workaround,SQL 主线 D160 / D154 / D155 driver class 演化路径必拖累;(f) scope 中等可控(单函数 ~15-30 LOC + Phase 1-3 spike 验证 + Phase 4 close,5 commit 切片);(g) D135-D161 主线范式延续(Phase 计划独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环 + §A.2 隐藏假设 + §A.3 废案 + §Followup)。**为何不选 C1**:CLAUDE.md 第一法则明确触发(D160 Phase 2 单 D 内重复 13 次 + 后续 sub-D 必复 5+ 次),用户对话锁不接次优 / workaround / 节省。**为何不选 C3**:scope 远超 D162 单 sub-D — 多继承 / 全局 method-collection 抽象 / abstract/final 修饰符全套 / Wrapper.unwrap 跨 D 通用 各留 §Followup 独立 sub-D。

## A.2 隐藏假设挑战

| H | 假设 | 挑战 | 实证锚 |
|---|------|------|--------|
| H1 | parser parseClassDecl 已支持 `class C extends Parent : Interface` 组合语法(line 427-441 EXTENDS + COLON 双子句解析)| parseClassDecl line 427-431 解析 EXTENDS 子句存 extendsName,line 435-441 解析 COLON 子句存 implList,二者顺序固定(EXTENDS 在前 COLON 在后)— 本 D 仓内首次系统性使用此组合形态,需 Phase 1 parser 节点 unit test 验证 nGetS2(extendsName)+ nGetS3(implList)双 slot 全填 | Phase 1 ≥3 case spike — Case 1 `class C extends Parent : I` 双 slot 全填 / Case 2 `class C extends Parent : I, J` 多 interface impl / Case 3 `class C extends Parent` 仅 extends 无 implList 兼容路径 |
| H2 | classMethodNames Map 已存父类 own methods(class_register.ss 已 set classMethodNames[parentName])— checkInterfaceImpl 加 walk classParents 后可直接复用,不需要 codegen 层改 | bootstrap/gen/class/class_register.ss line 198 resolveInheritance() 已为 classParents 链每个父类 set classMethodNames,本 D Phase 2 修法仅在 checkInterfaceImpl 端 walk classParents 链查 classMethodNames 合并 ownMethods 即可,不动 codegen / parser | Phase 2 spike Case 1 单层 `class Child extends Parent : I` 父类 method 走 D025 通路 + Case 2 多层 chain(GrandChild → Child → Parent)父+祖父 method 全集合并 |
| H3 | 多层 chain(`class GrandChild extends Child : Interface` 其中 Child extends Parent)walk 链全集传递 + idempotent | Phase 2 修法 walk classParents 链直到 ""(根类),visited 守 self-loop hang(同 D161 §Phase 2 visited Map 防御范式)— 真实场景 SS 不支持多继承,链结构是树而非 DAG,但 visited 守仍必要防 `class A extends A` 编程错误 self-loop | Phase 2 spike Case 2 多层 chain — `class GrandChild extends Child : I` 其中 Child extends Parent,Parent 实现 I 的部分 method,Child 实现剩余,GrandChild 不 re-declare 任何 method 走 D025 通路 + visited 守不 hang |
| H4 | 子类 override 父类 method 时 D025 走子类签名(子赢)| 子类 own method 与父类 method 同名同签名 → ownMethods 集合包含子类 method,walk 父类时 dedupe(已在 ownMethods 中跳过 add)— 子赢自然 fall-through;同名不同签名 → 双条 method 不 dedupe(method overloading,各自 mangled key 不同) | Phase 2 spike Case 3 子类 override `class Child extends Parent : I { function foo(): int { return 42 } }` 父类 foo 返 0,子类 foo 返 42 — D025 通路 + Case 4 同名不同 sig overload 不 dedupe(`function foo()` vs `function foo(x: int)` 父子各持) |
| H5 | bootstrap fixed-point 自举安全 — checker.ss 改动必走 self-bootstrap 三阶段 stage2==stage3 bit-identical 验证 | check_class.ss 改动直接影响 bootstrap 自身编译过程(bootstrap/ 内 class 用 D025 vtable check),修法必须 idempotent + 不改 method merge 顺序破坏现有 bootstrap;`./build.sh bootstrap` 三阶段固定点必走过 | Phase 2 修法落地后 `./build.sh bootstrap` GREEN(stage2 md5 == stage3 md5);Phase 1 parser 不改不需自举验证(parser 已支持组合语法,Phase 1 仅 spike test 验证) |

## A.3 废案

- **C1 数据层 patch**(用户对话锁不接次优;D160 Phase 2 单 D 内重复 re-declare 13 method workaround + 后续 sub-D 必复 5+ 次,CLAUDE.md "同一个 workaround 出现第二次必须停下修根因" 第一法则触发)
- **C3 架构层 refactor + 多继承 + 全局 method-collection 抽象 + abstract/final 修饰符全套**(scope 远超 D162 单 sub-D — 各独立 sub-D 留 §Followup F1-F4)
- **D025 check 跳过 walk 让 abstract / final 修饰符控制**(违反 §核心原则 7 — walk 不削弱 D025,真错仍 exit=1;跳过 walk 是放任假阳兼隐藏真错,不可接受)
- **composition pattern 替代 extends**(违反 §核心原则 1 — 用户对话锁不接 workaround;`class MysqlCallableStatement : CallableStatement { inner: MysqlPreparedStatement; ... 13 method delegations }` 是 OO composition over inheritance,但回避了 SS 编译器 D025 check 缺陷,不修根因;本 D 走真 extends 形态走根因修法)
- **D162 与 D160 Phase 2 同 commit 落地**(scope 失控 — D162 是编译器层根因 + D160 Phase 2 是应用层 driver class 真实现,二者分开切片;D162 主线 close 后 D160 Phase 2 重启 commit 跨 D 起首回填范式延续)
- **walk classParents 也加 walk ifaceParents on impl side**(scope 远超 — D161 §Phase 2 已修 walk-ifaceParents 子接口走父接口,本 D 仅修 walk-classParents 子类走父类;两个独立修法,合并会破 scope)
- **codegen 端显式 merge methods**(method_call.ss 已通过 classParents chain dispatch 命中父类 method,wire 端已可执行;本 D 仅修 check 端假阳,codegen 不动 — 留 §Followup F1 远期评估)
- **parser parseClassDecl 改支持 EXTENDS 在 COLON 后**(parser 历史顺序固定 EXTENDS 在 COLON 前,改顺序破坏向后兼容 — 留 §Followup F3 远期独立 sub-D)
- **abstract method walk classParents 重写**(D071 已实现 checkAbstractImpl walk classParents 合并 concrete methods 集合,本 D 不重写 D071 修法 — 仅在 checkInterfaceImpl 同步 walk 范式;D071 范式直接复用)
- **强制把已有 `: Interface` 单 implList 形态全部回退到 `extends Parent : Interface`**(scope 失控 — 现有 lib/ 仓内多处 `class MysqlConnection : Connection` / `class MysqlStatement : Statement` 等单 implList 形态稳定;本 D 仅启用 `extends Parent : Interface` 形态可行不强制回退;留 §Followup F4 simplify 评估远期)

## Phase commit hash 总览

| Phase | 内容 | Commit |
|-------|------|--------|
| 0 | D 文档落档(§核心目标 + §核心原则 + §A.1-A.3 + §Phase 收关锚 Phase 0-4 + §Followup F1-F4)+ D161 §F8 entry 末尾"等下轮"指向 D162 + D160.md Status header Phase 2 hold 锚 + D160.md §Followup F8 row + D160.md Status 时间线 D162 起首脱胎 entry | `418fe5d` |
| 1 | parser 验证 extends + : 组合语法 + ≥3 case spike GREEN(class extends class + : interface 同时存在的 parser 节点验证 — nGetS2/extendsName + nGetS3/implList 双 slot 全填) | `<phase1-hash>` |
| 2 | bootstrap/checker/check_class.ss checkInterfaceImpl walk classParents 链合并 ownMethods + parentMethods + ≥6 case codegen spike GREEN + D025 negative anchor + bootstrap fixed-point stage2==stage3 PASS | `<phase2-hash>` |
| 3 | D160 Phase 2 真 extends 形态回退验证(`class MysqlCallableStatement extends MysqlPreparedStatement : CallableStatement` + 单字段 paramDirections + 21 own method 真实现 + ≥12 case spike GREEN)+ absorb spike 评估 | `<phase3-hash>` |
| 4 | D162 主线 close 锚 + D160 §F8 跨 D 起首回填(D162 主线 close hash 回填至 D160.md §F8 row + D160.md Status 时间线 D162 起首脱胎 entry hash) | `<phase4-hash>` |

## Phase 收关锚

### Phase 0: D 文档落档 [x] Done at commit `418fe5d`

- 落地 `docs/3-decisions/D162-class-extends-interface-impl.md`(本文件)— §核心目标 + §核心原则 + §A.1 候选评估 + §A.2 隐藏假设 H1-H5 + §A.3 废案 + §Phase 收关锚 Phase 0-4 + §Followup F1-F4 + §Status 时间线
- D161.md F8 entry 末尾"等下轮"指向 D162 起首脱胎(已在本 Phase 同 commit 修)+ D160.md Status header Phase 2 hold 锚 + D160.md §Followup F8 row + D160.md Status 时间线 D162 起首脱胎 entry
- 落地 `.claude/next_prompt.md`(下轮 D162 Phase 1 起首 — parser 验证 extends + : 组合语法 + ≥3 case spike GREEN)
- payload 走 §M PSM 九问 B 档(sub-D 中段 Phase 1 parser unit test,scope ≤200 行 tests/d162_class_extends_interface_impl/),next_prompt_ultrathink_linter C1-C4 全 PASS(file exists + non-empty + ultrathink keyword + 标题不声明 docs-only)
- bootstrap/ + lib/ + tools/ + tests/ diff = 0(本 Phase 纯 docs/ + .claude/next_prompt.md)
- baseline:d_doc_index_linter F1 = 0(D147/D154/D155/D156/D157/D160/D161 全实存,加入 D162 实存)+ next_prompt_ultrathink_linter PASS + 14 reflection 指标全继承 D161 主线 close baseline(本 Phase 不动 bootstrap/)
- §A.2 H1-H5 假设挑战全实证锚明确

### Phase 1: parser 验证 extends + : 组合语法 + ≥3 case spike GREEN [x] Done at commit `<phase1-hash>`

- `tests/d162_class_extends_interface_impl/phase1_parser_unit_test.ss` 3 case 全 GREEN — Case 1 `class TestChildD162 extends TestParentD162 : TestIfaceD162` 双 slot 全填(nGetS2/extendsName + nGetS3/implList)+ Case 2 `class TestChildD162B extends TestParentD162B : TestIfaceD162B, TestIfaceD162C` 多 interface impl(implList comma 分割)+ Case 3 `class TestChildD162C extends TestParentD162C` 仅 extends 无 implList 兼容路径
- 不动 parser(parseClassDecl line 427-441 已支持组合语法 — §A.2 H1 实证锚,Phase 1 仅 spike test 验证)
- §A.2 H1 实证(parser EXTENDS + COLON 双子句解析与现有 class extends + interface impl 同形)— 编译 + 运行 exit 0 即 parser 节点 nSetS2/nSetS3 双 slot 落地的间接验证
- Phase 1 binary 下 D025 vtable check 不 walk classParents,故 Case 1-2 子类必须 re-declare interface methods 满足 D025 vtable check;Phase 2 walk classParents 修法落地后,子类不必 re-declare 即可走父类 method 满足 vtable(D162 §核心目标 5)
- bootstrap fixed-point 不需走(本 Phase 不动 bootstrap/,纯 docs/ + tests/ 改动)
- baseline:bin/ss test tests/ 净 +1 file +3 case + d_doc_index_linter F1 = 0 + reflection_health_linter no regression
- VCM 六验全 PASS

### Phase 2: checker walk classParents 修法 + ≥6 case codegen spike GREEN [ ] Pending at commit `<phase2-hash>`

- `bootstrap/checker/check_class.ss` checkInterfaceImpl 修法 — 加 walk classParents 链合并 ownMethods + parentMethods 集合(同 D071 checkAbstractImpl line 97 范式)+ visited 守 self-loop hang(同 D161 §Phase 2 visited Map 防御范式)
- 修法 ~15-30 LOC,不引入新 helper 函数(直接在 checkInterfaceImpl 内 inline walk)或可抽 walkClassMethods helper(跨 checkInterfaceImpl + checkAbstractImpl 共用,Phase 2 simplify 内决断)
- `tests/d162_class_extends_interface_impl/phase2_codegen_spike_test.ss` ≥6 case 全 GREEN — Case 1 单层 `class Child extends Parent : I` 父类 method 满足子类 interface / Case 2 多层 chain(GrandChild → Child → Parent : I)父+祖父 method 全集合并 / Case 3 子类 override 父类 method 子赢 / Case 4 同名不同 sig overload 不 dedupe / Case 5 multi-iface `class C extends P : I, J` 父类 method 同时满足 I + J 子集 / Case 6 D025 negative anchor — `class Bad extends P : I { 父+子全集仍缺 method }` 必 exit=1
- `tests/d162_class_extends_interface_impl/_negative_phase2_d025.ss.txt` D025 negative doc-anchor — `class BadChildD162 extends ParentD162Neg : ChildD162Neg { 仅父+子全集仍缺 method }` → bin/ss build exit=1 stderr 含 missing method 错误(commit-time shell verify exit=1 + grep -c "missing method")
- `./build.sh bootstrap` 三阶段固定点 stage2==stage3 PASS(§A.2 H5 — checker 改动必走 self-bootstrap)
- §A.2 H2 + H3 + H4 + H5 实证完整(H2 classMethodNames 已存父类 method / H3 多层 chain idempotent + visited 守 / H4 子赢 override / H5 bootstrap fixed-point)
- baseline:bin/ss test tests/ 净 +1 file +6 case + d_doc_index_linter F1 = 0 + reflection_health_linter:checker.ss F1 行数 + N1 SCOPE-DRIFT(若改动 bootstrap/checker 触发反射 scope 软警告,扩容申报锚)
- VCM 六验全 PASS

### Phase 3: D160 Phase 2 真 extends 形态回退验证 + ≥12 case spike GREEN [ ] Pending at commit `<phase3-hash>`

- `lib/com/mysql/prepared.ss` 加 `class MysqlCallableStatement extends MysqlPreparedStatement : CallableStatement`(继承父类 14 字段 + 13 PreparedStatement method;新加 3 own 字段 paramDirections + outRow + lastWasNull;21 own method 真实现 + 1 override getParameterMetaData)+ injectOutVarSetters / appendOutVarSelectors SQL 重写 helper 加 + doPrepareCall factory + 升级 MysqlParameterMetaData paramDirections 字段 + getParameterMode 反射(突破 D157 §核心原则 4 静态 IN-only 妥协)
- `lib/com/mysql/jdbc.ss` MysqlConnection.prepareCall 替换 stub 为真返 `doPrepareCall(this.fd, sql)`
- NoopDate / NoopTime move 至 driver_types.ss(避开 prepared.ss → jdbc.ss 循环导入)+ 同步 jdbc.ss imports
- `tests/d160_callable_statement/phase2_spike_test.ss` ≥12 case 全 GREEN(MysqlCallableStatement class 字段 / paramDirections 初始全 IN / registerOutParameter 设 OUT / registerOutParameter 重 setXxx 后设 INOUT / getParameterMode 反射 IN/OUT/INOUT 三态 / 多类型 OUT getter ≥4 case[getInt/getString/getDouble/getBoolean] / wasNull / SQL 重写 helper unit / 多 OUT 多 INOUT 混合 / outRow 字段非 null + 多 case 反射)
- D162 §A.2 H1-H5 实证 wire 端落地完整 — 真 extends 形态走 D025 walk classParents 通路全 GREEN(本 D 修法的 wire 端验证)
- bootstrap fixed-point 不需走(本 Phase 仅 lib/ + tests/ 改动不动 bootstrap/)
- baseline:bin/ss test tests/ 净 +1 file +12 case + d_doc_index_linter F1 = 0 + reflection_health_linter no regression(本 Phase 不动 bootstrap/)
- VCM 六验全 PASS

### Phase 4: D162 主线 close + D160 §F8 跨 D 起首回填 [ ] Pending at commit `<phase4-hash>`

- D162 主线 close 锚:Status header `[x] Phase 0-4 + [x] D162 主线 close at commit \`<phase4-hash>\``
- 跨 D 起首回填范式延续:本 D 主线 close 后的 Phase 4 hash 回填至 D160.md §F8 row(`<D162-phase4-hash>` placeholder)+ D160.md Status 时间线 D162 起首脱胎 entry hash(`<D162-phase0-hash>` placeholder)+ D160.md Status header Phase 2 hold 锚解锁("hold" → "[x] Phase 2 重启" + commit hash)
- D160 Phase 2 重启 commit `<D160-phase2-hash>` 已在 Phase 3 commit 一并落地(D162 §F? 路径或并行)— D160 Phase 3 docker e2e 仍 pending(D160 §Phase 3 收关锚)
- baseline:bootstrap/ + lib/ + tools/ + tests/ diff = 0(本 Phase 纯 docs/ + .claude/next_prompt.md)+ d_doc_index_linter F1 = 0 + 14 reflection 指标全继承
- VCM 六验全 PASS

## Followup

| F | 内容 | 范围 |
|---|------|------|
| F1 | codegen 端显式 merge methods walk classParents — method_call.ss 已通过 classParents chain dispatch 命中父类 method,wire 端已可执行;codegen 端显式 merge 仅让 IR 更直观,marginal 优化 — 留独立 sub-D 远期 |
| F2 | 多继承 `class C extends A, B` — SS 不支持多继承(parser parseClassDecl line 427-431 EXTENDS 仅吃单 ident),Java 同 SS 限制(单类继承 + 多接口实现);本 D 不开多继承支持 — 留独立 sub-D 远期(若有强需求,scope 远超本 D)|
| F3 | parser parseClassDecl 改支持 EXTENDS 在 COLON 后 — 历史顺序固定 EXTENDS 在 COLON 前,改顺序破坏向后兼容;Java + TS 顺序固定 `extends ... implements ...`,不需要灵活,本 D 不开此分支 — 留独立 sub-D 远期 |
| F4 | simplify 评估 — 现有 lib/ 仓内多处 `class MysqlConnection : Connection` / `class MysqlStatement : Statement` 等单 implList 形态稳定,是否回退到 `class C extends Parent : Interface` 形态(若 Parent 抽出公共字段);scope 失控不强制,留 §Followup simplify Agent 评估远期 |

## Status 时间线

- 2026-05-09 Phase 0 D 文档落档(commit `418fe5d`)— **新建 docs/3-decisions/D162-class-extends-interface-impl.md**(≥150 行 — §核心目标 + §核心原则 + §A.1 候选评估 + §A.2 隐藏假设 H1-H5 + §A.3 废案 + §Phase 收关锚 Phase 0-4 + §Followup F1-F4 + §Status 时间线)+ D161.md F8 entry 末尾"等下轮"更新指向 D162 起首脱胎(D161 §F8 wire 落地 entry 末尾改写)+ D160.md Status header Phase 2 hold 锚("[ ] Phase 2 hold(D162 编译器层 D025 walk classParents 修法主线 close 后回头做)"+ D160.md §Followup F8 row + D160.md Status 时间线 D162 起首脱胎 entry;**RED 实测**:`ls D162 = ENOENT` / `bin/ss build prepared.ss with class MysqlCallableStatement extends MysqlPreparedStatement : CallableStatement` 实测 = exit=1 stderr 含 12 处 missing method 假阳报错(executeUpdate / executeQuery / getGeneratedKeys / getLastInsertId / close / setInt / setLong / setString / setDouble / setBoolean / setNull / setFetchSize 全 13 inherited PreparedStatement method)/ `grep -nE "function checkInterfaceImpl" bootstrap/checker/check_class.ss = 62`(line 62-94 主体,classMethods 仅本类 own,无 walk classParents);**GREEN**:D162.md 落档 ≥150 行 + D161.md F8 entry 更新 + D160.md Status header Phase 2 hold 锚 + D160.md §Followup F8 row 起首脱胎 + D160.md Status 时间线 D162 起首脱胎 entry + .claude/next_prompt.md 含 ultrathink 关键字 + 下轮 D162 Phase 1 起首;**baseline**:bootstrap/ + lib/ + tools/ + tests/ diff = 0(本 Phase 纯 docs/ + .claude/next_prompt.md;Phase 2 半成品 lib/ 改动 git checkout -- 还原)+ d_doc_index_linter F1 = 0 PASS(D147/D154/D155/D156/D157/D160/D161 全实存,加入 D162 实存)+ next_prompt_ultrathink_linter PASS(下轮含 ultrathink 关键字)+ 14 reflection 指标全继承 D161 主线 close baseline(本 Phase 不动 bootstrap/);**simplify 跳过**(纯文档改动,§After Done §1 例外 — 同 D161 Phase 0/4 / D160 Phase 0 / D157 Phase 0 / D156 Phase 0 / D154 Phase 0 / D155 Phase 0 docs-only 范式延续);**§A.2 H1-H5 假设挑战全实证锚明确**:H1 parser EXTENDS + COLON 双子句已支持 / H2 classMethodNames 已存父类 method 复用 / H3 多层 chain idempotent + visited 守 / H4 子赢 override / H5 bootstrap fixed-point;**等下轮 Phase 1 — parser 验证 extends + : 组合语法 + ≥3 case spike GREEN(class extends class + : interface 同时存在的 parser 节点验证 — nGetS2/extendsName + nGetS3/implList 双 slot 全填)— 同 D162 §Phase 1 收关锚**

- 2026-05-09 **Phase 1 parser 验证 extends + : 组合语法 + 3 case spike GREEN**(commit `<phase1-hash>` 待下轮 Phase 2 commit 即时回填)— **新建 tests/d162_class_extends_interface_impl/phase1_parser_unit_test.ss**(86 行 — Case 1 `class TestChildD162 extends TestParentD162 : TestIfaceD162` 双 slot 全填验证 nGetS2/extendsName + nGetS3/implList / Case 2 `class TestChildD162B extends TestParentD162B : TestIfaceD162B, TestIfaceD162C` 多 interface impl 验证 implList comma 分割 / Case 3 `class TestChildD162C extends TestParentD162C` 仅 extends 无 implList 兼容路径)— Phase 1 binary 下 D025 vtable check 不 walk classParents,故 Case 1-2 子类必须 re-declare interface methods 满足 D025 vtable check(临时妥协,Phase 2 修法落地后子类不必 re-declare);**RED 实测**:`ls tests/d162_class_extends_interface_impl/ = ENOENT`(测试目录与文件全无,起首必新建);**GREEN**:`bin/ss build tests/d162_class_extends_interface_impl/phase1_parser_unit_test.ss -o /tmp/d162_phase1_parser` exit 0 + `/tmp/d162_phase1_parser` 运行输出 `Tests: 3 passed, 0 failed, 3 total` exit 0(3 case 全 PASS);**§A.2 H1 实证**(parser EXTENDS + COLON 双子句解析与 class extends + interface impl 同形 — parseClassDecl line 427-441 已支持组合语法,Phase 1 spike test 编译 + 运行 exit 0 即 nSetS2(extendsName) + nSetS3(implList) 双 slot 落地的间接验证);**baseline**:bin/ss test tests/ 净 +1 file +3 case 全继承 D162 Phase 0 baseline 302/15/317(本 Phase 仅 tests/ 不动 bootstrap/lib/tools/)+ d_doc_index_linter F1 = 0 PASS(D147/D154/D155/D156/D157/D160/D161/D162 全实存)+ reflection_health_linter no regression GATE PASS(本 Phase 不动 bootstrap/ → reflection scope 不触 → 14 reflection 指标全继承 D161 主线 close baseline)+ next_prompt_ultrathink_linter 4/4 PASS(下轮 D162 Phase 2 起首含 ultrathink 关键字);**simplify 4 agent 并跑评估**(reuse / quality / efficiency / readability + readability VETO 守);**bootstrap fixed-point 不需走**(本 Phase 不动 bootstrap/ 自举无影响);**§N §6 file:line 锚**:tests/d162_class_extends_interface_impl/phase1_parser_unit_test.ss(本 Phase 新建)+ docs/3-decisions/D162-class-extends-interface-impl.md Status header [x] Phase 1 + §Phase 1 §收关锚 [x] Done at commit `<phase1-hash>` + Status 时间线 Phase 1 entry(本 entry)+ bootstrap/parse/parser.ss line 427-441 parseClassDecl EXTENDS + COLON 双子句已支持(本 Phase 不动 parser);**等下轮 Phase 2 — bootstrap/checker/check_class.ss checkInterfaceImpl walk classParents 链合并 ownMethods + parentMethods 集合修法(同 D071 checkAbstractImpl line 97 范式 + D161 §Phase 2 visited Map 防御范式)+ ≥6 case codegen spike GREEN + ./build.sh bootstrap 三阶段固定点 stage2==stage3 PASS + Phase 1 hash 即时回填 D162.md 实际语义位 4 处 — 同 D162 §Phase 2 收关锚**
