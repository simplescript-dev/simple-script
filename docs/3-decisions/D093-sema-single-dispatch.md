# D093: SEMA 单函数 dispatch — Zig 本质一样路径

**Status:** Proposed
**Depends on:** D088(Zig 路线), D092(双轨 SEMA 实现 — 被本决策替代)
**Date:** 2026-04-15

## 第一性需求

**编译器里只能有一份求值逻辑。** comptime 与 runtime 不是两个世界,是同一份逻辑对同一段代码的两次提问:「这个值现在就能算出来吗?」能 → fold 成常量,不能 → 发射 runtime 指令。

当前 SS 的 **40 处** `if (comptimeDepth > 0) { genValCt* } else { gen* }` 分岔 + **7 个** `genValCt*` 函数代表的「comptime 专用求值器」设计,是把一份逻辑拆成两份独立实现。两份没有同步机制,人类审阅抓不全差异——过去 4 轮对 D092 代码的架构判断反转,根源都在这里。

消除双轨不是风格偏好,是防假装 bug 的唯一机制。

## 决策

**走 Zig SEMA 的单函数 dispatch 路径**:一个 `evalExpr` 函数对任意 AST 节点返回「已知值 / 未知」二元结果,`genExpr` 据此决定 fold 常量还是发射 runtime 指令。comptime 块只是对 `evalExpr` 返回值的强约束 flag,不是独立求值器。

### Zig 原理

纯原理提炼,来源 `src/Sema.zig` / `src/Value.zig` / `src/InternPool.zig` + Mitchell Hashimoto "Zig's Comptime is Bonkers Good"。**不引用任何 SS 既有代码作为权威**。

1. **单函数求值入口**: `Sema.resolveMaybeUndefVal(inst: Air.Inst.Ref) -> ?Value`。任意 ZIR 指令走这一个函数,拿 `?Value` 决定下一步。`Sema.zig` 全文只有一个 `resolveMaybeUndefVal`,没有 comptime 专用副本
2. **`?Value` 二元返回**: 有值 → 编译期已知 → `genConst`;null → 无法编译期确定 → 发射 AIR runtime 指令。**同一 `?Value` 语义覆盖 binop / call / member / index / cast / branch 全部表达式类型**,没有任何 `if comptime then A else B` 分岔
3. **Value 是无类型的**: `Value.zig` 里 Value 只存"这是什么值"(tag + payload),不存"这是什么类型"。类型信息单独存在 AIR 指令或 TypedValue 结构里。Value 的无类型性让 `?Value` 能作为通用容器覆盖一切
4. **Type 本身是一个 Value**: `Value.Tag.ty` —— 类型是一等公民,可以被 evalExpr 返回。这使得泛型单态化、`@TypeOf`、`@typeInfo` 无需独立通道,全部走同一套 dispatch
5. **InternPool 统一去重**: `InternPool.zig` 把所有 Value 和 Type 映射到稳定 index,相同值/类型共享同一 index。Value 相等比较是 O(1) index 比较,而非深度结构比较

### SS 本质一样骨架

```ss
// MaybeVal:SS 没有 nullable,用 class 模拟 Zig ?Value
// known=true  → val 是 Value id(InternPool 索引或 tagged int)
// known=false → val 是 LLVM 寄存器引用占位,无编译期意义
class MaybeVal {
    known: bool
    val: int
}

// 唯一求值入口(comptime 与 runtime 共用)
function evalExpr(astId: int): MaybeVal {
    // binop / call / member / index / cast / literal 共享同一分发表
    // 对每一种 kind:
    //   - 递归 evalExpr 所有子表达式,拿 MaybeVal
    //   - 若所有子项 known=true → 调对应 interp* 常量计算,返回 {known:true, val}
    //   - 否则返回 {known:false, val:emitRuntimeSubExprs(...)}
    // 没有任何 "if comptimeDepth > 0" 分岔
}

// 唯一代码生成入口
function genExpr(astId: int): string {
    let m = evalExpr(astId)
    if (mvKnown(m)) {
        return emitConstFromVal(mvVal(m))    // fold 成 LLVM 常量
    }
    if (comptimeMustBeKnown) {
        error("comptime block contains runtime-only expression")
    }
    return emitRuntimeInst(astId)             // 发射 LLVM 指令
}

// comptime 块语义:flag,不是独立求值器
function enterComptimeBlock() { comptimeMustBeKnown = true }
function exitComptimeBlock()  { comptimeMustBeKnown = false }
// 块内任何 evalExpr 返回 known=false 即 error,不存在"comptime 专用"走法
```

**与 Zig 的名词对齐**:

