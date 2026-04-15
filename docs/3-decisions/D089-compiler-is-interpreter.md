# D089: Compiler = Interpreter 统一架构

**Status:** Phase 0–7 全部完成（Phase 7 commit `4b52c91`）— 单一判据达成：加新语法只改 codegen 一处
**Depends on:** D088 (comptime Zig route)
**Date:** 2026-04-13
**Last Updated:** 2026-04-14

---

## 核心目标 (Goal)

- **为什么**：SS 当前有 codegen + interpreter 两套实现，加新语法要改两处，会漂移。
- **是什么**：让 codegen 自身具备求值能力，消除独立解释器。
- **单一判据**：加新语法只改 codegen 一处。

> "1 处 → 在路线上。2 处 → 没改到位。"

---

## 核心原则 (Principles)

1. **操作级 comptime 传播** — 看操作数，不看全局 mode flag（Zig 模型）
2. **comptime 性质自底向上** — 字面量天然 comptime，逐层冒泡
3. **comptime/runtime 边界显式 materialize** — 不隐式转换
4. **逐 Phase 迁移** — 每步 bootstrap 固定点 + 全量测试，禁大爆炸
5. **旧实现作 fallback** — 所有功能迁完才删，从不"先删后补"
6. **不绑无关重构** — 如 `nextReg` 类型独立成 D091，不混入 D089
7. **`genExpr` 做 wrapper** — 调用点零改动，内部腾挪

---

## 1. Context Management（上下文管理）

> clear 后的 Claude 动手前 5 分钟内必须加载完本节内容。

### 必读清单（按顺序）

