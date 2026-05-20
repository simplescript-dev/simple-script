# D169: MaybeVal class + comptimeMustBeKnown flag — D093 §骨架 协议接口详设

**Status:** Planned at 2026-05-20 — D093 Phase 1 受阻 触发(§拒绝准则 #1/#3 实证)落档,Phase 1.5a 起 Execute
**Depends on:** D088(Zig 路线), D093(SEMA 单 dispatch §骨架 §SS 本质一样骨架)
**Date:** 2026-05-20
**Last Updated:** 2026-05-20

## 第一性需求

D093 §决策 §SS 本质一样骨架 第一行 `class MaybeVal { known: bool, val: int }` 与 §骨架 §enterComptimeBlock 的 `comptimeMustBeKnown` flag 是 SS 等价 Zig `?Value` + comptime 块语义的**协议接口**,**没有这两件协议接口,任何 callsite 消除 `if (comptimeDepth > 0)` 双轨分岔都只能搬家(类似 D113 SEMA 拆模块教训),根因双轨未消**。

**Why 链**:
- (L1) D093 §0.3 选 do-while 作 Phase 1 spike 起首,§验收 #1 要求 grep 消除一处 `comptimeDepth > 0`
- (L2) do-while comptime 真消除路径只有一条 — 让 comptime / runtime 走**同一个 evalExpr/MaybeVal dispatch**,unified 后 if 才消失(任何"上提 dispatcher / 抽出 ct 函数 / 扩 ct* 数据结构" 都是搬家或违反 §0.3 §拒绝准则 #2)
- (L3) 末层断言可观测否定证据:`grep -rn "class MaybeVal\|comptimeMustBeKnown" bootstrap/` = **0** 实测 — 协议接口物理上不存在,Phase 1 spike 在 do-while 本地无 hack 可达路径

## 触发链(2026-05-20 Phase 1 起首 ultrathink 实证)

D093 §0.3 §拒绝准则 3 条本轮实证触发:

| # | §拒绝准则 字面要求 | 本轮实证 | 触发 |
|---|---|---|---|
| 1 | 若 do-while 消除需扩展 evalExpr 协议(MaybeVal 字段补充)→ 先完成协议扩展,回 §骨架 修订 | do-while 真消除 = unified dispatch = 需 MaybeVal class + comptimeMustBeKnown flag,callsite 用 mvKnown/mvVal 替代 isCt/payload | ✓ |
| 2 | 若发现类 B(`eval_expr.ss:25` 入口双轨)是 Phase 1 prerequisite → 升级 Phase 1.5 | `bootstrap/eval/` 类 B 入口双轨实证 **15+ 处**(eval_expr/postfix_inc/short_circuit/call/template_lit/member_access/ternary/new_expr/ident/index_access/method_call/array_lit);do-while callsite 依赖 evalExpr 入口先走 MaybeVal 协议 | ✓ |
| 3 | 若 MaybeVal class 当前未充分 instance 化 → 先补 MaybeVal 协议接口(回 §骨架 修订 + 可能起 D169 子设计) | `grep -rn "class MaybeVal\|mvKnown\|mvVal\|comptimeMustBeKnown" bootstrap/` = **0**,完全未 instance 化(D093 §骨架 §SS 本质一样骨架 第一/三行规约仅文字) | ✓ |

**三条全中** → D093 §0.3 §拒绝准则字面授权路径 = 回 §骨架 修订 + 起 D169 子设计 + 升级 Phase 1.5。本 D169 即此授权产出物。

## 协议接口形态

### A — MaybeVal class

```ss
// bootstrap/eval/interp_value.ss(目标新增 — Phase 1.5a 落地)
class MaybeVal {
    known: int   // 1 = compile-time known, 0 = runtime-only
    val: int     // known=1 → interpVal id(InternPool 索引或 tagged int payload);
                 // known=0 → 0(哨兵 — Phase 1.5a)或 LLVM 寄存器引用 idx(Phase 1.5d 起)
}

function mvNew(known: int, val: int): MaybeVal {
    let m = new MaybeVal()
    m.known = known
    m.val = val
    return m
}

function mvKnown(m: MaybeVal): int { return m.known }
function mvVal(m: MaybeVal): int { return m.val }

// 与 tagged int 形态双向编码(渐进迁移期共存)— Phase 1.5a 落地
function mvToTagged(m: MaybeVal): int {
    return m.known == 1 ? ctVal(m.val) : (0 - m.val - 1)
}

function mvFromTagged(v: int): MaybeVal {
    return mvNew(isCt(v), isCt(v) == 1 ? payload(v) : (0 - v - 1))
}
```

**字段 val 在 known=0 时的语义**(D093 §张力 #1 锚定 — 本 D169 落地):
- **Phase 1.5a stub 阶段**:`val = 0` 哨兵(callsite 走 mvKnown 判定先,不读 val)
- **Phase 1.5d 起**:`val = constVal idx`(等价当前 tagged int form `0 - constVal(reg) - 1`,callsite 通过 `reg(mvToTagged(m))` 拿 LLVM 寄存器 string)

### B — comptimeMustBeKnown flag

```ss
// bootstrap/eval/ct_driver.ss(目标新增 — Phase 1.5a 落地)
let comptimeMustBeKnown = 0   // 0/1 替代 comptimeDepth > 0 判定

function enterComptimeBlock() {
    comptimeMustBeKnown = 1
    comptimeDepth = comptimeDepth + 1   // depth 仍维护用于嵌套统计 / scope 链
}

function exitComptimeBlock() {
    comptimeDepth = comptimeDepth - 1
    if (comptimeDepth == 0) { comptimeMustBeKnown = 0 }
}
```

**与现有 comptimeDepth 双 flag 关系**:
- 短期(Phase 1.5a-c):**并存** — comptimeDepth 仍存在,新增 comptimeMustBeKnown 与之同步进出
- 中期(Phase 1.5d-e):callsite 逐步从 `comptimeDepth > 0` 迁移到 `comptimeMustBeKnown == 1`
- 终态(Phase 8,D093 §差距 #5 完成):comptimeDepth 仅保留嵌套统计 / scope 链作用,known 判定全走 comptimeMustBeKnown 单线

**为何不一刀替换 comptimeDepth**:`comptimeDepth` 在 `ctScopeStack` push/pop / `interpEnsureComptimeRoot` 等位置作为嵌套深度计数,语义独立于"must be known",不可简单合并(Zig 也是 Sema 状态 + comptime block flag 两层)。

### C — evalExpr 接口签名

**当前**(2026-05-20 实测):
```ss
function evalExpr(astId: int): int   // 返 tagged int(ctVal/constVal 编码)
                                      // callsite: isCt(v) + payload(v) + reg(v)
```

**Phase 1.5a 升级**(helper 包装,**不动**返回类型):
```ss
function evalExpr(astId: int): int   // 仍返 tagged int(渐进迁移期共存)
                                      // 新 callsite: mvKnown(mvFromTagged(v)) + mvVal(...)
```

**Phase 1.5d 终态**(class 化):
```ss
function evalExpr(astId: int): MaybeVal   // 返 MaybeVal class id
                                          // callsite: mvKnown(m) + mvVal(m) + reg(mvToTagged(m))
```

**为何分两步**:Phase 1.5a 引入 helper 不改返回类型,callsite 改动量最小(只换函数名 `isCt → mvKnown ∘ mvFromTagged`);返回类型升级到 class 在 1.5d 一次性完成,期间 callsite 已走 mvKnown/mvVal,改动局限于 evalExpr 内部 return 形态。

## Phase 1.5 子拆解

| Phase | 范围 | 验收 |
|---|---|---|
| **1.5a** | MaybeVal class + helper(mvNew / mvKnown / mvVal / mvToTagged / mvFromTagged)+ comptimeMustBeKnown flag + enterComptimeBlock/exitComptimeBlock + 1-2 callsite POC | (1) `grep "class MaybeVal" bootstrap/eval/interp_value.ss` ≥ 1;(2) `grep "let comptimeMustBeKnown" bootstrap/eval/ct_driver.ss` ≥ 1;(3) `runComptimeBlockBody` 改用 enterComptimeBlock/exitComptimeBlock;(4) POC callsite(eval_expr.ss UNARY case 单点)走 mvKnown/mvVal/mvFromTagged;(5) bootstrap 三阶段 GREEN + phase2-phase5 GREEN |
| **1.5b** | eval_expr.ss 入口双轨消除(UNARY/BINARY/TERNARY/NULL_COALESCE 5 处类 B)— evalExpr 改为单 dispatch 形态,callsite 用 mvKnown 判定 | eval_expr.ss `grep -c "comptimeDepth > 0"` 5+ → 0;入口双轨消;全测 GREEN |
| **1.5c** | bootstrap/eval/ 其他模块类 B 入口消除(call/method_call/member_access/index_access/template_lit/new_expr/postfix_inc/ternary/array_lit ~10 处) | bootstrap/eval/ `grep -c "comptimeDepth > 0"` 大幅降(预估 < 3);全测 GREEN |
| **1.5d** | evalExpr 返回类型升级 MaybeVal class + 回 Phase 1 原目标 — do-while + while + for 三处类 A 消除(走单 dispatch + comptimeMustBeKnown 错误路径) | `stmts_loop_classic.ss` `grep -c "comptimeDepth > 0"` = 0;D093 §Phase 1 §0.3 验收 5 项全达成(含新增 `tests/phase5/comptime_do_while_unknown_error.ss` spike 测试) |

**每个 sub-phase 完成时双轨必须局部消除**(D093 §张力 #4,不允许"过渡态"长期共存)。

## SS 语言能力前置实证

D093 §下一步 第 3 条要求"验证 D093 骨架所需的 SS 语言能力缺口"。本 D169 协议接口实证 SS 语言能力齐备:

| 能力 | 实证 |
|---|---|
| class bool 字段 | SS 用 `int` 1/0 表 bool;已广泛用(例 `isCt` 返 0/1)。MaybeVal `known: int` 直接复用 |
| 全局 flag | `let comptimeDepth = 0` 已是全局(`bootstrap/eval/ct_driver.ss:19`);`comptimeMustBeKnown` 同模式 |
| error 机制 | `comptimeError(msg, astId)` 已存(`bootstrap/eval/eval_expr.ss:66` 等 10+ callsite);本协议直接复用 |
| class 实例化 + helper 函数 | SS 完全支持(自举即证);`new MaybeVal()` + 方法调用零阻塞 |

**结论**:能力齐备,无前置阻塞,Phase 1.5a 可直接落地。

## 张力

1. **class vs tagged int 双形态共存期**:Phase 1.5a-c 期间 callsite 用 helper 包装(底层仍 tagged int),1.5d 才一次性升级 evalExpr 返回类型。共存期内 mvToTagged / mvFromTagged 是同构变换(O(1) 位运算),性能无损;但代码上两形态并存需 mental tax,通过 helper 命名(mv* prefix)+ §子拆解 表格锁定迁移轮次降低复杂度
2. **comptimeMustBeKnown 与 comptimeDepth 双 flag 关系**:见 §B 节"为何不一刀替换"。终态 comptimeDepth 仅作嵌套统计,不参与 known 判定
3. **MaybeVal val 字段 known=0 时占位编码**:1.5a 用 0 哨兵(callsite 走 mvKnown gate 先,不读 val);1.5d 起改为 constVal idx(等价当前 tagged int `0 - reg - 1` 编码)。两阶段验证后定稿
4. **何时把 evalExpr 改名为别的**:D093 §骨架 用名 `evalExpr`,SS 当前 `evalExpr` 已存在(`bootstrap/eval/eval_expr.ss`),名字一致;但语义上当前 evalExpr 内部仍是 `if (comptimeDepth > 0)` 入口双轨,1.5b 完成后才达骨架定义。不重命名,语义升级即可

## Rejected Alternatives

- **A: 跳过 D169 直接硬干 do-while spike** — 拒。违反 D093 §0.3 §拒绝准则 #1/#3 + §第一性需求"消除双轨"。任何 do-while 本地 hack 都是搬家或扩 ct*,等同 D113 教训复发
- **B: 起 D094(InternPool + Value-Type 拆分)替代 D169** — 拒。D094 是 D093 §差距 #3/#4,scope 远大于本 D169(InternPool 是 Value 去重,Value-Type 拆分动 TypedValue storage 整改),不是 Phase 1 spike 必需。本 D169 仅覆盖 §差距 #5 子集(MaybeVal + comptimeMustBeKnown),与 D094 解耦
- **C: 把 MaybeVal 做成 sum type / union / tagged enum** — 拒。SS 无 sum type,class 是唯一近原生方式(D093 §张力 #1 已锚)
- **D: 直接合并 tagged int 路径到 class,1.5a 一步替换** — 拒。callsite 数量大(全 bootstrap/eval/ + bootstrap/gen/exprs|stmts/),一步替换 = 大爆炸 LOC + 高 revert 风险,§子拆解 表格的 1.5a→1.5d 渐进路径是稳定推进必需
- **E: 跳 Phase 1.5 直接 Phase 8(comptime 块降 flag,D093 §差距 #5 终态)** — 拒。Phase 2-7 prereq 未做,跨多个 Phase 跳跃违反底层依赖链(类 A 消除依赖类 B 消除依赖协议接口)

## 与上游 D 文档关系

- **D088** Zig 路线(comptime 单 dispatch 原理来源 — `Sema.zig` / `Value.zig`)
- **D092** 双轨 SEMA 实现(已被 D093 §历史语境 §1 替代,本 D169 不引用)
- **D093** SEMA 单 dispatch §骨架 §SS 本质一样骨架 — 本 D169 是其 **§骨架 协议接口细化 + Phase 1 触发链落档**
- **D094** MaybeVal / InternPool / Type-as-Value 详设(D093 §下一步 第 2 条,InternPool / Type-as-Value 部分仍未起)— 本 D169 仅覆盖 MaybeVal + comptimeMustBeKnown 子集,InternPool / Type-as-Value 留待 D094

## 下一步

- **[ ] Planned** Phase 1.5a Execute:MaybeVal class + helper + comptimeMustBeKnown flag + enterComptimeBlock/exitComptimeBlock + 1-2 callsite POC(eval_expr.ss UNARY 单点)。RED:`grep -c "class MaybeVal" bootstrap/eval/interp_value.ss` = 0
- **[ ] Planned** Phase 1.5b Execute:eval_expr.ss 5 处类 B 入口消除
- **[ ] Planned** Phase 1.5c Execute:bootstrap/eval/ 其他 ~10 处类 B 入口消除
- **[ ] Planned** Phase 1.5d Execute:evalExpr 返回类型升级 MaybeVal class + 回 Phase 1 原目标(do-while / while / for 类 A 消除)+ D093 §0.3 验收 5 项全达成

**本 D169 落档后,Phase 1.5a 起 Execute 轮**;每 sub-phase 完成时双轨必须**局部消除**(不保留过渡态,D093 §张力 #4 联动)。
