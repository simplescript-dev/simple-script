# D089: Compiler = Interpreter 统一架构

**Status:** Proposed
**Depends on:** D088 (comptime Zig route)
**Date:** 2026-04-13

## 问题

SS 有两套语言实现：

```
codegen (gen_*.ss)     → 每个 AST 节点 → 发射 LLVM IR
interpreter (interp_*.ss) → 每个 AST 节点 → 直接求值
```

每加一个语言特性，改两处。两套代码可能漂移。这不是"compiler = interpreter"，是"compiler + interpreter"。

D088 定义的 Zig 路线本质是"编译器即解释器"——一套代码。当前实现是表面模拟。

## 决策

**消除独立解释器。让 codegen 自己具备求值能力。**

### 核心设计：Tagged Value

genExpr 目前返回 `string`（LLVM 寄存器名如 `"%42"`）。改为返回 **tagged int**：

```
bit 30 = 1 → comptime（编译期已知值），bits 0-29 = 解释器值 ID
bit 30 = 0 → runtime（运行时值），bits 0-29 = 寄存器表索引
```

```ss
// 三个基础操作
function ctVal(interpId: int): int { return interpId | 0x40000000 }
function isCt(v: int): int { return (v & 0x40000000) != 0 ? 1 : 0 }
function payload(v: int): int { return v & 0x3FFFFFFF }
```

### 寄存器表

当前 `nextReg()` 返回字符串 `"%N"`。改为返回 tagged int，字符串存入表：

```ss
let regTable: Array<string> = []

function nextReg(): int {
    regCount = regCount + 1
    const name = `%${regCount}`
    regTable = regTable.push(name)
    return regTable.length()  // positive int，bit 30 = 0
}

// tagged int → IR 可用的字符串
function r(v: int): string {
    if (isCt(v)) { return materialize(payload(v)) }
    return regTable[payload(v) - 1]
}
```

### 常量和全局引用也入表

genExpr 除了寄存器名，还返回常量（`"42"`）和全局引用（`"@.str.5"`）。统一入表：

```ss
function constVal(s: string): int {
    regTable = regTable.push(s)
    return regTable.length()
}

// 用法：
// genExpr(INT_LIT) → constVal("42") 或 ctVal(interpNewInt(42))
// genExpr(STRING_LIT) → constVal(addStringConst("hello"))
```

### genExpr 变为 genVal

```ss
// 新函数：返回 tagged int
function genVal(id: int): int {
    if (id <= 0) { return constVal("0") }
    const kind = nGetKind(id)

    if (kind == "INT_LIT") {
        return ctVal(interpNewInt(parseInt(nGetS1(id))))
    }
    if (kind == "STRING_LIT") {
        return ctVal(interpNewString(nGetS1(id)))
    }
    if (kind == "BINARY") {
        const lv = genVal(nGetI1(id))
        const rv = genVal(nGetI2(id))
        if (isCt(lv) && isCt(rv)) {
            return ctVal(interpBinaryOp(op, payload(lv), payload(rv)))
        }
        // 至少一个 runtime → 发射 IR
        const lReg = r(lv)
        const rReg = r(rv)
        const out = nextReg()
        emitIR(`  ${r(out)} = add i32 ${lReg}, ${rReg}`)
        return out
    }
    // ... 其他节点
}

// 兼容 wrapper：现有 111 个调用点零改动
function genExpr(id: int): string { return r(genVal(id)) }
```

### 操作级 comptime 传播（Zig 模型）

不用全局 `comptimeMode` flag。每个操作检查操作数：

```ss
// genBinary 不检查任何全局状态
// 两个 comptime 操作数 → comptime 结果（直接算）
// 任一 runtime 操作数 → runtime 结果（发射 IR）
```

comptime 性质从字面量自底向上传播：
- `INT_LIT` → 天然 comptime
- `1 + 2` → 两个 comptime → comptime 3
- `x + 1` → x 是 runtime → runtime（发射 add 指令）

### `comptime {}` 块 = 约束，不是模式

```ss
let comptimeDepth = 0

// COMPTIME_BLOCK handler:
comptimeDepth = comptimeDepth + 1
genBlock(bodyId)  // 同一套 genVal/genStmt，comptime 自然传播
comptimeDepth = comptimeDepth - 1

// 如果 comptimeDepth > 0 且出现 runtime 值 → 编译错误
```

`comptimeDepth` 不改变求值逻辑——逻辑永远是"看操作数"。它只用于报错：comptime 块内不允许出现 runtime 值。

### materialize：comptime → runtime 边界

