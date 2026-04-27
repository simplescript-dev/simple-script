# D140: Checker Class Method Overload by Arity 对称化

**Status:** [✓] Phase 0 落盘 at commit `e7cbe7b` + [✓] Phase 1 实施落地 at commit `a4741da` — 全 Phase 收关

**Depends on:**
- D137 §A.2 H 列(本 D 完成后回写 H8 假设破裂行)+ §核心原则 9(bootstrap 隔离)+ §F4 D138/D139/D140 编号冲突说明
- D137 §H8 实测破裂(本轮上半段 spike 锚 — `bin/ss run /tmp/spike_dual_arity.ss` 报 `error: method 'exec' expects 2 arguments, got 1`)
- D137 §核心原则 9 局部例外锚(用户对话 2026-04-27 路 (a) 授权打破 bootstrap 隔离起 sub-D 修编译器)
- D136 §R4(留 D138 sub-follow-up)+ §F1(留 D139 sub-D)— D138/D139 编号让位,本 D 取 D140
- `bootstrap/checker/check_func.ss:17-26` 既有范式(`defineFuncParams` 双 Map min/max 扩展)
- `bootstrap/checker/checker.ss:44 + 381-405` 既有范式(`funcOverloaded` map declaration + register 路径同名再 define `funcOverloaded.set`)
- `bootstrap/checker/check_exprs.ss:78-79` 既有范式(top-level function type 检查 `funcOverloaded.has(callee) == 0` 跳过)
- `bootstrap/gen/methods/gen_methods.ss:197-203` 既有范式(method overload mangling by `paramSig` 已就绪,本 D 不动)
- CLAUDE.md §项目技术规则 §Root Cause 优先 L91-103("编译器限制是 bug,不是边界条件" + "第一法则,无例外")
- CLAUDE.md §项目技术规则 §Java/TS 语法优先(method overload 是 Java/TS 主线,不借鉴 Kotlin/Scala)
- CLAUDE.md §项目技术规则 §交互式单文档(用户对话 2026-04-27 "1"+"A" 锁选 D137 候选 A → 路 (a) 启动 D140)
- `docs/3-MNK.md` §M PSM 九问 + §N VCM 六验(Plan 型 §④ 替换「替代方案对比 + 隐藏假设挑战」)+ §字段 8 "Layer 跨越触发 stop / D 文档独立审查窗口不许吞"
- `memory/feedback_root_cause_no_cost.md`(成本不是选次优的理由)
- `memory/feedback_no_derive_workaround.md`(主线能力缺口不允许 annotation 旁路)
- `memory/feedback_no_option_menu.md`(三候选论证 + 决策行,非选项菜单)

**Date:** 2026-04-27
**Last Updated:** 2026-04-27

---

## 第一性需求

`bootstrap/checker` 对 class method 注册路径与 top-level function 注册路径**不对称**:

| 项 | top-level function | class method |
|---|---|---|
| param count register | `defineFuncParams` 取 `min(existMin, minArgs)` / `max(existMax, maxArgs)` 扩展(`bootstrap/checker/check_func.ss:17-26`) | `registerMethodParams` **直接覆盖** min/max(`bootstrap/checker/check_class.ss:164-168`) |
| overloaded 检测 | `funcOverloaded.set(fname, "1")` (`bootstrap/checker/checker.ss:381-382`) | **无** `methodOverloaded` map |
| paramTypes register | `funcParamTypes.set` 仅 `funcOverloaded.has(fname) == 0` 时(`bootstrap/checker/checker.ss:389`) | `methodParamTypes.set` **总是覆盖**(`bootstrap/checker/check_class.ss:434`) |
| arg type 检查 | `funcOverloaded.has(callee) == 0` 跳过(`bootstrap/checker/check_exprs.ss:78-79`) | **无跳过分支**,`lookupMethodParamType` 永远查最后注册的 type(`bootstrap/checker/check_exprs.ss:153`) |

**Why ①(直接症状层)**: D137 §候选 A "callback 重载" 路径要求 `JdbcTemplate.execute(sql)` (1 arg) + `JdbcTemplate.execute(sql, setter)` (2 arg) 同 caller 双调用;`registerMethodParams` 直接覆盖致 checker 拿到的最后注册 paramCount = 2,1 arg 调用永远报 "method 'exec' expects 2 arguments, got 1";`lib/json.ss` 现存 `JsonNode.put(key, value: string)` / `put(key, value: int)` / `put(key, value: double)` 同 arity 不同 type overload **能工作**,机制是: codegen 层 `gen_methods.ss:197-203` `isOverloaded` + `paramSig` mangling 兜底 + 调用方碰巧传 type 与最后注册的 overload type 一致(实测: `JSON.create().put("pi", 3.14)` 走最后注册的 put(string, double),`put("ok", 1)` 靠 SS int↔double 隐式转换过 checker)— 这是**隐性 bug**,不是设计意图

**Why ②(架构成本层)**: 不修对称化 → D137 §第一性需求(Spring 层接管 prepared 路线传递业务层 SQL 注入根因解决) 永久 BLOCKED 在 Phase 1;同时 `lib/json.ss` JsonNode 既有 overload 调用方靠隐式 type 转换兜底过 checker,未来若加 `put(key, value: bool)` 等新 overload type → 同模式爆;CLAUDE.md §Java/TS 语法优先 axiom 在 method overload 上断;**根因解决是修 checker 对称化**,不是 D137 §候选 A 改成不同名(后者违反 CLAUDE.md §Root Cause "禁按工程量最小作排序依据")

