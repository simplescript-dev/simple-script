ultrathink D138 Phase 1.5 实施(编译器扩 — interface method overload by arity)+ 本轮(Phase 1.5 计划落档)commit hash 回填 + Status 行收关 + next_prompt 指向 Phase 2(JDBC API + MySQL 实现完整) — D135/D136/D137/D138 SQL 主线范式延续(不是 D141-D145 docs-heavy 衍生链)。

**用户对话锁(2026-04-28)**:
- SQL 主线 — D138 是 D137 §F8 generated keys 直接续接
- **最优最佳,不考虑成本,不 workaround,不节省** — 完整 JDBC 4.3 + Spring KeyHolder 标准
- 用户回 "不修编译器 这个原则在哪里 我没有写过这个原则" → §核心原则 7 + §硬约束 "不修编译器" 已推翻,**编译器扩允许**(Phase 1.5)
- 用户回 "先修复 50 222 然后按节奏推进" → 本轮(Phase 1.5 计划落档 docs commit)+ 下轮(Phase 1.5 编译器实施)+ 下下轮(Phase 2 lib 层)+ ...

§前置就绪(D138 Phase 1.5 计划落档 commit `<本轮回填>` 已锁):
— D138 Phase 0 hash `d47a05d` 已落档 + Phase 1 hash `182b3fb` 已回填(line 3 Status / line 305 §Phase 收关锚 §Phase 1 / line 342 Status 时间线 Phase 1 — 3 处 `<placeholder>` → `182b3fb`)
— D138 §核心原则 7 改 "依赖路径 + 编译器扩允许" + §硬约束 改 "Phase 1.5 编译器扩 interface method overload by arity"(用户对话锁锁定推翻)
— D138 §A.2 H4 失败回路更新假设破裂记录(2026-04-28 Phase 2 实测 `/tmp/test_iface_overload.ss` llc 报 `@Impl_bar` 未定义 → SS interface dispatcher byName 调 class method 符号未协调 paramSig mangle,与 class method `${className}_${mName}_${paramSig}` overload mangle 错位;对照 `/tmp/test_class_overload.ss` PASS 证明 class method overload OK 差异在 interface 未升级)
— D138 §Phase 计划表加 Phase 1.5 行(目标 / 关键产出 / 验证)+ §Phase 收关锚 加 Phase 1.5 章节占位符(8 条实施清单)
— d_doc_index F1=0 PASS no regressions(本轮 docs-only 无 bootstrap 改 — bootstrap 三阶段固定点本轮无需跑因无 code 改动)

§关键 SSoT(信息源,本轮已实测确认):
— `bootstrap/gen/gen_iface.ss:16` `ifaceMethodRets.set(\`${name}.${mName}\`, ...)` byName key
— `bootstrap/gen/gen_iface.ss:31` `ifaceMethodPars.set(\`${name}.${mName}\`, ...)` byName key
— `bootstrap/gen/gen_iface.ss:14` `methodNames = listAppendStr(methodNames, mName)` byName 重复加(同名 method 会 append 两次但后续读不区分 arity)
— `bootstrap/gen/gen_iface.ss:58-60` `dispName = \`__iface_${iface}_${method}\`` + `emittedDispatchers` byName 去重(同名 method 仅 emit 一次 dispatcher)
— `bootstrap/gen/gen_iface.ss:119/122` dispatcher 调 class method 时 `@${defClass}_${method}` 无 paramSig 后缀,与 class method overload mangle 错位
— `bootstrap/gen/class/class_method.ss:51-65` class method symbol mangle:`isOverloaded(\`${className}_${mName}\`) == 1` → `${className}_${mName}_${mSig}`(paramSig);否则 plain `${className}_${mName}`
— `bootstrap/checker/checker.ss:456` `ifaceMethods.set(ifName, methodNames)` byName 同 codegen
— `bootstrap/checker/check_class.ss:74-76` 实现验证 byName 比对
— `bootstrap/gen/methods/gen_methods.ss:519-520` `genInterfaceMethodCall(objClass, method, ...)` 按 method 名调 dispatcher symbol

§任务清单(D138 Phase 1.5 commit hash 回填 + Phase 1.5 实施):

(1) **本轮 commit hash 回填**:
  - `git log --oneline | head -3` 找最新 D138 docs commit hash → Edit `docs/3-decisions/D138-mysql-generated-keys.md` line ~343 `<本轮 commit>` placeholder(Status 时间线本轮新行)