当 comptime 值需要进入 runtime（如 `const x = comptime { return 42 }`）：

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

## 变量处理

### Runtime 变量（现有逻辑不变）

```ss
// let x = expr
const val = genVal(initId)
const reg = varRef(name)        // alloca
emitIR(`  store ${llType} ${r(val)}, ptr ${reg}`)
```

### Comptime 变量（新增）

当 `comptimeDepth > 0` 或初始值是 comptime 时，变量存入 comptime 作用域：

```ss
let ctVars = new Map()  // "scopeId:name" → tagged int

// let x = 1 + 2  (comptime 初始值)
// ctVars 记录 x = ctVal(interpNewInt(3))
// genVal(IDENT "x") → 从 ctVars 查到 comptime 值，返回 ctVal(...)
```

comptime 块外的 comptime 变量同时也发射 IR（常量折叠）。comptime 块内的 comptime 变量只存 ctVars，不发射 IR。

## 控制流

### comptime 块内的控制流

```ss
// IF：条件是 comptime → 只 codegen 命中分支（编译期常量折叠）
if (kind == "IF") {
    const cond = genVal(condId)
    if (isCt(cond) && comptimeDepth > 0) {
        if (interpTruthy(payload(cond)) == 1) { genStmt(thenId) }
        else if (elseId > 0) { genStmt(elseId) }
        return
    }
    // runtime 条件 → 正常发射 label + branch
}

// WHILE/FOR：同理，comptime 条件 → 实际循环执行
// RETURN：comptime 块内 → 设置 interpReturnFlag/interpReturnVal
// BREAK/CONTINUE：comptime 块内 → 设置 interpBreakFlag/interpContinueFlag
```

### 控制流 flag

comptime 块内需要 `interpReturnFlag`、`interpBreakFlag` 等控制流 flag。这些保留在 interp.ss。

## 函数调用

### comptime 块内调用函数

genCall 检查：所有参数是 comptime？

```ss
if (comptimeDepth > 0) {
    // 查找函数 AST 节点
    // 绑定参数到 comptime 作用域
    // genBlock(functionBody) — 同一套代码，comptime 传播
    // 返回 comptime 结果
}
```

### 内置函数（println, readFile, emit 等）

这些在 comptime 中需要实际执行。当前 interpCall 有 ~20 个 comptime intrinsic。迁移到 genCall 的 comptime 分支。

## 迁移计划

### 迁移基数

| 项目 | 数量 |
|------|------|
| genExpr 调用点 | 111（97% 赋值到变量） |
| nextReg 调用点 | 363 |
| emitIR 调用点 | 1,857 |
| 解释器代码 | ~2,145 行（6 个文件） |

### Phase 0: 基础设施

- 添加 tagged int 基础操作（`ctVal`, `isCt`, `payload`, `r`）到 codegen.ss
- 添加寄存器表（`regTable`, 新 `nextReg` 返回 int）
- 添加 `constVal` 函数
- 添加 `genVal` 函数（初始版本：对所有节点返回 `constVal(旧genExpr(id))`）
- 添加 `genExpr` wrapper：`return r(genVal(id))`
- **验证**：bootstrap 通过，所有测试通过。行为完全不变。

### Phase 1: 字面量 comptime

- `INT_LIT` → `ctVal(interpNewInt(...))`
- `DOUBLE_LIT` → `ctVal(interpNewDouble(...))`
- `STRING_LIT` → `ctVal(interpNewString(...))`
- `TRUE_LIT/FALSE_LIT` → `ctVal(interpNewBool(...))`
- `NULL_LIT` → `ctVal(interpNewNull())`
- **验证**：bootstrap 通过，所有测试通过。字面量是 comptime 值但 `genExpr` wrapper 自动 materialize。

### Phase 2: 简单表达式 comptime 传播

- `BINARY`：两个 comptime 操作数 → comptime 结果
- `UNARY`：comptime 操作数 → comptime 结果
- `TERNARY`：comptime 条件 → 只求值命中分支
- **验证**：`1 + 2` 不再发射 `add` 指令（常量折叠）。Bootstrap 通过。

### Phase 3: comptime 变量和控制流

- 添加 `ctVars` comptime 作用域
- `VAR_DECL`：comptime 初始值 → 记录到 ctVars
- `IDENT`：先查 ctVars，有 comptime 值就返回
- `ASSIGN`：更新 ctVars
- `IF/WHILE/FOR`：comptime 条件在 `comptimeDepth > 0` 时直接求值
- `RETURN/BREAK/CONTINUE`：`comptimeDepth > 0` 时设置 flag
- `POSTFIX_INC/DEC`：`comptimeDepth > 0` 时更新 ctVars
- **验证**：bootstrap 固定点通过，222 测试全通过。附带修复 Pow 运算符 comptime 折叠 bug。