**末层断言可观测否定证据**:
```bash
cat <<'EOF' > /tmp/spike_dual_arity.ss
class T {
    function exec(s: string): int { return s.length() + 100 }
    function exec(s: string, setter: fn): int { setter(this); return s.length() + 200 }
}
function main() {
    const t = new T()
    println(`one=${t.exec("hi")}`)
    println(`two=${t.exec("hi", (x: T) => { println("called") })}`)
}
EOF
bin/ss run /tmp/spike_dual_arity.ss
# 当前 RED: error: method 'exec' expects 2 arguments, got 1
# Phase 1 GREEN: one=102 + two=called/202
```

---

## 核心目标 (Goal)

- **为什么**: bootstrap/checker class method 注册逻辑与 top-level function 注册逻辑**对称化**(消除双 Map min/max 扩展 + overloaded map + type 检查跳过三处不对称)+ 解锁 D137 §候选 A "callback 重载" 路径(D137 Phase 1 续推前提)+ 修复 lib/json.ss 现存 JsonNode.put/add/get overload 调用方 type 检查窗口期破裂(隐性 bug)
- **是什么**:
  ① `bootstrap/checker/check_class.ss:164-168 registerMethodParams` 镜像 `defineFuncParams` 取 min/max 扩展;
  ② `bootstrap/checker/checker.ss` 加 `methodOverloaded` map (`"ClassName.method"` → `"1"`)+ init 调用;
  ③ `bootstrap/checker/check_class.ss:393-441` register 路径同名再 register 时 `methodOverloaded.set(...)`(注: register 之前判,与 `funcOverloaded` 在 `defineFunc` 调用之前判同范式);
  ④ `bootstrap/checker/check_class.ss:421-439 methodRetTypes.set` / `methodParamTypes.set` 在 overloaded 时跳过(参 checker.ss:389 funcOverloaded 路径);
  ⑤ `bootstrap/checker/check_exprs.ss:130-160` method arg type 检查路径加 `methodOverloaded.has(...)` 跳过分支
- **单一判据**:
  ① `/tmp/spike_dual_arity.ss` 编译 + 运行 GREEN(`one=102` + `called` + `two=202`);
  ② `/tmp/spike_overload2.ss` 同 arity 不同 type 双调用 GREEN(本 D 配套 spike,`a=102 / b=207`);
  ③ `bin/ss test tests/phase5/stdlib_json.ss` GREEN(lib/json.ss JsonNode overload baseline 不降);
  ④ `./build.sh bootstrap` 三阶段固定点 GREEN;
  ⑤ `bin/ss test tests/` 全绿 baseline 不降;
  ⑥ `tools/d_doc_index_linter.ss` F1 = 0;
  ⑦ `tools/reflection_health_linter.ss` baseline 不升

> 口号: **method 注册逻辑镜像 function — 消除 checker class/function 不对称,解锁 D137 §候选 A**

---

## 核心原则 (Principles)

1. **镜像而非新设计** — `registerMethodParams` 改造**只**镜像 `defineFuncParams` (`bootstrap/checker/check_func.ss:17-26`) 双 Map min/max 扩展;`methodOverloaded` 镜像 `funcOverloaded`;`methodParamTypes` overloaded 跳过镜像 `funcParamTypes` 跳过;不引入新结构 / 新规则 / 新 Map 类型
2. **bootstrap 改最小集** — 改动限于 `bootstrap/checker/check_class.ss` + `bootstrap/checker/checker.ss` + `bootstrap/checker/check_exprs.ss` 三文件;**不动** codegen / parser / interpreter / lib / tests / docs(除本文档 + Phase 1 完成后回写 D137 §A.2 H 列)
3. **codegen 层不改** — `bootstrap/gen/methods/gen_methods.ss:197-203` `if (isOverloaded(resolved) == 1) { sig = argsSig + funcRetTypes.has(resolved_sig) }` 路径已 method-overload-aware,本 D 只补 checker 短板,codegen 已 OK
4. **lib/json.ss 既有 overload 不破** — `JsonNode.get(string)` / `get(int)` / `put(string,string)` / `put(string,int)` / `put(string,double)` / `add(string)` / `add(int)` / `add(double)` 现存同 arity 不同 type overload 调用必须保持 GREEN(`tests/phase5/stdlib_json.ss` baseline);Phase 1 后 type 检查跳过路径让 caller 传任何 type 都过 checker(codegen 层 mangling 实际选 overload),正向修复隐性 bug
5. **D137 §核心原则 9 局部例外** — 本 D 是 D137 §核心原则 9 "bootstrap 隔离" 的局部例外,用户对话 2026-04-27 路 (a) 授权;D137 文档本体不动,D140 §核心原则 5 仅引述 D137 §核心原则 9 例外锚;Phase 1 完成后 D137 §A.2 H 列回写 H8 假设破裂行 + §F4 编号实际归属注释(D138 = D136 §R4 cache miss / D139 = D136 §F1 cross-module GEP / D140 = 本 D)
6. **双 Map min/max 范式延续** — `methodParamMin` / `methodParamMax` 已存在(`bootstrap/checker/checker.ss:36-37` + init line 79-80),只是 register 函数无扩展;镜像 `defineFuncParams` 改 register 即可,Map 本体不动
7. **不实施 D137 Phase 1** — D140 完成才回 D137 主线;D137 是 D140 的下游消费者,Phase 划分边界 = commit 边界;本 D 仅解锁能力,不顺带做 D137 Phase 1
8. **既有不变量保留** — class 继承 method override 路径(`lookupMethodParams` walk parent chain `bootstrap/checker/check_class.ss:171-184`)不动;`abstractMethods.set` 路径同步加 methodOverloaded 注册(若同名 abstract + concrete);private/protected/static 注册路径不动;codegen IR emit 顺序不动(D139 sub-D 处理);mimalloc C link axiom 例外保留

---

