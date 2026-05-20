# D093: SEMA 单函数 dispatch — Zig 本质一样路径

**Status:** Phase 0 Done at 2983d8a — 2026-05-20 反向倒退 audit + 三类混合分类 + Phase 1 首批起手 spec 落地;**Phase 1 Blocked at 5d36c8c** — §拒绝准则 #1/#3 触发(详 §Phase 1 受阻 + D169),升级 Phase 1.5(D169 起首);**Phase 1.5 §A class 形态 Superseded by D098 §决策 1**(2026-05-20 ultrathink — D169 立项时漏引 D098,§A class 改 D098 §决策 1 纯 int 4 helper);**Phase 1.5a Done at 3710016** — D098 §决策 1 4 helper(mvKnownOf/mvValOf/mvRuntime/mvError)+ comptimeMustBeKnown flag + enter/exit + UNARY POC 4 处 mvRuntime + D169 §POC 失败实证落档;**Phase 1.5b 单点起手 Done at e423591** — UNARY 入口双轨消除(1/5 类 B 处);**Phase 1.5b BINARY 子轮 Done at 4573341** — BINARY 入口 ct-depth 字面消(2/5 类 B 处累计 eval_expr.ss);`grep -c "comptimeDepth > 0" bootstrap/eval/eval_expr.ss` 2 → 1(BINARY case 入口 ct-depth 字面消 + int/bool runtime 走 mv 协议 + comptimeMustBeKnown 第二 read callsite;留 line 76 COMPTIME_EXPR 类 C 边界检查);**§POC N3 实证 落档**(首版按 inferType pre-route 在 comptime 路径引入 17 处 regression,inferType IDENT fallback "int" 致 `acc != ""` 走 int interpAsInt 恒 false → 修正改 1:1 字面 rename + 内部纯 valType dispatch);**Phase 1.5c 起手 Done at c9f8ff6** — TERNARY 子模块入口 ct-depth 字面消(`bootstrap/eval/ternary.ss:10` 单点字面 rename `comptimeDepth > 0 → comptimeMustBeKnown == 1` + OLD silent null `ctVal(interpNewNull())` 升 loud error `comptimeError("ternary condition not compile-time known", astId)` + `comptimeMustBeKnown == 1` 第三 read callsite 接入);`grep -c "comptimeDepth > 0" bootstrap/eval/ternary.ss` = 1 → 0;**Phase 1.5c short_circuit 子轮 In Progress(2026-05-20 本轮)** — SHORT_CIRCUIT 子模块(`bootstrap/eval/short_circuit.ss:13`)入口 ct-depth 字面消 + OLD silent null `ctVal(interpNewNull())` 升 loud error `comptimeError(`short-circuit '${op}' operand not compile-time known`, astId)` + `comptimeMustBeKnown == 1` 第五 read callsite 接入;`grep -c "comptimeDepth > 0" bootstrap/eval/short_circuit.ss` 1 → 0;index_access/template_lit/array_lit/ident/member_access/postfix_inc/method_call/call/new_expr ~8 处 + genBinary/genStringConcat/genValStringCompare 接口扩(take pre-eval reg)留 Phase 1.5c 余下子轮
**Depends on:** D088(Zig 路线), D092(双轨 SEMA 实现 — 被本决策替代)
**Spawned:** D169(MaybeVal + comptimeMustBeKnown 协议接口详设 — Phase 1.5 prereq)
**Date:** 2026-04-15
**Last Updated:** 2026-05-20 (Phase 1 受阻 → Phase 1.5 升级 + D169 起首)

## 第一性需求

**编译器里只能有一份求值逻辑。** comptime 与 runtime 不是两个世界,是同一份逻辑对同一段代码的两次提问:「这个值现在就能算出来吗?」能 → fold 成常量,不能 → 发射 runtime 指令。

当前 SS 的 **40 处** `if (comptimeDepth > 0) { genValCt* } else { gen* }` 分岔 + **7 个** `genValCt*` 函数代表的「comptime 专用求值器」设计,是把一份逻辑拆成两份独立实现。两份没有同步机制,人类审阅抓不全差异——过去 4 轮对 D092 代码的架构判断反转,根源都在这里。

消除双轨不是风格偏好,是防假装 bug 的唯一机制。

## 历史语境(2026-04-15)

