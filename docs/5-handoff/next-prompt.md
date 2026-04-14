# D089 Phase 7 启动：genExpr → genVal 迁移 Wave 1

## 上轮成果（Phase 6 Step 5 完成）

- `bootstrap/interp.ss`：467 行 → 402 行（-65，-13.9%），46 函数 → 40 函数
- 删除 6 个 dead 函数：`interpAsDouble`、`interpPushScope`、`interpPopScope`、`interpGetVar`、`interpUpdateVar`、`interpReset`
- 顺带删除 2 个 dead 全局 + unreachable 分支：`interpThrowFlag`/`interpThrowVal`（只清零，从不置 1；`interpShouldStop()` 的 throw 分支 unreachable；`runComptimeBlockBody` 两行清零一并删除）
- 清理 stale import：`./gen_reflect` 整行删除；`./parser` 只保留 `nGetS1/nGetI2/nGetList`
- 头部 block comment 重写，精确列出五大职责（值堆 / 作用域 / 控制流 flag / IR+SS 缓冲 / class+enum+Map 注册表）
- commit: `1781ddb`

Phase 6 整体收尾：旧解释器 4 文件 + 5 测试文件 + interp_reflect 迁移 + interp.ss 精简，全部完成。

## 本轮目标：Phase 7 — 启动 genExpr → genVal 迁移（Wave 1）

### 背景

D089 Phase 0-6 的策略是"**先让 genVal 活着，保留 genExpr wrapper 吸收全部旧调用点**"。当前状态：

- `genVal(id)` 定义在 `bootstrap/gen_exprs.ss:139`，返回 `int`（tagged value）
- `genExpr(id)` 定义在 `bootstrap/gen_exprs.ss:1300`，wrapper：`return reg(genVal(id))`
- **111 个** `genExpr(` 调用点分布（不含 wrapper 定义自身）：

| 文件 | 调用点 |
|------|-------:|
| `gen_exprs.ss` | ~24 |
| `gen_builtins.ss` | 28 |
| `gen_assigns.ss` | 13 |
| `gen_calls.ss` | 11 |
| `gen_methods.ss` | 11 |
| `gen_class.ss` | 7 |
| `gen_stmts.ss` | 11 |
| `gen_decls.ss` | 5 |
| `gen_generic_class.ss` | 1 |
| **合计** | **111** |

- `genVal(` 调用点（已迁移部分）：51，集中在 `gen_exprs.ss`（38）、`gen_stmts.ss`（7）、`gen_decls.ss`、`gen_assigns.ss`

### Wave 1 范围：gen_decls.ss + gen_generic_class.ss（6 处）

这两个文件调用点最少（5+1=6），作为热身：先验证工作流、建立机械迁移的 pattern，然后 Wave 2 再处理大文件。

**机械迁移 pattern**：

```ss
// 旧：
const rhs = genExpr(rhsId)
emitIR(`  store ${llType} ${rhs}, ptr ${slot}`)

// 新：
const rhsV = genVal(rhsId)
const rhs = reg(rhsV)
emitIR(`  store ${llType} ${rhs}, ptr ${slot}`)
```

**当 comptime 已知时的额外优化**（非必须，Wave 1 可以先不做）：

```ss
const rhsV = genVal(rhsId)
if (isCt(rhsV)) {
    // 直接用 comptime 值，跳过 runtime store（仅在 comptime 块内）
}
const rhs = reg(rhsV)
```

Wave 1 只做机械迁移：每个 `genExpr(x)` → `genVal(x)` + `reg()`，不改变任何行为。

### 具体任务

1. **读 `bootstrap/gen_decls.ss`，定位 5 个 `genExpr(` 调用点**。每个调用点：
   - 判断返回值如何被使用（emitIR 字符串插值 / 传给其他函数 / 赋值到本地变量）
   - 改为 `const xV = genVal(id); const x = reg(xV); ...原样使用 x`
   - 如果原来是 `emitIR(..${genExpr(id)}..)` 内联调用，需要展开为两行
   
2. **读 `bootstrap/gen_generic_class.ss`，定位 1 个 `genExpr(` 调用点**，同样处理。

3. **每改一个文件立即 `./build.sh bootstrap` 验证**（bootstrap ~2 分钟）。固定点通过后继续下一个文件。

4. **全部改完后跑 `bin/ss test tests/`**，必须 219/219 通过。

5. **不要动 `genExpr` wrapper 本身**（gen_exprs.ss:1300），它仍要服务剩余 105 个调用点。

6. **不要改任何 comptime 语义**：Wave 1 是纯机械迁移，行为完全不变。

### 关键文件

- `bootstrap/gen_exprs.ss:139-268`（genVal 定义 + dispatch）
- `bootstrap/gen_exprs.ss:1300-1302`（genExpr wrapper，仅参考不改）
- `bootstrap/gen_decls.ss`（Wave 1 目标文件 1）
- `bootstrap/gen_generic_class.ss`（Wave 1 目标文件 2）
- `docs/3-decisions/D089-compiler-is-interpreter.md`（Phase 7 章节 321-325 行）

### 反模式

- ❌ 顺手把 Wave 2/3 的文件也改了（爆炸半径）
- ❌ 改 genVal/genExpr wrapper 的实现（破坏 invariant）
- ❌ 在机械迁移的同时优化 comptime 分支（两件事混一起，调试难）
- ❌ 批量 sed 替换（每个调用点的上下文不同，需单独判断是否能内联展开）

### 正模式

- ✅ 每改一个文件 `./build.sh bootstrap` 一次
- ✅ 先读原 genExpr 调用点的上下文，再决定是两行展开还是保持内联 `reg(genVal(id))`
- ✅ 完成后统计：genExpr 调用点从 111 → 105（Wave 1 -6），genVal 调用点从 51 → 57

## When Done

1. `./build.sh bootstrap` 固定点通过
2. `bin/ss test tests/` 219 全通过
3. `/simplify` 自测
4. 更新 `docs/3-decisions/D089-compiler-is-interpreter.md` Phase 7 章节：
   - Phase 7 Wave 1 ✅ 标记
   - 记录 gen_decls.ss 迁移了 N 处、gen_generic_class.ss 迁移了 1 处
   - 记录 genExpr 调用点数从 111 → 105
5. `git commit`，message 格式：`feat: D089 Phase 7 Wave 1 — gen_decls + gen_generic_class genExpr→genVal`
6. 生成下轮 next-prompt（Wave 2：`gen_class.ss` + `gen_stmts.ss` 共 18 处）
7. Stop