## 1. Context Management

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D140)
2. CLAUDE.md §项目技术规则 §Root Cause 优先 + §Java/TS 语法优先 + §交互式单文档 + §项目本质
3. `docs/3-MNK.md` §M PSM 九问 + §N VCM 六验(Plan 型 §④ 替换)+ §K 收敛循环 + §字段 8 "D 文档独立审查窗口不许吞" + §大改档位规则
4. `docs/3-decisions/D137-jdbctemplate-prepared-retcon.md` §A.2 H 列 + §F4 + §核心原则 9
5. 关键代码位置:

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/checker/check_func.ss` | 17-26 | `defineFuncParams` 双 Map min/max 扩展 — 范式参照 |
   | `bootstrap/checker/checker.ss` | 44 | `funcOverloaded` map declaration — 范式参照 |
   | `bootstrap/checker/checker.ss` | 88 | `funcOverloaded = Map()` init — 范式参照 |
   | `bootstrap/checker/checker.ss` | 381-405 | top-level function register: `funcOverloaded.set` + funcParamTypes overload-skip 路径 — 范式参照 |
   | `bootstrap/checker/check_exprs.ss` | 78-79 | top-level function arg type 检查 funcOverloaded 跳过 — 范式参照 |
   | `bootstrap/checker/check_class.ss` | 164-168 | `registerMethodParams` 直接覆盖 — Phase 1 改:取 min/max 扩展 |
   | `bootstrap/checker/check_class.ss` | 393-441 | class method register 路径 — Phase 1 改:同名再 register → `methodOverloaded.set` + retTypes/paramTypes overloaded skip |
   | `bootstrap/checker/check_class.ss` | 419 | `registerMethodParams` 调用 — Phase 1 register 之前判 overloaded |
   | `bootstrap/checker/check_class.ss` | 423 | `methodRetTypes.set` — Phase 1 overloaded 时跳过 |
   | `bootstrap/checker/check_class.ss` | 434 | `methodParamTypes.set` — Phase 1 overloaded 时跳过 |
   | `bootstrap/checker/check_exprs.ss` | 130-139 | class method arg count 检查 — 不动(`registerMethodParams` 取扩展后 min/max 自然支持双 arity) |
   | `bootstrap/checker/check_exprs.ss` | 141-160 | class method arg type 检查 — Phase 1 改:加 `methodOverloaded.has` 跳过分支 |
   | `bootstrap/checker/checker.ss` | 36-37 | `methodParamMin` / `methodParamMax` map declaration — 已存在不动 |
   | `bootstrap/checker/checker.ss` | 45 | `methodParamTypes` map declaration — 已存在不动 |
   | `bootstrap/checker/checker.ss` | 79-80 | `methodParamMin / methodParamMax = Map()` init — 已存在不动 |
   | `bootstrap/checker/checker.ss` | 87 | `methodParamTypes = Map()` init — 已存在不动 |
   | `bootstrap/gen/methods/gen_methods.ss` | 197-203 | codegen overload mangling by `paramSig` — 已就绪不动 |
   | `lib/json.ss` | 58-65 | JsonNode.get(string)/get(int) — Phase 1 baseline 不破 |
   | `lib/json.ss` | 118-152 | JsonNode.put(string,string)/put(string,int)/put(string,double) — Phase 1 baseline 不破 |
   | `lib/json.ss` | 133-172 | JsonNode.add(string)/add(int)/add(double) — Phase 1 baseline 不破 |

### Stable Facts

| 项 | 值 |
|---|---|
| 现存 method overload 实证 | `lib/json.ss` JsonNode.get(2 重载,1 arg 不同 type) / put(3 重载,2 arg 不同 type) / add(3 重载,1 arg 不同 type) |
| 不同 arity 同 caller 双调用支持 | 当前 RED(spike "expects 2 arguments, got 1") |
| codegen overload mangling | 已就绪(`gen_methods.ss:197-203`) |
| `methodParamMin/Max` Map 本体 | 已存在(`checker.ss:36-37 + 79-80`),register 函数无扩展 |
| `methodParamTypes` Map 本体 | 已存在(`checker.ss:45 + 87`),register 路径无 overloaded 跳过 |
| 反射 baseline | `tools/reflection_health_linter.ss`(本 D 不触反射) |
| d_doc_index_linter F1 | Phase 0 落盘后 D140 加入,referenced D137 实存 → F1 = 0 |

### 禁止的 Context 操作

- ❌ 改 codegen `gen_methods.ss:197-203`(已就绪,§核心原则 3)
- ❌ 改 parser(method overload 不需新语法,既有 FUNC_DECL 节点已支持)
- ❌ 改 interpreter / `eval/`(method overload 是 codegen + checker 协同,interpreter 路径走 evalMethodCall 已 OK)
- ❌ 改 `lib/`(JsonNode 等既有 overload 不动,§核心原则 4)
- ❌ 改 `tests/`(本 D Phase 1 仅加 spike 在 `/tmp/`,不入仓 tests/ — Phase 1 完成后再决定是否入 tests/phase5/)
- ❌ 起 D138 / D139(留 D136 §R4 cache miss / §F1 cross-module GEP)
- ❌ 实施 D137 Phase 1(Phase 划分边界,§核心原则 7)

---

## 2. Tool System

### 必备工具(已在环境中)

| 工具 | 用途 |
|---|---|
| `./build.sh bootstrap` | 三阶段固定点(Phase 1 后跑) |
| `bin/ss run /tmp/spike_dual_arity.ss` | spike RED→GREEN 验证(主判据) |
| `bin/ss run /tmp/spike_overload2.ss` | spike 同 arity 不同 type 双调用 |
| `bin/ss test tests/phase5/stdlib_json.ss` | lib/json.ss JsonNode overload baseline |
| `bin/ss test tests/phase5/d096_p4_l2i_class_methods.ss` | abstract method + 继承 baseline |
| `bin/ss test tests/phase5/static_method.ss` | static method baseline |
| `bin/ss test tests/` | 全测 baseline |
| `bin/ss run tools/d_doc_index_linter.ss` | D 文档治理 gate |
| `bin/ss run tools/reflection_health_linter.ss` | 反射 baseline(本 D 不触反射) |
| `bin/ss run tools/next_prompt_ultrathink_linter.ss` | next_prompt.md 必含 ultrathink |

### 禁止引入

- ❌ 新关键字 / 新语法 / 新 AST 节点(method overload 是注册逻辑改造,非语法扩展)
- ❌ 新依赖(本 D 是 bootstrap 自身改造)
- ❌ 改 codegen / parser / interpreter / lib

---

## 3. Execution Orchestration

### 总体节奏

2 Phase:
- Phase 0: 本文档落盘(本轮 Plan)
- Phase 1: bootstrap/checker 三处改 + spike GREEN + 三阶段固定点(下轮 Execute)

### Phase 详细

#### Phase 0: 本文档落盘(本轮 Plan)

- 本文档 Status `[ ]` → `[✓ Phase 0 落盘 at commit <hash>]` 当前 commit hash 回填
- 不动代码 / 测试
- `bin/ss run tools/d_doc_index_linter.ss` F1 = 0 验证
- `bin/ss run tools/next_prompt_ultrathink_linter.ss` PASS
- §After Done(simplify N/A 文档型 / commit / 下一步提示词)

#### Phase 1: bootstrap/checker 三处改(下轮 Execute)

**改动清单**(按顺序):

1. **`bootstrap/checker/checker.ss` 加 `methodOverloaded` map**:
   - line 44 后 `let funcOverloaded` 同行附近加: `let methodOverloaded = ""    // "ClassName.method" -> "1" if overloaded (skip type check)`
   - init 函数(line 88 `funcOverloaded = Map()` 同处)加: `methodOverloaded = Map()`