### Phase 4: 函数调用和类 ✅

- `CALL`：comptime 块内调用用户函数 → 查 ctFuncNodes、绑参、genBlock
- `NEW_EXPR`：comptime 块内 → 创建 interp object
- `MEMBER_ACCESS`：comptime 对象 → interpGetField
- `METHOD_CALL`：comptime 对象 → interpFindMethod + genBlock
- `MEMBER_ASSIGN`：comptime 对象 → interpSetField
- 迁移 comptime intrinsic（println, emit, readFile, comptimeAssert, getenv 等）到 genValCtCall
- FUNC_DECL/CLASS_DECL/ENUM_DECL 在 comptime 块内注册到 ctFuncNodes/interpClasses/interpEnumNodes
- COMPTIME_BLOCK 路由 `interpExecComptime` → `runComptimeBlockBody` + `genBlock`
- class-level comptime 和 @derive 也改走 runComptimeBlockBody
- ctVars 全用 tagged 值存储（参数绑定、for-in 循环变量、postfix），IDENT 查找一致
- IDENT 查找 fallback 到 interpVars（OS/ARCH/DEBUG/COMPILER_VERSION 等预定义常量）
- **验证**：bootstrap 固定点通过，223 测试全通过。

### Phase 5: 内置方法和剩余节点 ✅

- 新增 `ctStringMethod`/`ctArrayMethod`/`ctMapMethod`/`ctBuiltinMethod` 在 `gen_exprs.ss` — 自包含，不依赖 `interpBuiltinMethod`
- 字符串方法：length/trim/toUpperCase/toLowerCase/split/indexOf/substring/replace/startsWith/endsWith/charAt/includes/repeat
- 数组方法：length/push/join/indexOf/slice/map/filter/forEach/reduce（高阶回调通过 `ctCallValue` 走 `genBlock`，不再经 `interpExec`）
- Map 方法：set/get/getString/has/delete/keys/size（复用 `interpMap*` helpers）
- 新增 `ctCallValue(fnValId, argVals)`：通过 `genBlock` 调用 comptime 函数值（arrow 或 function），正确保存/恢复 currentFunc、interpBreakFlag、interpContinueFlag、terminated 状态，并清理 ctVars 条目
- `genTryCatch` comptime 分支：执行 body + finally（comptime 无异常传播语义）
- `genDoWhile` comptime 分支：10000 iter 上限 + `interpCheckLoopExit` + `genVal` 求条件
- `genSwitch` comptime 分支：支持 STRING/INT/BOOL/ENUM pattern，default fallback，switch break 清理
- 提取 `ctPopScope()` helper 到 codegen.ss，统一 4 处重复的 scope 弹栈逻辑
- **验证**：bootstrap 固定点通过，`bin/ss test tests/` 224 测试全通过，新增 `tests/phase5/comptime_control_flow.ss` 7 子测试全通过。

### Phase 6: 切换入口 + 删除旧解释器

- **Step 1 ✅**：`COMPTIME_EXPR` 的 `interpExecComptime` 调用点迁入 `runComptimeBlockBody`（gen_types.ss:221）
  - 顺带修复 gen_stmts.ss comptime ENUM_DECL handler 的 AST 读取 bug：原代码按 `STRING_LIT`/`INT_LIT` 子节点解码，实际 parser 直接把值写在 `ENUM_VARIANT.S2/I1`，仅跑 COMPTIME_BLOCK 路径时被 latent bug 掩盖
  - 提取 `registerEnumInto(id, valuesMap, typesMap, nodesMap)` helper，`registerEnum` 和 comptime 分支共用，消除 ~18 行重复，防止再次漂移
  - `runComptimeBlockBody` 入口补齐 `interpThrowFlag/interpThrowVal` 重置，与 `interpExecComptime` 行为一致
  - **验证**：bootstrap 固定点通过，224 测试全通过
- **Step 2 ✅**：迁移 `interp_builtins.ss` 中新路径仍依赖的 helper（`interpValEquals`、`interpMap{Set,Get,Has,Delete,GetKeys,GetSize}`、`interpNewMap`）以及 `interpMapEntries`/`interpMapKeyIds` 全局到 `interp.ss`
  - 顺带把 `interpResetBuiltins` 内联进 `interpReset`（独立函数已无意义，仅一处调用且现在同文件），interp_builtins.ss 头部注释收敛到"只描述当前职责"
  - `gen_exprs.ss` 把两行 import（`./interp` + `./interp_builtins`）合并为一行 `./interp`，新路径 import 表面上彻底脱离 interp_builtins.ss
  - **验证**：bootstrap 固定点通过，224 测试全通过