1. **本文档 D089** — 核心计划 + 当前状态
2. **CLAUDE.md** — 项目铁律（语法约束、根因优先、交互式单文档）
3. **docs/3-decisions/D088-comptime-zig-route.md** — 依赖（comptime Zig 路线）
4. **关键代码位置**：

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/codegen.ss` | 106-144 | Tagged value 基础设施（`ctVal`/`isCt`/`payload`/`reg`/`materialize`） |
   | `bootstrap/gen_exprs.ss` | 97-213 | `genVal()` — 唯一 expression dispatcher（Phase 7 后单一入口） |
   | `bootstrap/gen_exprs.ss` | ~1218-1220 | `genExpr` wrapper（`return reg(genVal(id))`） |
   | `bootstrap/interp.ss` | 1-402 | comptime value/scope/buffer 核心 |
   | `bootstrap/gen_reflect.ss` | 全文件 | 反射（Phase 6 Step 4 从 `interp_reflect` 迁入） |

5. **Phase 7 4 个 commit**（用 `git log --oneline` 验证）：
   - `4da97a2` Step 1 — 6 个叶子 kind 直接 dispatch
   - `2d0b148` Step 2 — 4 个 call 类节点
   - `a9b5d3c` Step 3 — 4 个复合 kind
   - `4b52c91` Step 4 — 删除 `genExprOld` + `genTernary`

### Stable Facts（Live Repo Context）

| 项 | 值 |
|---|---|
| 当前阶段 | Phase 7 完成，D089 全部收尾 |
| 测试基线 | 219 个 `.ss` 文件全通过 |
| bootstrap 入口 | `./build.sh bootstrap` |
| bootstrap 耗时 | 2-3 分钟（每次必跑） |
| 测试入口 | `bin/ss test tests/` |
| `genExpr` 调用点 | 112（wrapper，保持不变） |
| `genVal` 调用点 | 51+（Phase 7 dispatch 全在 genVal 内） |
| `nextReg` 调用点 | 376（D091 范围，未动） |
| `genExprOld` 调用点 | 0（已删除） |

### 禁止的 Context 操作

- ❌ 扫描 `docs/3-decisions/` 找未完成决策自己挑活儿（违反 CLAUDE.md "交互式单文档"）
- ❌ 读取 `docs/5-handoff/`（已删除，commit `278f34c`）
- ❌ 顺带修无关文件
- ❌ 改 `CLAUDE.md` / `docs/1-axioms.md` / `docs/2-principles.md`（D089 范围外）

---

## 2. Tool System（工具系统）

### 必备工具（已在环境中）

| 类别 | 工具 / 命令 | 用途 |
|---|---|---|
| Claude 内置 | `Read` / `Edit` / `Grep` / `Glob` / `Bash` | 文件操作、搜索 |
| 构建 | `./build.sh bootstrap` | 三阶段固定点验证（必跑） |
| 编译单文件 | `bin/ss build file.ss -o out` | 验证特定测试 |
| 全量测试 | `bin/ss test tests/` | 223/223 必通过 |
| IR 检查 | `bin/ss build x.ss --emit-ir` | 验证常量折叠 |
| Git | `git log --oneline -10`、`git diff`、`git status` | 追踪进度 |
| 质量审查 | Skill `/simplify` | commit 前必跑 |

### 外部依赖（系统级，不动）

`llc-18`、`musl-gcc`、`vendor/mimalloc.o`（`build.sh` 自动管理）

### 禁止引入

- ❌ 新 C 库 / Cargo crate / npm 包（feedback: `pure_ss`）
- ❌ 修改 `build.sh` 流程
- ❌ 新关键字（feedback: `no_new_keywords`）
- ❌ Kotlin/Scala 风格语法（feedback: `no_kotlin_syntax`）
- ❌ Result<T,E> + ? operator（feedback: `no_rust_result`）

---

## 3. Execution Orchestration（执行编排）

### 总体节奏

- Phase 7 = **4 个 Step 顺序执行**
- 每个 Step **独立 commit**
- 每个 Step **必须 bootstrap 通过**才进下一步（硬约束，违反 = 回滚）
- **禁止"边迁移边重构"**

### 单 Step 内的循环（硬约束）

```
1. Read    bootstrap/gen_exprs.ss 当前 genVal() (line 139)
2. Edit    加上目标 expression kind 的 dispatch 分支
3. Bash    ./build.sh bootstrap   (等 2-3 分钟)
4. 失败    → 看错误 → 修 → 回 step 3
5. Bash    bin/ss test tests/
6. 全绿    → Skill /simplify → git commit
7. 失败    → git reset --soft HEAD^ → 回 step 2
```

### Phase 7 Step 详细

#### Step 1：叶子节点 + 简单 dispatch（6 个 kind）

- `THIS` / `SUPER` → `constVal(genThisExpr())`
- `IDENT` runtime 分支 → `constVal(genIdent(id))`（comptime 分支已在 `genVal:154`）
- `POSTFIX_INC` → `constVal(genPostfixExpr(id))`
- `DOUBLE_LIT` runtime 分支 → `constVal(nGetS1(id))`（comptime 分支已在 `genVal:147`）
- `COMPTIME_EXPR` runtime 分支 → 复用 `comptimeExprLiteral.getString` 缓存逻辑
- **验证**：bootstrap 固定点 + 223 测试通过

#### Step 2：调用类节点（4 个 kind）

- `CALL` runtime 分支 → `constVal(genCall(id))`
- `METHOD_CALL` runtime 分支 → 区分 `nGetI3(id) > 0`（optional chain）→ `genOptionalMethodCall` / `genMethodCall`
- `MEMBER_ACCESS` runtime 分支 → 同上 optional chain 分支
- `NEW_EXPR` runtime 分支 → `constVal(genNewExpr(id))`
- **验证**：bootstrap 固定点 + 223 测试通过

#### Step 3：复合节点（4 个 kind）

- `TEMPLATE_LIT` runtime 分支 → `constVal(genTemplateLit(id))`
- `ARRAY_LIT` runtime 分支 → `constVal(genArrayLit(id))`
- `ARROW_FUNC` runtime 分支 → `constVal(genArrowFunc(id))`
- `INDEX_ACCESS` runtime 分支 → `constVal(genIndexAccess(id))`
- **验证**：bootstrap 固定点 + 223 测试通过

#### Step 4：删除 `genExprOld` + fallback

- 删除 4 处 `return constVal(genExprOld(id))` fallback（`gen_exprs.ss:207/249/258/286`）
- 删除 `function genExprOld(id: int): string` 函数本体（~40 行）
- 删除 `genExprOld(nGetI1(id))` 在 GROUPING/NAMED_ARG 处的两个内部递归（line 122/129），改为 `genVal` + `reg`
- 把 `genVal()` 末尾的 `return constVal("0")` 改为 `println("[genVal] unknown kind: " + kind); return constVal("0")` 防御兜底
- **验证**：bootstrap 固定点 + 223 测试通过 + `grep -rn genExprOld bootstrap/` 返回 0

### 反模式

- ❌ 4 个 Step 合 1 个大爆炸（违反"逐 Phase 迁移"原则）
- ❌ 同时改 `nextReg()` 类型（**已驳回，见 D091 — 数据驱动关闭，0.04% 收益天花板。本行保留作为反诱饵：D 文档脚注里的"独立后续"永远不是路线指引**）
- ❌ 顺带 refactor / 修无关 bug（违反 `interactive_one_doc`）

---

## 4. State & Memory（状态与记忆）

### 编译时 state（in-memory，bootstrap 重建）

| 变量 | 文件 | 角色 |
|---|---|---|
| `regTable: Array<string>` | `codegen.ss` | 寄存器名 + 常量字符串表 |
| `comptimeDepth: int` | `gen_exprs.ss` | > 0 走 comptime，= 0 走 runtime |
| `ctVars: Map` | `gen_exprs.ss` | comptime 作用域（key = `scopeId:name`） |
| `ctScopeStack` | `gen_exprs.ss` | comptime 作用域栈 |
| `comptimeIR / comptimeSS` | `interp.ss` | comptime emit 缓冲区 |
| `interpClasses / EnumNodes / MapEntries` | `interp.ss` | comptime 注册表 |
| `interpReturnFlag / BreakFlag / ContinueFlag` | `interp.ss` | comptime 控制流 flag |

### bootstrap 中间产物

- `bootstrap-build/stage1` — seed 编译 stage1
- `bootstrap-build/stage2` — stage1 编译 stage2
- `bootstrap-build/stage3` — stage2 编译 stage3
- **验证规则**：`stage2 == stage3`（固定点）

### 会话间持久化（clear 后还在的）

- `git log` — 所有进度（实施日志的真相源）
- **本文档 D089** — 唯一计划 / 状态记录
- `tests/phase5/comptime_*.ss` — 35 个行为契约
- `bin/ss` — 当前 stage3 二进制（最新固定点产物）

### 禁止的 state 操作

- ❌ 写 `next-prompt.md` / `handoff.md` / `notes.md` / `analysis.md`（CLAUDE.md 硬规则，commit `278f34c` 已彻底移除）
- ❌ amend 已 push commit（始终 new commit）
- ❌ 把状态写到对话 / D089 / git 之外的任何位置

---

## 5. Evaluation & Observation（评估与观测）

### 4 个判据（每 Step 完成必跑）

| # | 类型 | 命令 / 检查 | 通过条件 |
|---|---|---|---|
| 1 | 架构判据（人工） | review：加新语法是否只改 codegen 一处？ | 是 |
| 2 | 工程判据（命令） | `./build.sh bootstrap` | `stage2 == stage3` |
| 3 | 测试判据（命令） | `bin/ss test tests/` | 223/223 通过 |
| 4 | 收敛判据（命令，Phase 7 末） | `grep -rn genExprOld bootstrap/` | 0 命中 |

### 回归信号（任一出现 = 立即停下）

- ⚠ bootstrap 报 `stage2 != stage3` → 编译器引入了非确定性
- ⚠ 任意 `tests/*.ss` 失败 → 行为漂移
- ⚠ IR 中出现意外 `add i32`（在 comptime 折叠路径）→ 常量折叠失效
- ⚠ stderr 出现 `[comptime] unsupported expression: X` → `genVal` 漏 dispatch 第 X kind

### 可选 spot check 命令

```bash
# 验证常量折叠
bin/ss build x.ss --emit-ir | grep "add i32"

# 验证 interp.ss 行数（Phase 6 Step 5 后应 ≈ 402）
wc -l bootstrap/interp.ss

# 验证 genVal 调用点（Phase 7 后应 > 51）
grep -c genVal bootstrap/gen_exprs.ss

# Phase 7 收敛判据
grep -rn genExprOld bootstrap/
```

### 功能验证脚本（嵌入测试集）

Phase 2 完成后 — IR 验证常量折叠：
```ss
function main() {
    const x = 1 + 2    // 不应出现 add 指令
    println(x)
}
```

Phase 3 完成后 — comptime 控制流：
```ss
const r = comptime {
    let sum = 0; let i = 0
    while (i < 5) { sum = sum + i; i = i + 1 }
    return sum
}
assertEqual(r, 10)
```

Phase 4 完成后 — comptime 块内 class：
```ss
const r = comptime {
    class Point { x: int; y: int }
    const p = new Point(x: 3, y: 4)
    return p.x + p.y
}
assertEqual(r, 7)
```

---

## 6. Constraints & Recovery（约束与恢复）

### 硬约束（违反 = 立即回滚）

- 不引入 Kotlin/Scala 语法（CLAUDE.md "Java/TS 优先"）
- 不做 workaround，根因修（user feedback `no_workaround`）
- 不写 `handoff` / `next-prompt` 文件（CLAUDE.md `no_handoff_drift`）
- 每个 Step 独立 commit + bootstrap 通过
- 不 amend 已 push commit
- 编译器 bug 立即停下修，不绕行

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| `bootstrap stage2 != stage3` | `git reset --soft HEAD^`；二分查 diff；查非确定性源（Map 遍历顺序、未初始化变量） |
| `tests/X.ss` 失败 | 读 X 源码理解期望；**不改测试**；修 codegen |
| `genVal` 漏 kind | 在 `genVal` 加 dispatch；防御 `println` 已在 |
| 死循环（runtime cond at CT） | `Ctrl-C`；`git reset`；检查 `comptimeDepth` 边界 |
| `nextReg` 类型冲突 | 立即停；这是 **D091 范围**，不在 D089 内修 |
| `/simplify` 提示有 dead code | 当前 Step 内消除，不留到下 Step |
| Bash 工具 timeout | 检查是否进了 REPL/交互模式；杀进程；不靠重试 |

### Phase 7 内部回滚策略

- 任何 Step 失败 → `git reset --soft HEAD^` 回上一 Step
- 禁止"先 commit 再修"
- 禁止跨 Step 的 partial state（每 Step 必须独立完整）
- 跨 Phase 回滚（如 Phase 7 → Phase 6）需先和用户确认 — Phase 边界是稳定锚点

### 升级判据（Anthropic "每升级模型必拆 harness"）

模型升级（如 Opus 4.6 → 5）时，本文档需要复审：
- "反模式" / "禁止" 列表是否还成立？（可能新模型自己能避免）
- "约束与恢复" 是否过度防御？
- 删除已不必要的 scaffolding，**不维护无用约束**

---

# 附录 A: 决策细节

## A.1 问题

SS 有两套语言实现：

```
codegen (gen_*.ss)        → 每个 AST 节点 → 发射 LLVM IR
interpreter (interp_*.ss) → 每个 AST 节点 → 直接求值
```

每加一个语言特性，改两处。两套代码可能漂移。这不是"compiler = interpreter"，是"compiler + interpreter"。

D088 定义的 Zig 路线本质是"编译器即解释器"——一套代码。当前实现是表面模拟。

## A.2 决策

**消除独立解释器。让 codegen 自己具备求值能力。**

### A.2.1 Tagged Value

`genExpr` 目前返回 `string`（LLVM 寄存器名如 `"%42"`）。改为返回 **tagged int**：

```
bit 30 = 1 → comptime（编译期已知值），bits 0-29 = 解释器值 ID
bit 30 = 0 → runtime（运行时值），bits 0-29 = 寄存器表索引
```

```ss
function ctVal(interpId: int): int { return interpId | 0x40000000 }
function isCt(v: int): int { return (v & 0x40000000) != 0 ? 1 : 0 }
function payload(v: int): int { return v & 0x3FFFFFFF }
```

### A.2.2 寄存器表（Phase 0 保守落地）

设计目标：`nextReg()` 返回 tagged int，字符串存入表，IR 通过 `reg(v)` 转字符串。

```ss
let regTable: Array<string> = []

function reg(v: int): string {
    if (isCt(v) == 1) { return materialize(payload(v)) }
    return regTable[payload(v) - 1]
}
```

**Phase 0 实际落地**：

- `nextReg()` 仍返回 `"%N"` 字符串（`codegen.ss:106`），未改类型
- `regTable` 只承载 `constVal(s: string)` 写入的非寄存器字符串值
- Runtime 路径继续走旧字符串发射，comptime 路径用 `ctVal()` 打包 interp value ID
- `reg()` 函数命名（不是文档原写的 `r()`，避免与局部变量 `const r = nextReg()` 冲突）
- 这个保守策略让 Phase 0–6 全程零回归，但留下了 Phase 7 的清理任务

### A.2.3 常量和全局引用入表

```ss
function constVal(s: string): int {
    regTable = regTable.push(s)
    return regTable.length()
}

// genExpr(INT_LIT) → constVal("42") 或 ctVal(interpNewInt(42))
// genExpr(STRING_LIT) → constVal(addStringConst("hello"))
```

### A.2.4 `genExpr` 变为 `genVal`

```ss
function genVal(id: int): int {
    if (id <= 0) { return constVal("0") }
    const kind = nGetKind(id)
    if (kind == "INT_LIT") { return ctVal(interpNewInt(parseInt(nGetS1(id)))) }
    if (kind == "STRING_LIT") { return ctVal(interpNewString(nGetS1(id))) }
    if (kind == "BINARY") {
        const lv = genVal(nGetI1(id))
        const rv = genVal(nGetI2(id))
        if (isCt(lv) && isCt(rv)) {
            return ctVal(interpBinaryOp(op, payload(lv), payload(rv)))
        }
        const out = nextReg()
        emitIR(`  ${out} = add i32 ${reg(lv)}, ${reg(rv)}`)
        return constVal(out)
    }
}

// 兼容 wrapper：现有 112 个调用点零改动
function genExpr(id: int): string { return reg(genVal(id)) }
```

### A.2.5 操作级 comptime 传播（Zig 模型）

不用全局 `comptimeMode` flag。每个操作检查操作数：
- 两个 comptime 操作数 → comptime 结果（直接算）
- 任一 runtime 操作数 → runtime 结果（发射 IR）

comptime 性质从字面量自底向上传播：
- `INT_LIT` → 天然 comptime
- `1 + 2` → 两个 comptime → comptime 3
- `x + 1` → x 是 runtime → runtime（发射 add 指令）

### A.2.6 `comptime {}` 块 = 约束，不是模式

```ss
let comptimeDepth = 0

// COMPTIME_BLOCK handler:
comptimeDepth = comptimeDepth + 1
genBlock(bodyId)
comptimeDepth = comptimeDepth - 1
```

`comptimeDepth` 不改变求值逻辑——逻辑永远是"看操作数"。它只用于报错：comptime 块内不允许出现 runtime 值。

### A.2.7 materialize：comptime → runtime 边界

```ss
function materialize(interpValId: int): string {
    const t = interpType(interpValId)
    if (t == "int") { return `${interpAsInt(interpValId)}` }
    if (t == "string") { return addStringConst(interpAsStr(interpValId)) }
    if (t == "bool") { return interpAsBool(interpValId) == 1 ? "1" : "0" }
    if (t == "double") { return interpAsStr(interpValId) }
    return "null"
}
```

### A.2.8 变量 / 控制流 / 函数调用

详见 `bootstrap/gen_exprs.ss` 的 `genValCt*` 系列函数，及附录 B Phase 3-5 实施记录。

## A.3 保留什么 / 删除什么

### 保留

| 模块 | 原因 |
|---|---|
| `interp.ss` 值系统 | comptime 值的数据层 |
| `interp.ss` comptime 缓冲区 | comptime 输出通道 |
| `interp.ss` 控制流 flag | comptime 控制流需要 |
| `interp.ss` 作用域 | comptime 根作用域 |
| `interp.ss` class/enum/map 注册表 | comptime 块内类/枚举/Map 操作 |
| `gen_reflect.ss` | 反射逻辑（Step 4 从 `interp_reflect` 迁入） |

### 删除（Phase 6–7 实测）

| 文件 | 行数 | 状态 | 备注 |
|---|---|---|---|
| `interp_eval.ss` | 237 | ✅ P6 Step 3 | `interpIntOp/interpDoubleOp` 迁入 `interp.ss` |
| `interp_exec.ss` | 335 | ✅ P6 Step 3 | `interpExec` → `genStmt` comptime 分支吸收 |
| `interp_calls.ss` | 607 | ✅ P6 Step 3 | `interpCall` 系列 → `genVal Ct*` 系列吸收 |
| `interp_builtins.ss` | 237 | ✅ P6 Step 3 | 共享 helper 迁入 `interp.ss`（Step 2） |
| `interp_stubs.ss` | 37 | ✅ P6 Step 3 | |
| `interp_reflect.ss` | 272 | ✅ P6 Step 4 | 整体迁入 `gen_reflect.ss`，函数体零改动 |
| `interp.ss` 死代码 | 65 | ✅ P6 Step 5 | 6 个无调用点函数 + `interpThrowFlag/Val` |
| `interpExecComptime` | 27 | ✅ P6 Step 3 | |
| `genExprOld` 函数 | 40 | ✅ P7 Step 4 | 4 处 fallback 同步替换为 genBinary/genUnary/防御日志 |
| `genTernary` 函数 | 33 | ✅ P7 Step 4 | 唯一调用方是 genExprOld，删除后无引用 |
| **合计已清理** | **~1,798** | | |

---

# 附录 B: Phase 0–7 实施日志

### Phase 0：基础设施 ✅

- 添加 tagged int 基础操作（`ctVal`, `isCt`, `payload`, `reg`, `materialize`）到 `codegen.ss:116-144`
- 添加寄存器表 `regTable`（保守版，详见附录 A.2.2）
- 添加 `constVal(s: string): int`
- 添加 `genVal(id: int): int`（comptime 路径走 `ctVal`，runtime 路径 fallback 到 `constVal(genExprOld(id))`）
- 添加 `genExpr` wrapper：`return reg(genVal(id))`（`gen_exprs.ss:1300`）
- 旧 dispatcher 改名为 `genExprOld()`（`gen_exprs.ss:97`）
- **验证**：bootstrap 通过，行为完全不变

### Phase 1：字面量 comptime ✅

- `INT_LIT` → `ctVal(interpNewInt(...))`
- `DOUBLE_LIT` / `STRING_LIT` / `TRUE_LIT/FALSE_LIT` / `NULL_LIT` 同样
- **验证**：bootstrap 通过，所有测试通过

### Phase 2：简单表达式 comptime 传播 ✅

- `BINARY` / `UNARY`：两个 comptime 操作数 → comptime 结果
- `TERNARY`：comptime 条件 → 只求值命中分支
- **验证**：`1 + 2` 不再发射 `add` 指令（常量折叠）

### Phase 3：comptime 变量和控制流 ✅

- 添加 `ctVars` comptime 作用域
- `VAR_DECL` / `IDENT` / `ASSIGN` / `IF/WHILE/FOR` / `RETURN/BREAK/CONTINUE` / `POSTFIX_INC/DEC` 全部走 comptime
- **验证**：bootstrap 固定点通过，222 测试全通过；附带修复 Pow 运算符 comptime 折叠 bug

### Phase 4：函数调用和类 ✅

- `CALL` / `NEW_EXPR` / `MEMBER_ACCESS` / `METHOD_CALL` / `MEMBER_ASSIGN` 在 comptime 块内
- 迁移 ~20 个 comptime intrinsic 到 `genValCtCall`
- `FUNC_DECL/CLASS_DECL/ENUM_DECL` 在 comptime 块内注册
- COMPTIME_BLOCK 路由 `interpExecComptime` → `runComptimeBlockBody` + `genBlock`
- `ctVars` 全用 tagged 值存储；IDENT 查找 fallback 到 `interpVars`
- **验证**：bootstrap 固定点通过，223 测试全通过

### Phase 5：内置方法和剩余节点 ✅

- 新增 `ctStringMethod` / `ctArrayMethod` / `ctMapMethod` / `ctBuiltinMethod` 在 `gen_exprs.ss`
- 新增 `ctCallValue(fnValId, argVals)`：通过 `genBlock` 调用 comptime 函数值
- `genTryCatch` / `genDoWhile` / `genSwitch` comptime 分支
- 提取 `ctPopScope()` helper
- **验证**：bootstrap 固定点通过，224 测试全通过；新增 `comptime_control_flow.ss` 7 子测试

### Phase 6：切换入口 + 删除旧解释器 ✅

#### Step 1 ✅ — `c959d22`
- `COMPTIME_EXPR` 的 `interpExecComptime` 调用点迁入 `runComptimeBlockBody`（`gen_types.ss:221`）
- 修复 `gen_stmts.ss` comptime ENUM_DECL handler 的 AST 读取 bug
- 提取 `registerEnumInto(id, valuesMap, typesMap, nodesMap)` helper
- **验证**：bootstrap 固定点通过，224 测试全通过

#### Step 2 ✅ — `045e511`
- 迁移 `interp_builtins.ss` 中新路径仍依赖的 helper 到 `interp.ss`
- `interpResetBuiltins` 内联进 `interpReset`
- `gen_exprs.ss` 合并两行 import 为一行
- **验证**：bootstrap 固定点通过，224 测试全通过

#### Step 3 ✅ — `c21d05b`
- 删除 `interp_eval.ss` / `interp_exec.ss` / `interp_calls.ss` / `interp_builtins.ss` / `interp_stubs.ss` 共 1453 行
- 删除 `tests/phase5/interp_*.ss` 5 个 legacy 测试
- 删除 `interp.ss` 中 `interpExecComptime`（27 行）
- `interpIntOp/interpDoubleOp` 迁入 `interp.ss`
- **验证**：bootstrap 固定点通过，219 测试全通过（224 - 5 删除的 legacy 测试）

#### Step 4 ✅ — `1e6320f`
- `interp_reflect.ss`（272 行）整体迁移到新建的 `bootstrap/gen_reflect.ss`
- 5 个反射函数体零改动
- 原计划迁入 `gen_types.ss`，因合并后超 500 行违反 CLAUDE.md 拆分指引，改走 B 路线
- **验证**：bootstrap 固定点通过，219 测试全通过

#### Step 5 ✅ — `ff9bcc2`
- `interp.ss` 精简：**467 → 402 行（−65，−13.9%）**，**46 → 40 函数**
- 删除 6 个无调用点 dead 函数：`interpAsDouble`, `interpPushScope`, `interpPopScope`, `interpGetVar`, `interpUpdateVar`, `interpReset`
- 删除死全局 `interpThrowFlag/interpThrowVal`（`genThrow` 直接发 runtime IR，从未走 flag）
- 清理 stale imports；重写头部 block comment
- **保留未迁移的对象/枚举/Map 基础设施**
- **验证**：bootstrap 固定点通过，219 测试全通过

### Phase 7：删除 genExprOld，单一 dispatch 入口 ✅

#### Step 1 ✅ — `4da97a2`
- 5 个叶子/简单 kind 移出 `genExprOld` fallback，进入 `genVal` 统一 dispatch：
  - DOUBLE_LIT runtime 分支（comptime 已在 Phase 1）
  - IDENT runtime 分支（comptime 已在 Phase 4 ctVars 路径）
  - THIS / SUPER 统一分支：comptime → `ctVal(interpThisVal)`；runtime → `genThisExpr()`
  - POSTFIX_INC：comptime 不支持告警；runtime → `genPostfixExpr`
  - COMPTIME_EXPR runtime 分支：复用 `comptimeExprType.has` + `inferType` + `comptimeExprLiteral` 缓存
- 同时从 comptime 块内移除独立的 THIS 分支（已并入统一分支）
- 清理 `// D089 Phase 4` 任务引用注释
- **验证**：bootstrap 固定点通过，219 测试全通过

#### Step 2 ✅ — `2d0b148`
- 4 个 call 类高频 kind 走统一分支：
  - CALL：comptime → `genValCtCall`；runtime → `genCall`
  - NEW_EXPR：comptime → `ctVal(genValCtNewExpr)`（裸 id 包 ctVal）；runtime → `genNewExpr`
  - MEMBER_ACCESS：comptime → `genValCtMemberAccess`；runtime → optional chain (`nGetI3 > 0`) 分派
  - METHOD_CALL：同上 optional chain 分派
- **验证**：bootstrap 固定点通过，219 测试全通过

#### Step 3 ✅ — `a9b5d3c`
- 4 个复合 kind 走统一分支：
  - TEMPLATE_LIT / ARRAY_LIT / INDEX_ACCESS：runtime → `genTemplateLit/genArrayLit/genIndexAccess`
  - ARROW_FUNC：comptime → `ctVal(interpNewVal("fn", id))`；runtime → `genArrowFunc`
- 迁移后 comptime 块只剩 COMPTIME_EMIT、TYPEINFO_EXPR + unsupported 兜底
- **验证**：bootstrap 固定点通过，219 测试全通过

#### Step 4 ✅ — `4b52c91`
- **收敛判据达成**：`grep -rn genExprOld bootstrap/` 返回 0
- 删除 `function genExprOld`（40 行）+ 孤立 `function genTernary`（33 行，唯一调用方是 genExprOld 的 TERNARY 分支，TERNARY 自 Phase 3 起改走 `genValTernary`，已是死代码）
- 4 处 `return constVal(genExprOld(id))` fallback 替换：
  - `genVal` 末尾 → `println("[genVal] unknown kind: ${kind}")` + `constVal("0")` 防御日志
  - `genValBinary` NullCoalesce/Instanceof/As/Pow 分支 → `genBinary(id)`
  - `genValBinary` 非 int/bool 操作数分支 → `genBinary(id)`
  - `genValUnary` 非 int/bool 操作数分支 → `genUnary(id)`
- `bootstrap/gen_exprs.ss` 净减 79 行（-82/+5）
- **验证**：bootstrap 固定点通过，219 测试全通过；`grep genExprOld` / `grep genTernary` 均为 0

---

## 反模式 / 正模式（历史归纳）

### ❌ 反模式
- 给 `interp_*.ss` 补缺口（perpetuate 双实现）
- 全局 `comptimeMode` flag 切换行为（应该看操作数，不是看 flag）
- 大爆炸重构（应逐 Phase 迁移）
- 改 `nextReg` 调用点的同时改 `genExpr` 调用点（一次只改一层）

### ✅ 正模式
- `genVal` 返回 tagged int，`genExpr` 做 wrapper——零调用点改动
- 每个 Phase 完成后 bootstrap + 全量测试
- 字面量先 comptime 化（最简单，风险最低）
- 旧解释器在 Phase 6 才删除（之前一直作为 fallback）

---

## 参考

- Zig SEMA: https://github.com/ziglang/zig/blob/master/src/Sema.zig
- D088: `docs/3-decisions/D088-comptime-zig-route.md`
- Harness Engineering 框架：
  - Martin Fowler / Birgitta Böckeler — https://martinfowler.com/articles/harness-engineering.html
  - Anthropic — https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
  - Anthropic — https://www.anthropic.com/engineering/harness-design-long-running-apps
- Phase 6 commits: `c959d22` (Step 1), `045e511` (Step 2), `c21d05b` (Step 3), `1e6320f` (Step 4), `ff9bcc2` (Step 5)
- Phase 7 commits: `4da97a2` (Step 1), `2d0b148` (Step 2), `a9b5d3c` (Step 3), `4b52c91` (Step 4)