2. **`bootstrap/checker/check_class.ss:164-168 registerMethodParams` 镜像 `defineFuncParams`**:
   ```
   function registerMethodParams(className: string, methodName: string, minArgs: int, maxArgs: int) {
       const key = `${className}.${methodName}`
       if (methodParamMin.has(key) == 1) {
           const existMin = parseInt(methodParamMin.getString(key))
           const existMax = parseInt(methodParamMax.getString(key))
           if (minArgs < existMin) { methodParamMin.set(key, `${minArgs}`) }
           if (maxArgs > existMax) { methodParamMax.set(key, `${maxArgs}`) }
       } else {
           methodParamMin.set(key, `${minArgs}`)
           methodParamMax.set(key, `${maxArgs}`)
       }
   }
   ```

3. **`bootstrap/checker/check_class.ss:419 registerMethodParams` 调用之前判 overloaded**:
   - line 419 `registerMethodParams(...)` 调用之前加:
     ```
     if (methodParamMin.has(`${className}.${mName}`) == 1) {
         methodOverloaded.set(`${className}.${mName}`, "1")
     }
     ```
   - **必须**在 `registerMethodParams` 之前判(register 后 has 永远为真,无法区分新/再 register)

4. **`bootstrap/checker/check_class.ss:423 methodRetTypes.set` + `:434 methodParamTypes.set` overloaded 时跳过**:
   - line 422-424 `if (mRetType != "")` 改成 `if (mRetType != "" && methodOverloaded.has(`${className}.${mName}`) == 0)`
   - line 433-435 `if (mpType != "")` 改成 `if (mpType != "" && methodOverloaded.has(`${className}.${mName}`) == 0)`

5. **`bootstrap/checker/check_exprs.ss:141-160` method arg type 检查路径加 methodOverloaded 跳过**:
   - line 141 `if (recvClass != "") {` 改成 `if (recvClass != "" && methodOverloaded.has(`${recvClass}.${methodName}`) == 0) {`

**LOC 估** ~25(register 改 ~10 + Map 加 ~3 + register 路径 overload 检测 ~4 + retTypes/paramTypes 跳过 ~4 + check_exprs 跳过 ~2 + import update if 需要 ~2)

**GREEN**:
- `bin/ss run /tmp/spike_dual_arity.ss` → `one=102` + `called` + `two=202`
- `bin/ss run /tmp/spike_overload2.ss` → `a=102 / b=207`(同 arity 不同 type 双调用)
- `./build.sh bootstrap` 三阶段固定点 GREEN
- `bin/ss test tests/phase5/stdlib_json.ss` GREEN(lib/json.ss JsonNode overload baseline)
- `bin/ss test tests/phase5/d096_p4_l2i_class_methods.ss` GREEN(abstract method + 继承)
- `bin/ss test tests/phase5/static_method.ss` GREEN
- `bin/ss test tests/` 全绿 baseline 不降

### 反模式

- ❌ 改 codegen 让 method dispatch 改运行时(违反 §核心原则 3)
- ❌ 把 `funcOverloaded` / `methodOverloaded` 合并成单一 Map(混叠 namespace,看不清)
- ❌ 改 D137 文档本体内容(D140 §核心原则 5 引述 D137 §核心原则 9 例外锚即可,文档不动)
- ❌ 顺带改 D136 §R4 / §F1 cache miss / cross-module GEP(留 D138 / D139 sub-D)
- ❌ 实施 D137 Phase 1(本 D 完成才回主线,§核心原则 7)
- ❌ 改 `methodParamMin / methodParamMax / methodParamTypes` Map 本体(§核心原则 6 — 已存在不动)
- ❌ 加 D003 / D004 / D025 / D068 旧 D 文档引用(已删,F1 死指针 — 直接引 bootstrap source file:line)