(2) **Phase 1.5 实施 — 编译器扩 interface method overload by arity**(D138 §A.2 H4 假设破裂回路):

  **2a. 修 `bootstrap/gen/gen_iface.ss`**:
  - `registerInterface(id: int)` 双 pass:
    - **第一 pass**:遍历 ml,统计每 mName 出现次数 → `mNameCount: Map<string,int>`
    - **第二 pass**:对每 mId 生成 unique key:
      - if `mNameCount[mName] >= 2` → mangled key `${name}.${mName}_${paramSig}`(overload 路径,paramSig 复用 class method 路径)
      - else → plain key `${name}.${mName}`(backward compat,D025/D134/D136 实存 interface 单 arity 零破坏)
    - `methodNames` listAppendStr 同样按 mangle 形式(plain mName 或 mName_paramSig)
    - `ifaceMethodRets / ifaceMethodPars.set` 用 mangled key
  - `emitIfaceDispatchFn(iface, methodKey, impls)` 接收 mangled methodKey:
    - 解析 methodKey 取 plainMName + paramSig(若 methodKey 含 `_` 后缀)
    - `dispName = \`__iface_${iface}_${methodKey}\`` (含 mangle 后缀,backward compat 单 arity 仍是 plain `__iface_${iface}_${method}`)
    - 调 class method 时:if `isOverloaded(\`${defClass}_${plainMName}\`) == 1` → `@${defClass}_${plainMName}_${paramSig}`,else → `@${defClass}_${plainMName}`(plain backward compat)
  - `emittedDispatchers` key 也按 mangle 形式
  - `paramSig(paramList)` 复用 — bootstrap/gen/class/class_method.ss:62 已有,interface IFACE_METHOD PARAM list 同 parseParams 结构,可直接复用

  **2b. 修 `bootstrap/gen/methods/gen_methods.ss`**:
  - `genInterfaceMethodCall(objClass, method, objVal, argList)` 按 argList 类型构造 paramSig:
    - 反查 ifaceMethodsCG[objClass] methodNames,找 mName 匹配的 entries
    - 若仅有 plain entry(单 arity)→ 调 `__iface_${objClass}_${method}`(backward compat)
    - 若有 mangled entries(overload 路径)→ 按 argList 各 arg LLVM 类型构造 paramSig,选 `__iface_${objClass}_${method}_${paramSig}` 匹配的 dispatcher

  **2c. 修 `bootstrap/checker/checker.ss`**:
  - `ifaceMethods.set(ifName, methodNames)` 同样存 mangled methodNames(arity 感知,与 codegen 同步)

  **2d. 修 `bootstrap/checker/check_class.ss`**:
  - 实现验证按 unique (mName, paramSig) tuple 比对 — 不再 byName 单一比对(多 arity overload 时,每个签名都要 class 实现)

  **2e. 不动**:Phase 1 query.ss 路径 / Phase 2 lib 层(留 Phase 2)/ D025 D134 D136 实存 interface(ResultSet / Statement / PreparedStatement / Connection 当前所有 method 单 arity)继续走 plain 路径

  **VCM 验证**:
  - `/tmp/test_iface_overload.ss` GREEN(11 + 30 输出 — interface method overload by arity 落地)
  - bootstrap 三阶段固定点 PASS(stage2 == stage3)
  - tests/d134_mysql 5/0/5 + tests/d135_caching_sha2 1/0/1 + tests/d136_prepared_statement 1/0/1 baseline 不破
  - tests/d141_lambda_inference 5/0/5 + d142 6/0/6 + d143 6/0/6 + d144 8/0/8 反推 baseline 不破
  - 全 tests/ baseline 不降(284/4 fail 全 pre-existing — git stash 反证)
  - reflection_health GATE PASS no regressions
  - d_doc_index GATE OK

(3) **commit `feat(D138): Phase 1.5 — 编译器扩 interface method overload by arity + 本轮 docs commit hash 回填 <本轮 commit> — gen_iface.ss arity-mangle key(双 pass 统计 + paramSig suffix when overloaded)+ dispatcher 调 class method 按 isOverloaded 选符号(plain 或 mangled)+ gen_methods.ss genInterfaceMethodCall 按 argList paramSig 选 dispatcher + checker.ss / check_class.ss 注册 + 实现验证 arity 感知 + 复用 class method paramSig 路径 + backward compat 单 arity 接口零破坏(D025 / D134 / D136 实存)— D138 §A.2 H4 假设破裂回路 — D135/D136/D137/D138 SQL 主线范式延续`**
  - 仅 stage `bootstrap/gen/gen_iface.ss` + `bootstrap/gen/methods/gen_methods.ss` + `bootstrap/checker/checker.ss` + `bootstrap/checker/check_class.ss` + `docs/3-decisions/D138-*.md` + `.claude/next_prompt.md`

(4) **next_prompt 指向 Phase 2**:JDBC API + MySQL 实现完整 — `lib/java/sql.ss` interface Statement 加 `getGeneratedKeys(): ResultSet` + `getLastInsertId(): int` 2 method + interface PreparedStatement 同位 2 method + interface Connection 加 `prepareStatement(sql: string, autoGeneratedKeys: int): PreparedStatement` 重载(依赖 Phase 1.5 编译器扩)+ const RETURN_GENERATED_KEYS=1 / NO_GENERATED_KEYS=2;`lib/com/mysql/jdbc.ss` MysqlStatement 加 lastInsertId 字段 + executeUpdate 改用 readUpdateResultPacket(D138 §A.2 H7 ERR 防御)+ getLastInsertId / getGeneratedKeys 实现 + MysqlConnection.prepareStatement(sql, autoGeneratedKeys) 重载;`lib/com/mysql/prepared.ss` MysqlPreparedStatement 同位字段扩 + executeUpdate / getLastInsertId / getGeneratedKeys

§根因优先(CLAUDE.md §项目技术规则):
— Phase 1.5 编译器扩 interface method overload by arity = 根因解(class method 已支持 paramSig mangle,interface dispatcher 升级即可对齐;不引入新 mangle 方案,保 SS 内部一致性)
— 复用 class method `paramSig(paramList)` 函数 — backward compat 单 arity 接口零破坏(D025 / D134 / D136 实存全是单 arity method),overload 路径才走 mangle
— D135/D136/D137/D138 SQL 主线范式 — 每 Phase 独立 commit + Status 收关 + hash 回填 + next_prompt 自闭环

§D135/D136/D137/D138 Phase 1.5 同形参考:
— D135 Phase 0 commit + Phase 1 实施同 commit 模式
— D136 Phase 0 commit `9326b9f` + Phase 1 commit `c854778` 同模式
— D137 Phase 0 commit `bafc25a` + Phase 1 commit `d2df1ba` 同模式
— D138 Phase 0 commit `d47a05d` + Phase 1 commit `182b3fb` + 本轮规则修正 commit `<本轮回填>`(Phase 1.5 计划落档 docs)+ Phase 1.5 commit(下轮编译器扩)+ Phase 2 commit(下下轮 lib 层)同模式