D093 替代 D092 "半 SEMA + 填洞即合并" 路径,来源于本轮对话的以下发现:

1. **D092 既有代码不可靠** —— 单轮对话中 4 次架构判断反转(全盘否定 → 仅节奏缺陷 → 另起炉灶 → 骨架正确 / interp* 必要),每次新读都被下一次读推翻。根因: D092 实现层是"双轨 + 手工同步",代码在"装修双轨 vs 合并架构"两种意图之间漂移,无一致架构承诺。详见 `docs/3-decisions/D092-sema-architecture.md` §不可靠性声明
2. **dev 分支是废墟** —— `d1816ab` 清零了 `interp.ss` / `gen_reflect.ss` / `gen_annotations.ss` 等文件,但保留了 `gen_assigns.ss` / `gen_exprs.ss` 里 **448 处** undefined function 调用。不是 clean slate,是半拆房 + 引用悬空。任何"reset 到 dev 重做"的提议都会落入比当前更糟的状态,已在 `feedback_verify_reset_target.md` 锚定
3. **Phase 8 commit `25e5760` 是双轨装修** —— `interpIntOp` 分支顺序调整 + `UShr` 补丁 + Q1 最小测试,全部在双轨系统一侧补洞,不动消除双轨的结构。符合 D088 §反模式 "给 interp.ss 抄 handler 加深双轨制"
4. **方法论教训** —— "读代码决定架构" 在假装期代码上必然产生反转,因为前提(代码一致性)不成立。设计阶段必须**从原理出发**,不从代码出发。已在 `feedback_design_no_code_authority.md` 锚定

D093 的 §决策 和 §差距清单 不引用 D092 代码作为架构依据——Zig 原理段完全出自 `src/Sema.zig` / `src/Value.zig` / `src/InternPool.zig`,§差距清单 的 40 / 7 数字只作为**现状快照**(要消除的目标),不作为**设计依据**。

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

## Phase 0: 反向倒退 audit + 分类规约 + 首批起手 spec (2026-05-20 起首)

**Status**: [x] Done at 2983d8a

### 0.1 反向倒退 audit

2026-04-15 D093 立项时 baseline = 39 处 `comptimeDepth > 0` 分岔(gen_assigns 2 / gen_decls 4 / gen_exprs 18 / gen_stmts 15)。截至 2026-05-20 = **54 处**(**+15 / +38% 反向倒退**)。

**关键发现**: 旧 4 扁平文件 39 处全部消失,**新 27 子目录文件 54 处全部新增** — D113 SEMA 模块拆分(commit `e3d8262`)只是把双轨分岔搬家,**根因双轨架构未消除**。

| | baseline (2026-04-15) | 现在 (2026-05-20) | delta |
|---|---|---|---|
| 旧扁平 `gen_{exprs,stmts,decls,assigns}.ss` | 39 | 0 (文件消失) | -39 |
| 新 `bootstrap/eval/` (11 文件) | 0 | 25 | +25 |
| 新 `bootstrap/gen/{class,methods,stmts,exprs}/` (16 文件) | 0 | 29 | +29 |
| **总数** | **39** | **54** | **+15** |

**事件链**(2026-05-20 PSM §字段 13 + linter C5 双闸落地的触发链):

```
e3d8262 D113 SEMA 模块拆分 (末次 SEMA 主线 commit, 2025-12)
  → D168 RC system 长线 (2026-01-04 起)
    → SS-LIM-4/5/6 修复 (2026-04)
      → I023-I031 CLI/build/comptime issue (2026-04-05~)
        → Tier1-5 tests refactor (2026-05-12~19, 5 commits)
          → next_prompt Tier 第 6 轮 (本轮被双闸 GATE BLOCKED 拦住)
```

5 个月 SEMA Q1 主线 0 commit。Phase 0 起首本身受同期落地的双闸防护,Phase 1+ 每轮 next_prompt 必含 `d092`/`sema`/`q1` 任一关键字,任何"避难性偏离"(tests cleanup / CLI fix / 工程整理 等绕开 SEMA Q1 主线)由 linter GATE BLOCKED 阻断 stop。

### 0.2 三类混合 — 真双轨 vs 入口双轨 vs 合理边界

54 处分岔是**三类混合**,Phase 1+ 必须按类区分,不能一刀切消除/保留。