---

## 4. State & Memory

### 编译时 state

- `methodOverloaded` map(新加,镜像 `funcOverloaded`)
- `methodParamMin / methodParamMax` 注册逻辑改造(扩展不覆盖)
- `methodRetTypes / methodParamTypes` 注册逻辑改造(overloaded 跳过)
- `check_exprs.ss` method arg type 检查路径(overloaded 跳过)

### 运行时 state

(N/A — 本 D 是 checker 编译时改,不影响运行时;codegen mangling 已 method-overload-aware)

### 中间产物

- `/tmp/spike_dual_arity.ss`(本轮上半段实测留底)
- `/tmp/spike_overload2.ss`(本 D 配套 spike,同 arity 不同 type)
- 三候选评估矩阵(本 D §A.1)
- 隐藏假设挑战表(本 D §A.2)

### 会话间持久化

- D140 §Phase 进度(clear 后续 Plan 锚,Status 行单一事实源)
- bootstrap 三阶段固定点 commit hash(Phase 1 回填)

### 禁止 state 操作

- ❌ 把 `methodOverloaded` 信息保存到 codegen 阶段(checker 阶段足够,codegen 已用 paramSig mangling)
- ❌ 把 `methodParamMin / methodParamMax` 改成 List / Array(Map 已就绪,Map 本体不动 — §核心原则 6)
- ❌ 把跨轮进度 / 摘要写到 handoff 文件(`.claude/next_prompt.md` 仅 terman preset 单次 payload)

---

## 5. Evaluation & Observation

### 判据(每 Phase 完成必跑)

| # | 判据 | 命令 | 期望 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` | Phase 1 后三阶段固定点 GREEN |
| 2 | spike RED→GREEN(主判据) | `bin/ss run /tmp/spike_dual_arity.ss` | Phase 0 RED("expects 2 arguments, got 1");Phase 1 GREEN(`one=102` + `called` + `two=202`) |
| 3 | 同 arity 不同 type 双调用 | `bin/ss run /tmp/spike_overload2.ss` | Phase 1 GREEN(`a=102 / b=207`) |
| 4 | lib/json.ss JsonNode overload baseline | `bin/ss test tests/phase5/stdlib_json.ss` | Phase 1 全绿 |
| 5 | abstract method + 继承 baseline | `bin/ss test tests/phase5/d096_p4_l2i_class_methods.ss` | Phase 1 全绿 |
| 6 | 全测 baseline | `bin/ss test tests/` | Phase 1 全绿不降 |
| 7 | D 治理 | `bin/ss run tools/d_doc_index_linter.ss` | F1 死指针 = 0(D140 加入未破 referenced Ds — D137 实存) |
| 8 | 反射 baseline | `bin/ss run tools/reflection_health_linter.ss` | 不升(本 D 不触反射) |

### 回归信号(任一出现 = 立即停下)

- ⚠ Phase 1 后 lib/json.ss JsonNode 任一调用红(误改 funcOverloaded / methodOverloaded 路径混叠)
- ⚠ /tmp/spike_dual_arity.ss 仍 RED(checker 改不彻底 — 漏改 check_exprs.ss type 检查跳过)
- ⚠ tests/phase5/d096_p4*.ss 红(abstract method + 继承 path 误判 overloaded)
- ⚠ bootstrap 三阶段固定点失败(checker state leak / Map init 漏)
- ⚠ 反射 baseline 升(本 D 不触反射,若升说明误改)
- ⚠ d_doc_index_linter F1 BLOCK(D140 引用 Ds 未实存 — 本 D 仅引 D136 / D137,均现存)

### 可选 spot check

```bash
# 验证 register 路径 overload 检测顺序(register 之前判)
grep -n "methodOverloaded.set" bootstrap/checker/check_class.ss
# Phase 1 后期望: register 调用之前(line < 419)

# 验证 type 检查跳过路径
grep -n "methodOverloaded.has" bootstrap/checker/check_exprs.ss
# Phase 1 后期望: line 141 附近 1 处
```

---

## 6. Constraints & Recovery

### 硬约束

- 不改 codegen `gen_methods.ss:197-203`(§核心原则 3)
- 不改 parser / interpreter(§核心原则 2)
- 不改 lib/ (§核心原则 4)
- 不改 D137 文档本体(§核心原则 5,只引述例外锚)
- 不起 D138 / D139(留 D136 §R4 / §F1 sub-D)
- 不改 codegen IR emit 顺序(D139 sub-D 处理)
- 不实施 D137 Phase 1(本 D 完成才回主线,§核心原则 7)

### 风险锚(R1-R5)