| Zig | SS | 说明 |
|---|---|---|
| `Sema.resolveMaybeUndefVal` | `evalExpr` | 唯一求值入口 |
| `?Value` | `MaybeVal { known, val }` | 二元返回,SS 无 nullable 用 class 模拟 |
| `Sema.air_instructions` | LLVM IR 发射路径 | runtime 分支落点 |
| `InternPool` | 未补 — §张力 第 2 条 | Value / Type 去重层,待 D094 |
| `Sema.typeOf(inst)` | 独立 type 通道 | Value 层不混 Type,§差距 第 3 条 |

## 与双轨现状的差距清单

每项标 P19 状态。本 D 文档**不**给修复步骤,下一轮 Execute 单独决策。

1. **[ ] Planned** — 消除 40 处 `if (comptimeDepth > 0)` 分岔
   现状: gen_exprs.ss:18 + gen_stmts.ss:15 + gen_decls.ss:4 + gen_assigns.ss:2 + codegen.ss:1 = 40。目标: 分岔数归 0,全部走 `evalExpr` → `genExpr` 两步

2. **[ ] Planned** — 合并 7 个 `genValCt*` 函数到 `evalExpr` 分发表
   现状: `genValCtCall` / `NewExpr` / `MemberAccess` / `MethodCall` / `TemplateLit` / `ArrayLit` / `IndexAccess` 各自独立。目标: `genValCt*` 函数不再存在,逻辑作为 `evalExpr` 各 kind 分支吸收

3. **[ ] Planned** — TypedValue storage 拆成 Value + Type 两层
   现状: `{tvKind, tvI1, tvS1, tvD1, tvList, tvMap}` 把 kind 和 val 混存,名义 TypedValue 实则 Kind-tagged Value。目标: Value 层不带 Type,Type 查询走独立通道(`astType` / `inferType` 或未来 InternPool 的 Type id)

4. **[ ] Planned** — 引入 InternPool 去重 Value / Type
   现状: 无 intern,相同常量每次产生新 id(或通过 tagged int 原地带值)。目标: 实现 InternPool,Value 相等即 id 相等,Type 同理

5. **[ ] Planned** — comptime 块降为 `comptimeMustBeKnown` flag
   现状: comptime 块内触发一整套独立求值器 —— `interpIntOp` / `interpDoubleOp` / `interpCompoundOp` / `interpGetField` / `interpSetField` / `ctVars` / `ctScopeStack` / `interpBreakFlag` / `interpContinueFlag` / `interpReturnFlag` / TypedValue storage,本质是 code + state 两份独立系统。目标: 块内走同一个 `evalExpr`,只在块边界把 flag 置位/复位,`evalExpr` 返回 `known=false` 即 error

## Rejected Alternatives

- **A: 继续双路径手工同步**(现状延长线) —— 每 phase 两改,漏一侧即假装 bug。过去 4 轮架构判断反转即证据
- **B: 抄 Nim 编译期 VM / Crystal macro 系统** —— 独立 VM 本身就是双轨;脱离 D088 §借鉴来源 的 Zig 路线
- **C: D092 sub-a→sub-e 补洞路径** —— 装修双轨而非消除,D088 §核心验证 Q2 "双轨制根因" 两问过不了
- **D: 把 `genValCt*` 合入 `genExpr` 但保留 `if comptimeDepth > 0` 分岔** —— 表面合并底层仍双轨,消除不到根

## 张力

1. **SS 无 nullable** —— `MaybeVal` 用 `{known: bool, val: int}` class 模拟 Zig `?Value`。`known=false` 时 `val` 字段的语义需明确(LLVM 寄存器引用占位 / 哨兵值 / 未设),是骨架的核心编码决策,D094 细化
2. **InternPool 依赖哈希表** —— SS Map 够用但需定制 hash/equal。Value 的结构化比较 vs 引用比较取舍单独立项
3. **Type-as-Value 的编码空间** —— 当前 tagged int `ctVal(id) = id | 1073741824` 只有一个 tag,扩展到同时容纳 int / string literal / Type 句柄 / class instance 需重新设计 payload 编码
4. **渐进迁移还是一次性重构** —— 40 + 7 处差距是一次重构还是分批,本 D 文档不决定,下一轮单独立项。但**不允许**"保留双轨作过渡态" —— 即便分批,每批完成时双轨必须局部消除,不允许长期共存

## 下一步(Plan 型,不触发代码改动)

- **[ ] Planned** 验证 §张力 1-3 的编码决策可行性,产出 D094 "MaybeVal / InternPool / Type-as-Value 详设"
- **[ ] Planned** 验证 D093 骨架所需的 SS 语言能力缺口(class bool 字段 / 全局 flag / error 机制),缺则补

**本 D 文档不触发任何 `.ss` 代码改动,不跑 bootstrap。** 代码改动从 D094 之后的 Execute 轮开始。