**类 A — 真双轨 callsite (~45 处, 该消除)**

`comptimeDepth > 0` 分支走**完全独立 dispatch / 独立数据结构**(`ctFuncNodes` / `ctVars` / `ctScopeStack` / `ctCallDispatch` / `interp*Flag`),与 runtime 路径**几乎无共享代码**。

判据(全部满足):
- 分支体写或读独立 ct* 命名空间数据结构
- 分支体调用 `genVal` + `isCt` + `payload` 协议(comptime 求值返 tagged ctVal)
- 分支体不与 runtime 分支共享 helper 函数(各走各的)

实证样例:
- `gen_decls.ss:35` — comptime func decl 写 `ctFuncNodes`,runtime 走 codegen IR emit
- `gen_decls.ss:527` — comptime var decl 写 `ctVars`,runtime 写 codegen alloca
- `gen_decls.ss:683` — comptime return 写 `interpReturnFlag`,runtime 写 LLVM ret
- `gen_assigns.ss:93` — comptime member assign 走 `ctObj/ctNewVal + interpType`
- `stmts_loop_classic.ss:12/71/120` — comptime for/while/do-while 走 interp 1 万次硬限制
- `call.ss:10` / `call.ss:77` — comptime 走独立 `ctFuncNodes`/`ctCallDispatch`

Zig 等价: `Sema.resolveMaybeUndefVal` 单一 dispatch,callsite 走 `?Value` 协议(known→fold/runtime emit / unknown 在 comptime 块内触发 error)。SS 应走 `MaybeVal` 协议 + `comptimeMustBeKnown` flag,callsite 不再分岔。

**类 B — evalExpr 入口双轨 (~3 处, 该彻底消除)**

evalExpr 入口本身按 comptimeDepth 分岔。

实证样例:
- `eval_expr.ss:25` — `comptimeDepth>0 → ctUv = genVal(child) + isCt 检查 + payload`,runtime → `genExpr`
- `eval_expr.ss:88` — binop comptime 路径
- `gen/exprs/exprs.ss` 部分入口

Zig 等价: evalExpr 始终走 MaybeVal 协议,**不分 comptime/runtime**。这是 D093 §决策 §Zig 原理 §2 的核心。**类 B 必须先于类 A 大规模消除**(类 A callsite 依赖 evalExpr 统一协议作为前提)。

**类 C — 合理 comptime 边界检查 (~6 处, 该保留)**

`comptimeDepth>0` 仅作为 error 触发条件,**不分发到独立 code path**。

判据:
- 分支体仅 `comptimeError(...)` 或 `println + exit(1)`
- 不调 interp* / 不写 ct* 数据结构
- 等价 Zig `comptimeMustBeKnown` flag 触发 error

实证样例:
- `eval_expr.ss:66` — `nested comptime expression` 报错
- `call.ss:44` — comptime spread non-array error
- `call.ss:59` — comptime spread runtime value error

Zig 等价: 保留作为 comptime 块内 error gate。

### 0.3 首批起手目标 spec (Phase 1)

按 §张力 §4 "渐进迁移 + 每批完成时双轨必须局部消除",首批起手选**最孤立的类 A 单点** spike:

**Phase 1 起手目标**: `stmts_loop_classic.ss:120` comptime do-while loop 消除(类 A 单点)

理由:
- **单点孤立** — 本文件 3 处 loop 结构互相独立,改一处不牵动两处
- **模式纯** — comptime 块内循环本质 = "evalExpr 多次 + check flag",最适合作为 `comptimeMustBeKnown` flag spike 跑通
- **Zig 对标** — `comptime { while ... }` 在 Sema 里走同一 dispatch,unknown 触发 error,有清晰先例

Phase 1 验收:
1. `grep -c "comptimeDepth > 0" bootstrap/gen/stmts/stmts_loop_classic.ss` 从 3 → 2 (消除 do-while 一处)
2. **不引入新 `ct*` 数据结构 / 不打补丁**(根因防偏)
3. bootstrap 三阶段固定点验证 GREEN
4. 所有 phase2-phase5 测试 GREEN
5. comptime do-while spike 测试(新增 `tests/phase5/comptime_do_while_unknown_error.ss`)验证 unknown 触发 error