| # | 风险 | 描述 | mitigation |
|---|---|---|---|
| R1 | `methodOverloaded` 跳过太宽,JsonNode 过去精确 type 检查也跳了 | 现存 lib/json.ss JsonNode.put/add/get overload 调用方靠 type-skip 永远过(symbolic 上是隐性 bug 修复) | 实测 `tests/phase5/stdlib_json.ss` baseline 不降即可;codegen mangling 兜底所有 overload 调用方都能正确分派 |
| R2 | abstract method 注册路径漏判 overloaded | abstractMethods.set 在 registerMethodParams 之前(`check_class.ss:405-416` vs `:419`),若 abstract + concrete 同名 overloaded → methodOverloaded 注册路径要覆盖 abstract 也判 | Phase 1 register 路径 overload 检测在 `registerMethodParams` 之前;abstract method 走同 register 路径 → 同步 set methodOverloaded;`tests/phase5/d096_p4*.ss` baseline 不降 |
| R3 | parent class method 与 child class method 同名 — overload 还是 override | `lookupMethodParams` walk parent chain(`check_class.ss:171-184`),override 走 parent chain 不走 methodOverloaded;child class register 自己的 method 时,`methodParamMin.has` 限同 className 不 walk parent → 不误判 override 为 overload | register 路径用 `.has` 严格限同 className(不 lookup parent chain);override 走 lookupMethodParams parent chain 路径不变 |
| R4 | 改 `registerMethodParams` 影响 lib/json.ss 等既有 overload | `JsonNode.get(string)` / `get(int)` 同 arity 不同 type — `registerMethodParams` 改成扩展后,min=max=1 不变(都是 1 参),无副作用;但 methodOverloaded 注册后 type 检查跳过,JsonNode caller 传 type 错也不报 | bootstrap 三阶段固定点 + `tests/phase5/stdlib_json.ss` baseline;codegen mangling 兜底正确分派(spike2-7 实证 codegen layer overload 已就绪) |
| R5 | `methodOverloaded` 注册时机 | register call 之前判 vs 之后判 — 之前判保留"是否首次 register"信息;之后判 has 永远为真无法区分 | Phase 1 严格在 `registerMethodParams(...)` 调用**之前**判 `methodParamMin.has`;按 `funcOverloaded` 范式 `bootstrap/checker/checker.ss:381` `if (funcNames.has(fname) == 1) { funcOverloaded.set(...) }` 在 `defineFunc(...)` 调用之前同顺序 |

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| Phase 1 build 失败 | `git revert`;调 register 顺序 + Map init 检查 |
| Phase 1 spike_dual_arity 仍 RED | grep 找 method type 检查未跳过路径(`check_exprs.ss:141` 等) |
| Phase 1 lib/json.ss 红 | `git revert`;R1 R3 R4 重审(methodOverloaded 跳过路径过宽 / parent chain 误判) |
| Phase 1 tests/phase5/d096_p4*.ss 红 | R2 mitigation:abstract method 注册路径同步加 methodOverloaded set |
| Phase 1 d_doc_index_linter F1 BLOCK | 修引用(D140 引用 Ds 必须实存 — 本 D 仅引 D136/D137,均现存) |
| Phase 1 反射 baseline 升 | 本 D 不触反射,若升说明误改 codegen,`git reset --soft HEAD^` 回 Phase 0 |

### 回滚策略

- Phase 1 失败 → `git reset --soft HEAD^` 回 Phase 0
- Phase 0 文档已落盘,Phase 1 实施 commit 边界严格
- D140 失败回退不影响 D137(D137 §H8 BLOCKED 状态保持不变)

---

## A.1 三候选评估矩阵(Plan 型 §④ 替换:替代方案对比)

| 维度 | 候选 A(镜像 defineFuncParams + funcOverloaded)★ 选 | 候选 B(改 check_exprs method arg count 只用 minArgs) | 候选 C(codegen 后做运行时 dispatch) |
|---|---|---|---|
| 实施层 | checker 层(register + lookup 双向对称化) | checker 层(arg count 检查放宽,register 仍覆盖) | codegen + runtime(dispatch table) |
| LOC 估 | check_class ~16 + checker.ss ~3 + check_exprs ~2 + 配套 ~4 = **~25** | check_exprs ~10 = **~10** | gen_methods ~80 + runtime dispatch ~50 = **~130** |
| 根因解决度(checker 对称化) | ★★★(register + check 双向对称,消除 method 与 function 不对称) | ★(掩盖症状,register 仍覆盖,methodParamTypes 仍只记最后一个) | ★(从静态分派改运行时,反 SS 静态语言主线) |
| 第一性需求覆盖度(D137 §候选 A 解锁) | 100%(D137 Phase 1 直接解锁) | 70%(arg count 通过但 type 检查仍可能误覆盖) | 100%(但成本爆) |
| 副作用 | 低(JsonNode 既有 overload 调用方修隐性 bug;R1 mitigation 兜底) | 中(掩盖问题,未来 method overload 加更多 type 时再爆) | 高(codegen 大改,影响所有 method dispatch 路径) |
| Java/TS 主线对齐 | 高(method overload 标准 checker 实现) | 低(只查 arg count 不查 type 反 Java 主线) | 中(运行时 dispatch 偏 dynamic 语言) |
| bootstrap 影响面 | checker 三文件(register + Map + check) | check_exprs 一处 | codegen + runtime 多处 |

**决策**: **选候选 A**

**理由**:
- **根因解决度 ★★★**: register + check 双向对称化,消除 checker 层 method 与 function 的不对称;候选 B C 都不触根因
- **第一性需求覆盖度 100%**: D137 §候选 A "callback 重载" 直接解锁,业务层 SQL 注入根因解决传递到 Spring 层
- **CLAUDE.md §Root Cause "禁按 LOC 最少 排序"**: A 的 LOC ~25 不是排序依据,根因解决度 + 第一性需求覆盖度才是;A 在两项都赢,LOC 是同等的第二排序
- **副作用低**: JsonNode 既有 overload 调用方过去靠 codegen mangling 兜底过 checker(只有最后 register 的 type 能过),Phase 1 之后所有 type 都过 checker(隐性 bug 正向修复)

**为何不选 B**:
- arg count 检查放宽**只是绕过症状**,`registerMethodParams` 仍覆盖,`methodParamTypes` 仍只记最后一个 — 同 type / arity 双调用还是会爆 type 检查
- 70% 覆盖度漏掉 type 检查路径,未来 method overload 加更多 type 时再爆
- 反 Java/TS 主线(method overload 必查 type)
- **关键反驳**: B 的"LOC ~10 最少"是按工程量最小排序,违反 CLAUDE.md §Root Cause "禁按 LOC 最少作排序依据";根因不解决 → method overload 是 patch 不是真支持