- **Step 3 TODO**：删除 `interp_eval.ss`（237 行）、`interp_exec.ss`（335 行）、`interp_calls.ss`（607 行）、`interp_builtins.ss`（剩余 ~245 行），并清理 gen_stmts.ss 里对 `interpExecComptime` 的遗留 import
- **Step 4 TODO**：`interp_reflect.ss` 迁入 `gen_types.ss` → 删除
- **Step 5 TODO**：`interp.ss` 精简，只保留值系统、comptime 缓冲区、comptime 作用域

### Phase 7: 逐步迁移 genExpr → genVal

- 将 111 个 genExpr 调用点逐步改为 genVal + 显式 `r()` 调用
- 移除 genExpr wrapper
- **验证**：bootstrap 固定点通过。

## 保留什么

| 模块 | 保留 | 原因 |
|------|------|------|
| interp.ss 值系统 | ✅ | interpNewInt/interpType/interpAsStr 等——comptime 值的数据层 |
| interp.ss comptime 缓冲区 | ✅ | comptimeIR/comptimeSS/flush——comptime 输出通道 |
| interp.ss 控制流 flag | ✅ | interpReturnFlag 等——comptime 控制流需要 |
| interp.ss 作用域 | ✅ | interpPushScope 等——comptime 变量需要 |
| interp_reflect.ss | 迁移 | 搬到 gen_types.ss，逻辑不变 |

## 删除什么

| 文件 | 行数 | 原因 |
|------|------|------|
| interp_eval.ss | 237 | interpEval → genVal 吸收 |
| interp_exec.ss | 335 | interpExec → genStmt comptime 分支吸收 |
| interp_calls.ss | 607 | interpCall/interpMethodCall/interpNewExpr → genCall/genMethodCall/genNewExpr 吸收 |
| interp_builtins.ss | 331 | → gen_builtins.ss comptime 分支吸收 |
| interp_reflect.ss | 272 | → gen_types.ss 迁移 |
| **合计** | **1,782** | |

## 根本验证

### 架构验证（最重要）

> **新增一个语言特性时，需要改几处？**
> - 改前（当前）：codegen + interpreter = 2 处
> - 改后：codegen = 1 处
> - **1 处 → 在路线上。2 处 → 没改到位。**

### 每个 Phase 的验证

1. `./build.sh bootstrap` 固定点通过
2. `bin/ss test tests/` 全量通过（当前 218 测试）
3. 现有 comptime 测试（tests/phase5/comptime_*.ss）全部通过
4. Phase 6 完成后：确认 interp_eval.ss、interp_exec.ss、interp_calls.ss 不再被 import

### 功能验证

Phase 2 完成后，IR 验证常量折叠：
```ss
function main() {
    const x = 1 + 2    // 不应出现 add 指令，直接 store i32 3
    println(x)
}
// bin/ss build test.ss --emit-ir | grep "add i32" → 无匹配
```

Phase 3 完成后，comptime 块使用 genVal 路径：
```ss
const r = comptime {
    let sum = 0
    let i = 0
    while (i < 5) { sum = sum + i; i = i + 1 }
    return sum
}
assertEqual(r, 10)
```

Phase 4 完成后，comptime 块内 class 操作：
```ss
const r = comptime {
    class Point { x: int; y: int }
    const p = new Point(x: 3, y: 4)
    return p.x + p.y
}
assertEqual(r, 7)
```

## 反模式

- ❌ 给 interp_*.ss 补缺口（perpetuate 双实现）
- ❌ 全局 `comptimeMode` flag 切换行为（应该看操作数，不是看 flag）
- ❌ 大爆炸重构（应该逐 Phase 迁移，每步 bootstrap 验证）
- ❌ 改 nextReg 调用点的同时改 genExpr 调用点（一次只改一层）

## 正模式

- ✅ genVal 返回 tagged int，genExpr 做 wrapper——零调用点改动
- ✅ 每个 Phase 完成后 bootstrap + 全量测试
- ✅ 字面量先 comptime 化（最简单，风险最低）
- ✅ 旧解释器在 Phase 6 才删除（之前一直作为 fallback）

## 参考

- Zig SEMA: https://github.com/ziglang/zig/blob/master/src/Sema.zig
- D88: docs/3-decisions/D088-comptime-zig-route.md