Phase 1 拒绝准则(根因防偏 — 与 CLAUDE.md §Root Cause 优先 第一法则联动):
- 若 do-while 消除需要扩展 evalExpr 协议(`MaybeVal` 字段补充) → **先完成协议扩展**(回 §骨架 修订)再消除,不偏方扩 ct* 数据结构
- 若发现类 B (`eval_expr.ss:25` 入口双轨) 是 Phase 1 prerequisite → **升级 Phase 1.5** (先 evalExpr 入口走 MaybeVal),不绕开
- 若 spike 中发现 `MaybeVal class` 当前未充分 instance 化(D110 起步 / D113 拆模块仅起步未推进) → **先补 MaybeVal 协议接口**(回 D093 §骨架 修订 + 可能起 D169 子设计),不在 do-while 局部 hack

### 0.4 Phase 后续粗规划(Phase 1 实施时按需细化)

**2026-05-20 更新**:Phase 1 起首 ultrathink 实证 §拒绝准则 #1/#3 触发,Phase 1 受阻(详 §Phase 1 受阻段),Phase 1.5 由"条件触发"转"已触发",拆 1.5a/b/c/d 渐进路径(D169 §子拆解 表 单一事实源)。

| Phase | 范围 | 验收 |
|---|---|---|
| 1 | ~~`stmts_loop_classic.ss` do-while 消除 (1 处类 A spike)~~ **Blocked** — §拒绝准则 #1/#3 触发,见 §Phase 1 受阻;升级 Phase 1.5 | §0.3(待 1.5d 回归后达成) |
| **1.5a** | **D098 §决策 1 4 helper**(`mvKnownOf`/`mvValOf`/`mvRuntime`/`mvError`,纯 int 形态)+ comptimeMustBeKnown flag + enterComptimeBlock/exitComptimeBlock + UNARY POC(2026-05-20 §A §修订:原 class MaybeVal 形态 Superseded by D098 §决策 1) | D169 §子拆解 1.5a 验收 6 项 |
| **1.5b** | eval_expr.ss UNARY/BINARY/TERNARY/NULL_COALESCE 5 处类 B 入口消除(callsite 走 `mvKnownOf`/`mvValOf`/`reg`) | eval_expr.ss `grep -c "comptimeDepth > 0"` 5+ → 0 |
| **1.5c** | bootstrap/eval/ 其他 ~10 处类 B 入口消除(call/method_call/member_access/index_access/template_lit/new_expr/postfix_inc/ternary/array_lit) | bootstrap/eval/ `grep -c "comptimeDepth > 0"` 预估 < 3 |
| **1.5d** | evalExpr 入口双轨彻底消除(ct/runtime 分支合一)+ 回 Phase 1 原目标(do-while / while / for 三处类 A 消除)+ §0.3 验收 5 项达成。**接口返回类型保持 int**(D098 §决策 1 §Phase A→B 接口稳定性) | `stmts_loop_classic.ss` `grep -c "comptimeDepth > 0"` = 0;tests/phase5/comptime_do_while_unknown_error.ss spike GREEN |
| 2 | `stmts_loop_classic.ss` 剩余 + `stmts_loop_forin.ss` 类 A | loop 族类 A 归 0(部分已在 1.5d) |
| 3 | `gen_decls.ss` / `gen_assigns.ss` var/assign 族 (~9 处类 A) | decl/assign 族类 A 归 0 |
| 4 | `call.ss` + `new_expr.ss` + `method_call.ss` 等 (~15 处类 A) | call/dispatch 族类 A 归 0 |
| 5 | 剩余 `gen/exprs/` + `class/` + `methods/` (~12 处类 A) | 类 A 全消 |
| 6 | `exprs_ct_reflect.ss` `genValCtReflectClasses` 合入 evalExpr | §差距 #2 全 close (残 1 个 genValCt 收口) |
| 7 | InternPool + Value/Type 拆分 (§差距 #3/#4) | §差距 #3/#4 全 close |
| 8 | comptime 块降为 flag + 残余类 C 边界规约审计 (§差距 #5) | §差距 #5 全 close, D093 §决策 全达成 |

**Phase 1.5 拆解单一事实源**:D169 §子拆解 表 — 本表与 D169 不一致以 D169 为准。

## Phase 1 受阻 — 三拒绝准则触发 + 升级 Phase 1.5 + D169 起首 (2026-05-20)

**Status:** Blocked at 5d36c8c — Phase 1.5a 起 Execute 接替

### 实证

2026-05-20 Phase 1 起首 ultrathink 实证 §0.3 §拒绝准则 3 条:

| # | §拒绝准则 字面要求 | 本轮实证 | 触发 |
|---|---|---|---|
| 1 | 若 do-while 消除需扩展 evalExpr 协议(MaybeVal 字段补充)→ 先完成协议扩展,回 §骨架 修订 | do-while 真消除 = unified dispatch = 需 MaybeVal class + comptimeMustBeKnown flag,callsite 用 mvKnown/mvVal 替代 isCt/payload | ✓ |
| 2 | 若发现类 B(`eval_expr.ss:25` 入口双轨)是 Phase 1 prerequisite → 升级 Phase 1.5 | `bootstrap/eval/` 类 B 入口双轨实证 **15+ 处**;do-while callsite 依赖 evalExpr 入口先走 MaybeVal 协议 | ✓ |
| 3 | 若 MaybeVal class 当前未充分 instance 化 → 先补 MaybeVal 协议接口(回 §骨架 修订 + 起 D169 子设计) | `grep -rn "class MaybeVal\|mvKnown\|mvVal\|comptimeMustBeKnown" bootstrap/` = **0** | ✓ |

### 物理不可达论证

do-while spike 在本地 hack 的三条物理可达路径,**全部违反规约**:

- **路径 α(搬家)**:把 `if (comptimeDepth > 0)` 分支体提到 stmts.ss dispatcher,分发 `genDoWhileComptime/genDoWhileRuntime` 两函数。`grep` 结果在 do-while 本文件消除,但 dispatcher 多一处,**总数不变** = D113 SEMA 模块拆分教训复发(commit `e3d8262` 同模式),违反 §第一性需求"消除双轨"
- **路径 β(扩 ct* 数据结构)**:do-while 局部新增 ct 状态(如循环计数 / 历史值缓存)模拟 fold,**违反 §0.3 验收 #2 "不引入新 ct*"** + §拒绝准则 #1
- **路径 γ(unified dispatch)**:让 do-while comptime / runtime 走同一 evalExpr/MaybeVal 协议,unified 后 `if (comptimeDepth > 0)` 消失 — **正确路径,但需 MaybeVal class + comptimeMustBeKnown flag 协议接口先确立**,触发 §拒绝准则 #1/#3

**结论**:路径 γ 是唯一合规路径,prereq = MaybeVal/comptimeMustBeKnown 协议接口(本轮未存)+ eval_expr.ss 类 B 入口先消(本轮未做)。Phase 1 在本轮**物理不可达**,字面授权升级 Phase 1.5。

### 决策

按 §0.3 §拒绝准则字面授权 + CLAUDE.md §Root Cause 优先第一法则("真做不到就停手不做,绝不接受次优 / workaround / 临时绕道"):

1. **本轮不改 bootstrap 代码** — do-while 局部不 hack,§拒绝准则 字面要求"先完成协议扩展再消除"
2. **起 D169** — MaybeVal class + comptimeMustBeKnown flag 协议接口详设(§拒绝准则 #3 字面授权产出物)
3. **升级 Phase 1.5** — §0.4 表插 1.5a/b/c/d 渐进路径,D169 §子拆解 表单一事实源
4. **本 Phase 0/1 状态闭环** — Phase 1 标 Blocked,Phase 1.5a 起 Execute 接替(下轮 next_prompt)

### 联动

- D169 §下一步 §Phase 1.5a 接续(MaybeVal + comptimeMustBeKnown 接口 stub + POC)
- 本 §下一步 表更新 — Phase 1 → Phase 1.5a;D094 / D 骨架能力前置 子项部分覆盖于 D169(余 InternPool / Type-as-Value 留 D094)

## 下一步

- **[x] Done at 2983d8a** Phase 0: 反向倒退 audit + 三类混合分类 + 首批起手 spec(本节)
- **[ ] Blocked at 5d36c8c** Phase 1 Execute: `stmts_loop_classic.ss:120` comptime do-while 消除 spike — §拒绝准则 #1/#3 触发,详 §Phase 1 受阻;升级 Phase 1.5(D169 起首)
- **[x] Done at 3710016** Phase 1.5a Execute: **D098 §决策 1 4 helper**(`mvKnownOf`/`mvValOf`/`mvRuntime`/`mvError`,纯 int 形态 — D169 §A §修订 Superseded by D098 §决策 1)+ comptimeMustBeKnown flag + enterComptimeBlock/exitComptimeBlock + UNARY POC 4 处 mvRuntime + D169 §POC 失败实证 落档(详 D169 §子拆解 修订版 + §POC 失败实证)
- **[~] In Progress** Phase 1.5b Execute: eval_expr.ss UNARY/BINARY/TERNARY/NULL_COALESCE 5 处类 B 入口消除(callsite 走 `mvKnownOf`/`mvValOf`/`reg`)
  - **[x] Done at e423591** 1.5b 单点起手 — UNARY case 入口双轨消除(`bootstrap/eval/eval_expr.ss:23-74` 单 dispatch + `genVal` 反向编码回 mv 空间 + `mvKnownOf`/`mvValOf` 协议 + `comptimeMustBeKnown == 1` read callsite 首接入 → `comptimeError`)。RED→GREEN:`grep -c "comptimeDepth > 0" bootstrap/eval/eval_expr.ss` = 3 → 2(留 line 78 COMPTIME_EXPR 类 C / line 100 BINARY 类 B)。known double fold 留 1.5c interp*Double 双列入口落地(本轮 1.5b §POC 实测:`interpAsStr(double_tvId)` 跨读 tvS1 string 列恒得空串 → 0.0 regression,delegate genUnary 是临时 unified path 的合规出路)
  - **[x] Done at 4573341** 1.5b BINARY 子轮 — BINARY case 入口 ct-depth 字面消除(`bootstrap/eval/eval_expr.ss:96-157` per-op pre-route + 通用 binop int/bool runtime 走 mv 协议 + `comptimeMustBeKnown == 1` read callsite 第二接入)。NullCoalesce/Instanceof/As/Pow 按 op pre-route 不 eager genVal(避 delegate genBinary 后 `f()+g()` 函数调用副作用 emit 两次);通用 binop int/bool runtime 走 mv 协议(eager genVal + mvKnownOf 判定 + genIntBinary pre-eval reg);string compare / 非 int/bool / Pow 走 genBinary delegate(保 OLD 语义)。RED→GREEN:`grep -c "comptimeDepth > 0" bootstrap/eval/eval_expr.ss` 2 → 1(消 BINARY line 98 入口;留 line 76 COMPTIME_EXPR 类 C)。**§POC N3 实证 落档**(首版按 inferType pre-route 在 comptime 路径引入 17 处 i021/d123/spring regression — `let acc = ""` 注册 ctVars 而非 varTypes,inferType IDENT fallback "int" 致 `acc != ""` 走 int interpAsInt → 0 → Ne 恒 false;修正改 1:1 `comptimeDepth > 0 → comptimeMustBeKnown == 1` rename + 内部纯 valType dispatch 保 OLD 行为)。「真单 dispatch」(eager genVal + 纯 valType + 单 leaf gate)留 1.5d — 1.5c 先把 genBinary/genStringConcat/genValStringCompare 改 take pre-eval reg 才不出函数调用副作用 double-eval bug
  - **[x] Done(1.5c 起手吸收)** 1.5b 后续子轮 — TERNARY 子模块入口消除归 1.5c 同批(详 1.5c In Progress 子项)
- **[~] In Progress** Phase 1.5c Execute: bootstrap/eval/ 其他 ~10 处类 B 入口消除(ternary/short_circuit/index_access/template_lit/array_lit/ident/member_access/postfix_inc/method_call/call/new_expr 各自子模块)+ genBinary/genStringConcat/genValStringCompare 改 take pre-eval reg(消除 1.5b BINARY delegate 路径的 double-eval 桥)
  - **[x] Done at c9f8ff6** 1.5c 起手 — TERNARY case 入口 ct-depth 字面消(`bootstrap/eval/ternary.ss:10` 单点字面 rename `comptimeDepth > 0 → comptimeMustBeKnown == 1` + OLD silent null `ctVal(interpNewNull())` 升 loud error `comptimeError("ternary condition not compile-time known", astId)` + `comptimeMustBeKnown == 1` 第三 read callsite 接入)。本子模块 cond 已先 `genVal + isCt` 判定(line 5-9),本轮 1:1 字面消;真单 dispatch(eager genVal + mv 协议 + 桥消除)留 1.5d 统一收口(D169 §POC N3 §1.5c/d 物理依赖链 — 1.5c 后续子轮需先把 genBinary/genStringConcat/genValStringCompare 改 take pre-eval reg 才不出函数副作用 double-eval bug)。对齐 1.5b UNARY (e423591) 单点起手 + BINARY (4573341) 子轮 OLD silent → loud error 升级模式;对齐 plain string sibling one-liner 风格(`eval_expr.ss:76` / `index_access.ss:18` / `template_lit.ss:36`)。RED→GREEN:`grep -c "comptimeDepth > 0" bootstrap/eval/ternary.ss` = 1 → 0;`comptimeMustBeKnown == 1` read callsite 累计 4 active(UNARY 2 + BINARY 1 + 本轮 TERNARY 1)
  - **[~] In Progress(2026-05-20 本轮)** 1.5c short_circuit 子轮 — SHORT_CIRCUIT case 入口 ct-depth 字面消(`bootstrap/eval/short_circuit.ss:13` 单点字面 rename `comptimeDepth > 0 → comptimeMustBeKnown == 1` + OLD silent null `ctVal(interpNewNull())` 升 loud error `comptimeError(`short-circuit '${op}' operand not compile-time known`, astId)` + `comptimeMustBeKnown == 1` 第五 read callsite 接入)。本子模块 left cond `lv` 已先 `genVal + isCt` 判定(line 5-12),本轮 1:1 字面消(单 dispatch 形态 sibling 间最干净 +1/-1 swap,无 inferType pre-route 风险 — D169 §POC N3 17 处 regression 复发预防);真单 dispatch(eager genVal + mv 协议 + 桥消除)留 1.5d 统一收口(D169 §POC N3 §1.5c/d 物理依赖链)。对齐 1.5c 起手 (c9f8ff6) TERNARY 子轮 OLD silent → loud error 升级模式;对齐 plain string sibling one-liner 风格(`eval_expr.ss:76` / `ternary.ss:10` / `index_access.ss:18` / `template_lit.ss:36` 四处一致)。RED→GREEN:`grep -c "comptimeDepth > 0" bootstrap/eval/short_circuit.ss` 1 → 0;`comptimeMustBeKnown == 1` read callsite 累计 5 active(UNARY 2 + BINARY 1 + TERNARY 1 + 本轮 SHORT_CIRCUIT 1)
  - **[ ] Planned** 1.5c 余下子轮 — index_access/template_lit/array_lit/ident/member_access/postfix_inc/method_call/call/new_expr ~8 处类 B 入口消除 + genBinary/genStringConcat/genValStringCompare 接口扩(take pre-eval reg)
- **[ ] Planned** Phase 1.5d Execute: evalExpr 入口双轨彻底消除(ct/runtime 分支合一)+ 回 Phase 1 原目标(do-while / while / for 类 A 消除)+ §0.3 验收 5 项达成。**接口返回类型保持 int**(D098 §决策 1 §Phase A→B 接口稳定性)
- **[x] Done at D098(2026-04-18)+ D099(2026-04-18)+ D111(2026-04-18)+ D112(2026-04-20)+ D117(2026-04-21)** D093 §张力 1-3 "MaybeVal / InternPool / Type-as-Value 详设" — 由 D098 §决策 1/2/3 集中决策,各 Phase 已落地:D098 §决策 1 §Phase A 编码 → D099 落 eval_expr.ss:1-5 + gen/gen_maybeval.ss;D098 §决策 2 §Phase B Meta InternPool → D117 落;D098 §决策 3 Phase A `comptimeTypeAliases` 消除 → D112 落。**D094 由 D098 承接 supersede**,InternPool/Type-as-Value 不再另起 D094
- **[x] Done at 2026-05-20** 验证 D093 骨架所需的 SS 语言能力缺口 — 见 D169 §SS 语言能力前置实证修订版(全局 int flag / error 机制 / 顶层 helper 函数 / int 符号位运算 全部齐备)

**本节落档后,Phase 1.5a 起 Execute 轮**;每 sub-phase 完成时双轨必须**局部消除**(不保留过渡态,§张力 #4 联动)。