**为何不选 C**:
- 130 LOC + 影响面爆(所有 method dispatch 路径改运行时)
- 反 SS 静态语言主线(SS 是 LLVM 静态编译,方法分派天然静态)
- 实施风险高(整个 codegen pass 顺序可能乱)
- **关键反驳**: C 的"100% 覆盖度"看似与 A 同等彻底,但代价是从静态语言改半 dynamic 语言,代价远超收益;CLAUDE.md §Root Cause "禁按工程量最大也最彻底" 同样不是排序依据 — 根因解决度才是,A C 同 ★★★ 但 A 实施风险显著低 → 选 A

**废案**:
- 候选 D(放弃 method overload,改 D137 §候选 B 不同名 method)— 用户对话 2026-04-27 明确路 (a) 修编译器,不路 (b) 改设计;且 lib/json.ss 现存 JsonNode 已用 method overload,放弃 → 全 lib/json.ss 重命名爆,违反 §核心原则 4

---

## A.2 隐藏假设挑战(Plan 型 §④ 替换配套)

| # | 假设 | 风险 | 验证手段 | 失败回路 |
|---|---|---|---|---|
| H1 | codegen 层 method overload mangling 已就绪(`gen_methods.ss:197-203` `isOverloaded` + `paramSig`) | 若 codegen 也不支持,checker 修了 codegen 仍崩 | 本轮上半段 spike4 实测(单 overload 调用 GREEN,b=207)+ spike5 (D137 真实布局,1+2 arity 同 method 选最后定义版调用)成功 a=202;Phase 1 实测 spike_dual_arity 双调用 | 失败 → 起 D141 sub-D 评估 codegen overload 路径 |
| H2 | lib/json.ss JsonNode.put/add/get 现存 overload 工作机制依赖 codegen mangling 兜底 | 若 checker 跳过 type 检查后,所有 caller 传 type 错过 checker 但 codegen 路径选错 overload → 运行时崩 | spike: `JSON.create().put("pi", 3.14)` 走最后注册的 put(string, double)— 调用方传 type 必须与 codegen mangling 选的 overload 一致;Phase 1 后 `tests/phase5/stdlib_json.ss` baseline 全绿验证 codegen 兜底 OK | 失败 → R1 mitigation;Phase 1 后 spot check codegen mangling 路径 |
| H3 | `methodOverloaded` 跳过 type 检查不破坏单 overload method 现有 type 检查 | 若 `methodOverloaded.has` 路径过宽,所有 method 都跳过 type 检查 → 整体类型安全降 | Phase 1 实测 `tests/phase5/static_method.ss` + `tests/phase5/d095_getter_mixed.ss` 等单 overload method type 检查仍工作(报错路径不变) | 失败 → 收紧 `methodOverloaded.has` 判定到 register 时同名再 register 二次触发(单 overload 不进 map);若仍宽 → register 路径 `methodParamMin.has` 严格判同 className |
| H4 | parent class method 与 child class method 同名不应 trigger `methodOverloaded` | override 走 `lookupMethodParams` walk parent chain;`registerMethodParams` 限同 className register | Phase 1 实测 `tests/phase5/d096_p4*.ss`(class 继承 + 方法 override)baseline 不降 | 失败 → register 路径 `.has` 严格限同 className,parent chain walk 移到 `lookup`;若仍误判 → 加 `parentName != ""` 判定保守化 |
| H5 | `abstractMethods` 注册路径与普通 method 注册路径同 register | `abstractMethods.set` 在 `registerMethodParams` 之前(`check_class.ss:405-416` vs `:419`),走同函数;Phase 1 同步加 `methodOverloaded` 注册即可,abstract method 走同 path | grep `abstractMethods.set` 路径与 `registerMethodParams` 同函数;Phase 1 同步加 `methodOverloaded.set` 在 register 之前 | 失败 → R2 mitigation;abstract method 单独 set methodOverloaded |
| H6 | bootstrap 三阶段固定点验证可靠 | bootstrap 自身 lib/json.ss / 其他 lib 用 method overload — 若 D140 改 checker 后 bootstrap 编译 lib 自身崩 | bootstrap 三阶段固定点(seed→stage1→stage2→stage3)严格;固定点失败 = bootstrap 自身崩 | 失败 → `git reset` → R1 R3 R4 重审 |
| H7 | `funcOverloaded` 范式适合 mirror 到 method | `funcOverloaded` 是 SSoT,但 method 注册路径有 className prefix + parent chain 需求;直接 mirror 可能不够 | 范式 mirror + className prefix 已 cover 需求(spike4-7 实证 codegen mangling 已支持 className.method namespacing) | 失败 → 加 className 路径限定到 register / lookup |

---

## Followup

| # | 锚 | 描述 |
|---|---|---|
| F1 | D137 §A.2 H8 假设破裂回写 + §F4 编号实际归属 | D140 Phase 1 完成后,在 D137 §A.2 H 列补 H8 行(class method overload by arity checker 不对称破裂记录,实测命令 + Phase 1 fix commit hash 锚)+ §F4 D138/D139/D140 编号实际归属注释(D138 = D136 §R4 cache miss / D139 = D136 §F1 cross-module GEP / D140 = 本 D)— 留 D 治理后续轮处理 |
| F2 | D138(D136 §R4)prepared statement cache miss | sub-D 评估 — server 重启后 statement_id invalid → driver 重新 prepare;依赖 ER_UNKNOWN_STATEMENT_HANDLER 检测;本 D 范围外 |
| F3 | D139(D136 §F1)cross-module struct GEP | sub-D 评估 — codegen IR emit 顺序改造(类型声明先于函数体),解决 lib/com/mysql/query.ss columnDefColType / columnDefName 包装绕道;影响面整个 codegen pass;本 D 范围外 |
| F4 | D137 Phase 1-4 续推 | D140 完成后回 D137 主线,按 D137 §核心目标 + Phase 划分继续(spring/jdbc.ss 5 callback 重载实施 → spring/data.ss 11 处 retcon → tests/d134_mysql 8 case retcon → e2e 闭环) |
| F5 | method overload by 同 arity 不同 type 一致性 | 当前 D140 范围 = 同 arity / 不同 arity 都 cover;若未来需要更精确 type 匹配(JsonNode 范式 + method 重载分派),codegen mangling 已就绪,checker 同步对称即可;本 D 范围内已 cover |
| F6 | constructor overload 是否同步对称化 | classConsMin / classConsMax(`check_class.ss:382-383`)是 constructor param count 注册;构造函数 overload 当前未支持;若未来需要(类似 JsonNode 多 overload 构造场景),按 D140 范式延展即可;本 D 范围外 |

---

## Phase 收关锚

### Phase 0: D 文档落盘 [✓] Done at commit `e7cbe7b` (2026-04-27)

- 本文档 Status [✓] Phase 0 落盘 at commit `e7cbe7b`
- d_doc_index_linter F1 = 0 验证 PASS(referenced D 文档 D136/D137 实存,F2 soft warn 14 orphan 含 D140 不阻 commit)
- next_prompt_ultrathink_linter PASS(本轮 next_prompt.md 含 ultrathink 关键字)

### Phase 1: bootstrap/checker 三处改 [✓] Done at commit `a4741da` (2026-04-27)

- bootstrap/checker/checker.ss line 47 + 90: + `methodOverloaded` map declaration + `initChecker` 初始化(镜像 funcOverloaded line 44 + 86)
- bootstrap/checker/check_class.ss line 164-175: `registerMethodParams` 取 min/max 扩展(镜像 defineFuncParams line 17-26)
- bootstrap/checker/check_class.ss line 426-431: `registerCheckerClassDecl` register 之前判 `methodParamMin.has` → `methodOverloaded.set`(register call 之前判,与 funcOverloaded.set 在 defineFunc 之前判同顺序)
- bootstrap/checker/check_class.ss line 433 + 437: `methodRetTypes` / `methodParamTypes` overloaded 时跳过(镜像 funcParamTypes line 389)
- bootstrap/checker/check_exprs.ss line 140-141: METHOD_CALL 路径 type 检查加 `methodOverloaded.has` 跳过(镜像 funcOverloaded line 78-79)
- spike GREEN(主判据): `bin/ss run /tmp/spike_dual_arity.ss` → `one=102` + `called` + `two=202`(D140 §第一性需求 末层断言)
- spike GREEN(配套 ②): `bin/ss run /tmp/spike_overload2.ss` → `a=102 / b=207`(同 arity 不同 type 双调用)
- `./build.sh bootstrap` stage2 == stage3 byte-identical 固定点 PASS
- `bin/ss test tests/` 259/4/263 与 baseline 完全一致(0 D140 回归;4 pre-existing fail: spring_web_params/d096_p4_l2_reactive/harness_task/harness_bug 不变)
- `bin/ss test tests/phase5/stdlib_json.ss` GREEN(JsonNode.put/add/get 同 arity 不同 type 既有 overload baseline 不破)
- `bin/ss test tests/phase5/d096_p4_l2i_class_methods.ss` GREEN(abstract method + 继承 baseline 不破)
- d_doc_index_linter F1 = 0 + reflection_health_linter GATE PASS — no regressions
- simplify 采纳: check_exprs.ss:140 注释去 "D140:" 前缀镜像 line 78 风格("non-overloaded methods only")
- D137 §候选 A "callback 重载" 路径解锁,D137 Phase 1(lib/spring/jdbc.ss 5 method callback 重载实施)下轮可启动

---

## D140 全 Phase 收关锚

[✓] Phase 0 D 文档落盘 at commit `e7cbe7b` (2026-04-27)
[✓] Phase 1 bootstrap/checker 三处改实施 at commit `a4741da` (2026-04-27)

**总收关**: D140 主线全 2 Phase 落地,checker class method 注册逻辑与 top-level function 注册逻辑**对称化**完成 — 消除 register / type 检查路径双 Map min/max 扩展 + overloaded map + type 检查跳过三处不对称,主判据 spike_dual_arity GREEN + 配套 spike_overload2 GREEN + bootstrap 三阶段固定点 + 全测 baseline 不降 + 双 linter gate PASS。

**下游解锁**: D137 §候选 A "PreparedStatementSetter callback 重载" 路径(D137 Phase 1 lib/spring/jdbc.ss 5 method callback 重载 + Phase 2 lib/spring/data.ss 11 处 retcon + Phase 3 tests/d134_mysql/ 8 case retcon + Phase 4 e2e 闭环)主线打开,业务层 SQL 注入根因解决传递到 Spring 层路径就绪。

**隐性 bug 正向修复**: lib/json.ss JsonNode.put/add/get 同 arity 不同 type 既有 overload 调用方过去仅靠 codegen mangling + SS int↔double 隐式转换兜底过 checker(checker 只记最后注册的 type,其他 type 调用错位),Phase 1 后 type 检查正确跳过,所有 type 调用方按 codegen mangling 真实分派(实证 tests/phase5/stdlib_json.ss baseline 不破)。

**Followup F1 留下轮**: D137 §A.2 H 列 H8 假设破裂行回写 + §F4 D138/D139/D140 编号实际归属注释(留 D 治理后续轮处理,见 D140 §Followup F1)。
