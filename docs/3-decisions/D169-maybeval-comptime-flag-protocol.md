# D169: MaybeVal helper + comptimeMustBeKnown flag — D093 §骨架 协议接口详设

**Status:** §A class 形态 **Superseded by D098 §决策 1**(2026-05-20 ultrathink 实证 — 详 §A §修订)— §A 改纯 int 4 helper(`mvKnownOf` / `mvValOf` / `mvRuntime` / `mvError`),§B comptimeMustBeKnown flag + §C evalExpr 接口 + §子拆解 1.5b/c/d 路径**保留有效**;**Phase 1.5a Done at 3710016** — 4 helper 落 `bootstrap/eval/interp_value.ss:207-218` + comptimeMustBeKnown flag 落 `bootstrap/eval/ct_driver.ss:25` + enter/exit 落 `bootstrap/eval/ct_driver.ss:27-35` + `runComptimeBlockBody` 改用 enter/exit + UNARY POC 4 处 mvRuntime + §POC 失败实证 落档;**Phase 1.5b 单点起手 Done at e423591** — UNARY case 入口双轨消除(`eval_expr.ss:23-74` 单 dispatch + `genVal` 反向编码回 mv 空间 + `mvKnownOf`/`mvValOf` 协议 + `comptimeMustBeKnown` read callsite 首接入 → `comptimeError`),`grep -c "comptimeDepth > 0" eval_expr.ss` = 3 → 2;**Phase 1.5b BINARY 子轮 Done at 4573341** — BINARY case 入口 ct-depth 字面消(`eval_expr.ss:96-157` per-op pre-route + 通用 binop int/bool runtime 走 mv 协议 + `comptimeMustBeKnown == 1` read callsite 第二接入),`grep -c "comptimeDepth > 0" eval_expr.ss` 2 → 1(留 line 76 COMPTIME_EXPR 类 C);**§POC N3 实证 落档**(首版按 inferType pre-route 在 comptime 路径引入 17 处 i021/d123/spring regression — `let acc = ""` 注册 ctVars 而非 varTypes,inferType IDENT fallback "int" 致 `acc != ""` 走 int interpAsInt → 0 → Ne 恒 false;修正改 1:1 字面 rename + 内部纯 valType dispatch 保 OLD 行为);**Phase 1.5c 起手 In Progress(2026-05-20 本轮)** — TERNARY 子模块 (`ternary.ss:10`) 入口 ct-depth 字面消 + silent null → loud error 升级 + `comptimeMustBeKnown == 1` 第三 read callsite 接入,`grep -c "comptimeDepth > 0" bootstrap/eval/ternary.ss` 1 → 0;short_circuit/index_access/template_lit/array_lit/ident/member_access/postfix_inc/method_call/call/new_expr ~9 处 + 接口扩留 Phase 1.5c 后续子轮
**Depends on:** D088(Zig 路线), D093(SEMA 单 dispatch §骨架 §SS 本质一样骨架), **D098(MaybeVal 编码 / InternPool / Type-as-Value 详设 — §决策 1 物理编码权威)**, D099(D098 §决策 1 §Phase A 编码实施 — eval_expr.ss:1-5 mv 编码契约已落)
**Date:** 2026-05-20
**Last Updated:** 2026-05-20(§A class 形态 Superseded by D098 §决策 1 — D169 立项时未引 D098/D099 链条,经 ultrathink D 文档对照核查发现冲突)

## 第一性需求

D093 §决策 §SS 本质一样骨架 第一行 `class MaybeVal { known: bool, val: int }`(概念示意,D098 §决策 1 行 35 论证为接口恒定 + 物理编码随 Phase 演进 — Phase A 物理实现 = **纯 int 4 helper**,非 class)与 §骨架 §enterComptimeBlock 的 `comptimeMustBeKnown` flag 是 SS 等价 Zig `?Value` + comptime 块语义的**协议接口**,**没有这两件协议接口,任何 callsite 消除 `if (comptimeDepth > 0)` 双轨分岔都只能搬家(类似 D113 SEMA 拆模块教训),根因双轨未消**。

**Why 链**:
- (L1) D093 §0.3 选 do-while 作 Phase 1 spike 起首,§验收 #1 要求 grep 消除一处 `comptimeDepth > 0`
- (L2) do-while comptime 真消除路径只有一条 — 让 comptime / runtime 走**同一个 evalExpr/mv dispatch**,unified 后 if 才消失(任何"上提 dispatcher / 抽出 ct 函数 / 扩 ct* 数据结构" 都是搬家或违反 §0.3 §拒绝准则 #2)
- (L3) 末层断言可观测否定证据:`grep -rn "function mvKnownOf\|function mvValOf\|comptimeMustBeKnown" bootstrap/` = **0** 实测(2026-05-20 §A §修订后修订 RED pattern — 原 `class MaybeVal` 形态已废,改为 D098 §决策 1 4 helper 显式落地的 grep)— 协议接口显式 helper 物理上不存在,Phase 1 spike 在 do-while 本地无 hack 可达路径

## 触发链(2026-05-20 Phase 1 起首 ultrathink 实证)

D093 §0.3 §拒绝准则 3 条本轮实证触发:

| # | §拒绝准则 字面要求 | 本轮实证 | 触发 |
|---|---|---|---|
| 1 | 若 do-while 消除需扩展 evalExpr 协议(MaybeVal 字段补充)→ 先完成协议扩展,回 §骨架 修订 | do-while 真消除 = unified dispatch = 需 MaybeVal 4 helper(mvKnownOf/mvValOf/mvRuntime/mvError,D098 §决策 1 字面规约)+ comptimeMustBeKnown flag,callsite 用 mvKnownOf/mvValOf 替代裸 isCt/payload | ✓ |
| 2 | 若发现类 B(`eval_expr.ss:25` 入口双轨)是 Phase 1 prerequisite → 升级 Phase 1.5 | `bootstrap/eval/` 类 B 入口双轨实证 **15+ 处**(eval_expr/postfix_inc/short_circuit/call/template_lit/member_access/ternary/new_expr/ident/index_access/method_call/array_lit);do-while callsite 依赖 evalExpr 入口先走 mv 协议 | ✓ |
| 3 | 若 MaybeVal class 当前未充分 instance 化 → 先补 MaybeVal 协议接口(回 §骨架 修订 + 可能起 D169 子设计) | `grep -rn "function mvKnownOf\|function mvValOf\|function mvRuntime\|function mvError\|comptimeMustBeKnown" bootstrap/` = **0**,显式 helper 完全未 instance 化(D093 §骨架 §SS 本质一样骨架 第一/三行规约仅文字;D099 commit `53066f0` mv 编码契约已隐式落注释 + callsite 直接 tagged int 操作,但 D098 §决策 1 字面 4 helper 函数未显式定义) | ✓ |

**三条全中** → D093 §0.3 §拒绝准则字面授权路径 = 回 §骨架 修订 + 起 D169 子设计 + 升级 Phase 1.5。本 D169 即此授权产出物。

## 协议接口形态

### A — MaybeVal 纯 int 4 helper(2026-05-20 §修订 — Superseded by D098 §决策 1)

**§修订摘要**:D169 立项时(2026-05-20)未引 D098(2026-04-18 立项,D093 §张力 1-3 字面授权产出物),把 D093 §骨架 §SS 本质一样骨架 第一行 `class MaybeVal { known: bool, val: int }` 文字误读为**物理强制**(实为 D098 §决策 1 行 35 已论证的"概念容器 — 接口恒定,物理编码随 Phase 演进"概念示意)。ultrathink D 文档对照实证 D098 § 决策 1 § Phase A "纯 int 符号位辨识"已**完整落地**(D099 commit `53066f0` evalExpr 最小骨架 + eval_expr.ss:1-5 mv 编码契约 + gen/gen_maybeval.ss valOf/valType),且 D098 §决策 1 已论证 class 视图不落 bootstrap 的物理理由(linter N1 +1~+3 regression / 与 D099 编码契约冲突 / 跨 Phase 接口反复迁移)。**结论**:§A class 形态作废,Phase 1.5a 落 D098 §决策 1 字面规约的**纯 int 4 helper**。

```ss
// bootstrap/eval/interp_value.ss(目标新增 — Phase 1.5a 落地)
// D098 §决策 1 §Phase A 编码契约(已隐式落 D099 commit 53066f0 — 本轮显式 helper 化)
//   mv >= 0   → known=true,  val = mv             (Value 句柄,ctVal tagged int)
//   mv <= -2  → known=false, regId = -mv - 1      (regTable 1-based)
//   mv == -1  → error 哨兵,禁止 reg()

// 构造器(命名错开访问器避 SS 函数重载 int 同名 dispatch 失效,D098 §新张力 6)
function mvRuntime(regId: int): int { return 0 - regId - 1 }   // regId 1-based → mv <= -2
function mvError(): int { return 0 - 1 }                        // -1 哨兵

// 访问器(命名 *Of 与构造器 mvKnown/mvRuntime/mvError 错开)
function mvKnownOf(mv: int): int { if (mv >= 0) { return 1 } return 0 }
function mvValOf(mv: int): int {
    if (mv >= 0) { return mv }              // known=true:Value 句柄(payload 等价 mv 本身,bit 30 含 ct tag)
    if (mv == 0 - 1) { return 0 - 1 }       // error:返回 -1 哨兵
    return 0 - mv - 1                        // runtime:decode regId
}
```

**为何不落 class MaybeVal**(D098 §决策 1 行 42-47 字面论证 + 本 §修订实证):

| # | 物理理由 | 实证 |
|---|---|---|
| 1 | linter N1 regression | class 引入 MEMBER_ACCESS(bootstrap 其他文件未用 user class field 读)→ +1;若 `known: bool` 则再 +2(TRUE_LIT/FALSE_LIT bootstrap 未用 bool 字面量)。必触 §反射根因 gate B 路径申报扩容 |
| 2 | 与 D099 编码契约冲突 | bootstrap 全文已用 `if (isCt(v))` / `payload(v)` / `0 - constVal(x) - 1` 直接 tagged int 操作(54 处 callsite + D099 注释契约),class 形态需引入 mvFromTagged/mvToTagged 双向桥包装层,**接口形态反复迁移两次**(1.5a-c 包装,1.5d 拆包装) |
| 3 | 业界演化对标反向 | Zig (`?Value` tag bit/union)、Rust (`Option<T>` niche optimization)、Haskell (`Maybe` sum type)、Crystal (`Union(T,Nil)`)同类编译器普遍走 tag/union/optional,**不用 class**。SS 用 int 符号位是 SS 等价 niche(Zig 原生路径) |
| 4 | N 年返工度 | Phase B InternPool 引入时 D098 路径 mv 物理含义换层(tagged int → pool index)接口 transparent,callsite 0 改动;D169 §A class 路径 1.5d 必拆 mvFromTagged 包装层 + Phase B 内部存储再换 = 2 次返工 |
| 5 | SS 函数重载缺口 | D098 §新张力 6 已证 SS 函数重载 int vs ptr 同名 dispatch 失效;D169 §A `mvKnown(m: MaybeVal)` 直接撞 D098 构造器 `mvKnown(valId: int)` 同名不同语义,无法共存。本 §修订改名 `mvKnownOf` 错开 |

**保留的 class 视图**(仅作文档 / 测试,与 D098 行 102 一致):`/tmp/maybeval_probe.ss` 已验 `class MaybeVal { known: int, val: int }` 可跑通,作为未来取消 linter N1 约束后的后备形态。**Phase 1.5a 实现用纯 int 4 helper**,class 视图本 D 文档不落到 bootstrap。

**字段 val 编码语义**(D093 §张力 #1 + D098 §决策 1 §语义 锚定):
- `known=1`(mv >= 0):val = mv 本身(ctVal tagged int 含 bit 30 ct tag);callsite 取 payload 仍调 `valOf(mv)` / `payload(mv)`(已落 bootstrap)
- `known=0, regId >= 1`(mv <= -2):val = `0 - mv - 1`(regTable 1-based 索引);callsite 调 `reg(mvToTagged_equiv)` 拿 LLVM 寄存器 string,Phase A 等价 `regTable[mvValOf(mv) - 1]`
- `known=0, val=-1`:错误哨兵,callsite 禁止 `reg()`(`mvError()` 构造)

### B — comptimeMustBeKnown flag(D098 §决策 1 行 92 实施细化)

D098 §决策 1 行 92 `if (comptimeMustBeKnown == 1) { return comptimeError(...) }` 已规约 flag 语义,但未规定 enter/exit 函数封装。本 §B 是 D098 行 92 的实施细化(scope 进出对称管理 + 与 comptimeDepth 同步)。

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

### C — evalExpr 接口签名(2026-05-20 §修订 — Superseded by D098 §决策 1 §Phase A → B 接口稳定性)

**当前**(2026-05-20 实测,D099 已落):
```ss
function evalExpr(astId: int): int   // 返 mv(D099 编码契约:mv >= 0 known / mv <= -2 runtime / mv == -1 error)
                                      // 已部分 callsite: isCt(v) + payload(v) + reg(v)(直接 tagged int 操作)
                                      // 待显式化 callsite: mvKnownOf(mv) + mvValOf(mv) + reg(mv)
```

**Phase 1.5a 显式化**(helper 显式定义,**不动**返回类型):
```ss
function evalExpr(astId: int): int   // 仍返 mv int 编码(D099 契约不变)
                                      // 新 callsite: mvKnownOf(mv) 替代 isCt(v);mvValOf(mv) 替代 payload(v)
```

**Phase 1.5d 入口双轨消除**(返回类型仍 int,合并 ct/runtime 分支):
```ss
function evalExpr(astId: int): int   // 仍返 mv int 编码(接口跨 Phase 稳定 — D098 §决策 1 §语义恒定)
                                      // ct/runtime 入口合一,callsite 全走 mvKnownOf/mvValOf/reg 三访问器
```

**Phase B 终态**(InternPool 引入后,D098 §决策 2 §Phase B):
```ss
function evalExpr(astId: int): int   // 仍返 mv int 编码,**接口完全不变**
                                      // mv >= 0 物理含义从 ctVal tagged int → InternPool index
                                      // callsite 透明(经 valOf/valType 访问器屏蔽差异)
```

**为何接口跨 Phase 稳定 + 不返 class**(D098 §决策 1 §保留的 class 视图 + §决策 2 §Phase B):接口语义恒定(known + val 二元),物理编码随 Phase 演进(Phase A tagged int → Phase B pool index → Phase C 可选纯 Value pool),所有 Phase 都用 int 承载(`mvKnownOf` / `mvValOf` 访问器跨 Phase 透明),callsite **不需要二次迁移**。D169 §A 原 class 路径(1.5a-c 包装 + 1.5d 拆包装)被 §A §修订作废,本 §C 跟着 §A 同步修订。

## Phase 1.5 子拆解

| Phase | 范围 | 验收 |
|---|---|---|
| **1.5a** | **D098 §决策 1 4 helper**(`mvKnownOf` / `mvValOf` / `mvRuntime` / `mvError`)显式落 `bootstrap/eval/interp_value.ss` + comptimeMustBeKnown flag + enterComptimeBlock/exitComptimeBlock 落 `bootstrap/eval/ct_driver.ss` + POC callsite(eval_expr.ss UNARY mvRuntime 构造器 4 处) | (1) `grep "function mvKnownOf\|function mvValOf\|function mvRuntime\|function mvError" bootstrap/eval/interp_value.ss` = 4;(2) `grep "let comptimeMustBeKnown" bootstrap/eval/ct_driver.ss` ≥ 1;(3) `grep "function enterComptimeBlock\|function exitComptimeBlock" bootstrap/eval/ct_driver.ss` = 2;(4) `runComptimeBlockBody` 改用 enterComptimeBlock/exitComptimeBlock;(5) POC callsite(`eval_expr.ss` UNARY case 单点)走 `mvRuntime` 构造器 4 处(`0 - constVal(s) - 1 → mvRuntime(constVal(s))`)— **限 evalExpr 返值构造器侧**,不替换 `isCt`/`payload`(两套编码空间不等价:mv 编码符号位 vs ctVal/constVal positive bit 30,`isCt(negative_mv) = 1` 在 i32 bit 30 下会错位,见 §POC 失败实证);**mvKnownOf/mvValOf/mvError 访问器在 1.5b 入口双轨消除时 evalExpr 内部 mv 空间触发应用点**;(6) bootstrap 三阶段 GREEN + phase2-phase5 GREEN(baseline 持平,无本轮 regression) |
| **1.5b** | eval_expr.ss 入口双轨消除(UNARY/BINARY/TERNARY/NULL_COALESCE 5 处类 B)— evalExpr 改为单 dispatch 形态,callsite 用 `mvKnownOf` 判定 | eval_expr.ss `grep -c "comptimeDepth > 0"` 5+ → 0;入口双轨消;全测 GREEN |
| **1.5c** | bootstrap/eval/ 其他模块类 B 入口消除(call/method_call/member_access/index_access/template_lit/new_expr/postfix_inc/ternary/array_lit ~10 处) | bootstrap/eval/ `grep -c "comptimeDepth > 0"` 大幅降(预估 < 3);全测 GREEN |
| **1.5d** | evalExpr 入口双轨彻底消除(ct/runtime 分支合一)+ 回 Phase 1 原目标 — do-while + while + for 三处类 A 消除(走单 dispatch + `comptimeMustBeKnown` 错误路径)。**接口返回类型保持 int**(D098 §决策 1 §Phase A→B 接口稳定性),物理仍 mv int 编码,不引 class | `stmts_loop_classic.ss` `grep -c "comptimeDepth > 0"` = 0;D093 §Phase 1 §0.3 验收 5 项全达成(含新增 `tests/phase5/comptime_do_while_unknown_error.ss` spike 测试) |

**每个 sub-phase 完成时双轨必须局部消除**(D093 §张力 #4,不允许"过渡态"长期共存)。

### §POC 失败实证(Phase 1.5a 首次 Execute 拦截 — 2026-05-20)

Phase 1.5a 首次 POC 把 UNARY ct 分支行 27 `isCt(ctUv) == 0` 和 runtime 分支行 43 `isCt(ov) == 1` 替换为 `mvKnownOf` — 触 phase5 `instanceof_basic.ss` / `instanceof_error.ss` 2 处 regression(`!(x instanceof Y)` UNARY Not 路径 exit 1)。根因 grep + probe 实测:

- **`gen/exprs/exprs.ss:68 genVal`** 对 evalExpr 返值做解码:`const mv = evalExpr(id); return mv >= 0 ? mv : 0 - mv - 1`(known mv 直传,runtime negative mv 解码成 positive regId)
- **解码后**调用方拿到 **positive 空间编码**(ctVal `bit 30 set` vs constVal `bit 30 clear`),`isCt` 是该空间权威(D089 tagged value infrastructure)
- **mv 空间编码**(D098 §决策 1 §Phase A)在 evalExpr 内部用 — `mv >= 0` known / `mv <= -2` runtime / `mv == -1` error,`mvKnownOf` 是该空间权威
- **两空间不等价**:probe `bin/ss run /tmp/mv_probe.ss` 实测 `isCt(mvRuntime(5)) = 1`(因为 -6 i32 补码 bit 30 为 1)、`payload(mvRuntime(5)) = 1073741818`(完全错乱)— **isCt 协议在 negative mv 空间失效**
- POC 把 genVal 解码后 positive 编码上的 `isCt` 替换为 mv 空间 `mvKnownOf`,**逻辑反转**(positive 永远 >= 0 → mvKnownOf = 1 → 总走 ct 分支,runtime ref 被误当 ct 处理)

**修正**:POC 仅替换 mvRuntime 4 处构造器(evalExpr 返值,真正 mv 空间);mvKnownOf/mvValOf/mvError 访问器在 1.5b 入口双轨消除后 evalExpr 内部走 evalExpr 子调用拿 raw mv 不解码时才有契合应用点。

**教训**:helper 命名空间隔离(isCt+payload positive 空间 vs mvKnownOf+mvValOf mv 空间)未在 D098 §决策 1 字面规约里明示,本 §POC 失败实证补 D098 §决策 1 行 60(`mvKnown(valId): int { return valId }` 构造器)隐含的 callsite 边界 — **构造器返值进入 mv 空间;访问器从 mv 空间读;genVal 是 mv 空间 → positive 空间的桥;桥之外的 callsite 必用 isCt+payload**。Phase 1.5b 入口双轨消除时,要先把 callsite 改走 evalExpr(raw mv) 路径(去掉 genVal 桥),mvKnownOf/mvValOf 才正确替代 isCt/payload。

### §POC 失败实证 N3(Phase 1.5b BINARY 子轮 中段拦截 — 2026-05-20 commit 4573341)

Phase 1.5b BINARY 子轮首版尝试**真单 dispatch** — eager `genVal(left)` + `genVal(right)` 后按 op type 用 `inferType` pre-route(string compare / Add+string / Pow / non-int-bool / int-bool 五分支),触 17 处 phase5 regression:
- `tests/phase5/i021_requestbody*` (10+ 个文件 — RequestBody / 嵌套 array/map/optional 等 routes 注册全 fail "not found")
- `tests/phase5/i021_pathvariable.ss` / `i021_multi_param.ss` / `i021_requestheader.ss`
- `tests/phase5/d123_phase1_smoke.ss` (expected "AlphaController,BetaController" got "AlphaControllerBetaController" — 逗号丢失)
- `tests/phase5/d096_p4_l2_reactive.ss`

根因 grep + probe 实测(repro `comptime { let acc = ""; while ... if (acc != "") + "," ; ... }` 前 = "XXX" / 后 = "X,X,X"):

- **`comptime ctVars` 与 `varTypes` 是两个独立 var 注册通道**:`let acc = ""` 在 comptime 块内通过 `ctVars.set("acc", ctVal(stringTvId))` 注册到 `ctVars` Map,**不写入** `varTypes`(后者只跟踪 runtime 命名变量)
- **`gen/gen_types.ss:331-336 inferType IDENT`** 调用 `getVarType(name)`,对 comptime-only IDENT 返空 → fallback "int":
  ```ss
  if (kind == "IDENT") {
      const vType = getVarType(nGetS1(id))
      if (vType != "") { return vType }
      if (funcRetTypes.has(nGetS1(id)) == 1) { return "fn" }
      return "int"   // ← comptime IDENT fallback 致语义错配
  }
  ```
- **首版 BINARY 按 inferType pre-route**:`blt = inferType(nGetI1(astId))` 对 comptime `acc` 返 "int",`brt = inferType(nGetI2(astId))` 对 `""` 返 "string"。条件 `blt == "string" && brt == "string"` 为 FALSE → **string-compare 分支不走**,落到 "non int/bool" 分支 → `interpIntOp("Ne", interpAsInt(stringTvId), interpAsInt(emptyStringTvId))` → `interpAsInt` 读 `tvI1[stringId]` = 0 → `0 != 0 ? 1 : 0` = 0 → `acc != ""` **恒 false** → 逗号永不添加 → 17 处依赖 comptime 字符串拼接的测试集体 fail

**修正(commit 4573341 落地)**:放弃首版"真单 dispatch"目标,改 1:1 字面 rename `comptimeDepth > 0 → comptimeMustBeKnown == 1`,**comptime 路径走 OLD 整块结构(纯 valType dispatch)** — `valType(genVal(lhs))` 返 comptime 值真实类型 "string",string-compare 分支正确触发。**「真单 dispatch」(eager genVal + 纯 valType + 单 leaf gate)推迟到 1.5d**,prereq:
1. **1.5c 重构 `genBinary` / `genStringConcat` / `genValStringCompare` 接口** — 改 take pre-eval reg(`(op, lReg, rReg, blt, brt) → string`),消除 BINARY 块 eager genVal 后 delegate 时的 double-eval 函数副作用 bug
2. 或者 **1.5c 把 comptime IDENT 类型查询并入 inferType** — `gen/gen_types.ss:331-336` 改 `if (ctVars.has(name)) { return valType(ctVal(parseInt(ctVars.getString(name)))) }` 让 inferType 走 ctVars 通道(注:需先评估循环依赖 + comptime 求值在 inferType 调用栈的副作用)

**教训**:`inferType` 是**静态类型查询**,只看 varTypes(runtime 命名 var)+ AST 节点 kind/literal,**不感知 comptime 求值动态值类型**。「按 inferType 路径分发 → callsite 用 valType 取值」是同函数内的**类型语义错配陷阱** — 静态 inferType 选错路 → 取 valType 时已经在错路 leaf 里。1.5d 真单 dispatch 必须先把 comptime IDENT 在 inferType 通道接通(1.5c 路径 2),或者所有 dispatch 走 eager genVal 后的 valType(1.5c 路径 1,需先接口扩),否则同一 bug 在 TERNARY/INDEX_ACCESS/MEMBER_ACCESS/CALL 等 子模块的 1.5c 推进时会**复发** — 本 N3 实证锁 1.5c/d 物理依赖链。

## SS 语言能力前置实证(2026-05-20 §A §修订后更新)

D093 §下一步 第 3 条要求"验证 D093 骨架所需的 SS 语言能力缺口"。本 D169 §A §修订后**改 4 helper 不落 class**,SS 语言能力前置实证:

| 能力 | 实证 |
|---|---|
| 全局 int flag | `let comptimeDepth = 0` 已是全局(`bootstrap/eval/ct_driver.ss:19`);`comptimeMustBeKnown` 同模式 |
| error 机制 | `comptimeError(msg, astId)` 已存(`bootstrap/eval/eval_expr.ss:66` 等 10+ callsite);本协议直接复用 |
| 顶层 helper 函数 | SS 完全支持(自举即证);bootstrap 大量顶层函数(`isCt`/`payload`/`ctVal` 等)与 4 helper 同模式 |
| int 符号位运算 | `mv >= 0` / `mv == 0 - 1` / `0 - mv - 1` 已在 D099 commit 53066f0 落 bootstrap(eval_expr.ss:1-5 头部注释 + 散布 callsite);本 §A 4 helper 是该编码契约的显式 helper 化 |

**结论**:能力齐备,无前置阻塞,Phase 1.5a 可直接落地。**class 视图作能力后备**(D098 行 102 + 本 §A §保留 — 仅作文档/测试,linter N1 约束解除时可启用)。

## 张力

1. ~~class vs tagged int 双形态共存期~~ **已消除**(2026-05-20 §A §修订 — D098 §决策 1 纯 int 编码 helper 接口跨 Phase 稳定,1.5a-c 无包装层 mental tax)
2. **comptimeMustBeKnown 与 comptimeDepth 双 flag 关系**:见 §B 节"为何不一刀替换"。终态 comptimeDepth 仅作嵌套统计,不参与 known 判定
3. ~~MaybeVal val 字段 known=0 时占位编码~~ **已统一**(D098 §决策 1 §语义:`val = -mv - 1` regTable 1-based 索引;`-1` 错误哨兵 — 跨 Phase A/B 稳定)
4. **何时把 evalExpr 改名为别的**:D093 §骨架 用名 `evalExpr`,SS 当前 `evalExpr` 已存在(`bootstrap/eval/eval_expr.ss`),名字一致;但语义上当前 evalExpr 内部仍是 `if (comptimeDepth > 0)` 入口双轨,1.5b 完成后才达骨架定义。不重命名,语义升级即可

## Rejected Alternatives

- **A: 跳过 D169 直接硬干 do-while spike** — 拒。违反 D093 §0.3 §拒绝准则 #1/#3 + §第一性需求"消除双轨"。任何 do-while 本地 hack 都是搬家或扩 ct*,等同 D113 教训复发
- **B: 起 D094(InternPool + Value-Type 拆分)替代 D169** — 拒。D094 §决策 §规则 1-3 已由 D098 §Depends on 承接保留,§张力 1-3(MaybeVal/InternPool/Type-as-Value)已由 D098 §决策 1/2/3 承接,本 D169 是 D098 §决策 1 显式 helper 化 + D098 §下一步 第 3 条 evalExpr Phase A 首批 1a Plan 的 Execute 起手
- **C: 把 MaybeVal 做成 sum type / union / tagged enum** — 拒。SS 无 sum type / union / tagged enum 原生支持,**int 符号位编码是 SS 等价 niche optimization**(Zig small enum / Rust Option<T> niche 同理),D098 §决策 1 已选定
- **D: 直接合并 tagged int 路径到 class,1.5a 一步替换** — 拒。**class 路径整体已被 §A §修订作废**(Superseded by D098 §决策 1),不再讨论替换粒度
- **E: 跳 Phase 1.5 直接 Phase 8(comptime 块降 flag,D093 §差距 #5 终态)** — 拒。Phase 2-7 prereq 未做,跨多个 Phase 跳跃违反底层依赖链(类 A 消除依赖类 B 消除依赖协议接口)
- **F**(2026-05-20 §A §修订新增):**坚持 class MaybeVal(D169 原 §A)而非 D098 §决策 1 纯 int** — 拒。物理理由 5 条详 §A 表格(linter N1 +1~+3 / D099 冲突 / 业界反向 / N 年 2 次返工 / SS 重载缺口);D093 §骨架 字面 class 是概念示意非物理强制(D098 §决策 1 行 35 已论证)

## 与上游 D 文档关系

- **D088** Zig 路线(comptime 单 dispatch 原理来源 — `Sema.zig` / `Value.zig`)
- **D092** 双轨 SEMA 实现(已被 D093 §历史语境 §1 替代,本 D169 不引用)
- **D093** SEMA 单 dispatch §骨架 §SS 本质一样骨架 — 本 D169 是其 **§骨架 协议接口细化 + Phase 1 触发链落档**;§A §修订后明确 D093 §骨架 字面 class 为概念示意,物理实现由 D098 §决策 1 定
- **D094** comptime purity §决策 §规则 1-3(由 D098 §Depends on 承接保留有效),§张力 1-3 MaybeVal/InternPool/Type-as-Value 已由 D098 §决策 1/2/3 承接 — 本 D169 不再覆盖 §张力 1-3,改为 D098 §下一步 第 3 条 evalExpr Phase A 首批 1a Plan 的 Execute 起手(Phase 1.5b/c/d 即 D098 §下一步 第 3 条同范围)
- **D098** MaybeVal 编码 / InternPool / Type-as-Value 详设(**2026-04-18 立项,本 D169 立项时漏引,§A §修订修正**)— §决策 1 §Phase A 纯 int 4 helper 为本 D169 §A 物理实现权威;§决策 2 §Phase B InternPool 已由 D117 (Meta 对象 InternPool) 部分落地;§决策 3 Phase A `comptimeTypeAliases` 消除已由 D112 落地
- **D099** D098 §决策 1 §Phase A 编码实施(commit `53066f0`)— eval_expr.ss:1-5 mv 编码契约 + gen/gen_maybeval.ss valOf/valType 已隐式落,本 D169 Phase 1.5a 即 D099 后续显式 helper 化(`mvKnownOf`/`mvValOf`/`mvRuntime`/`mvError` 4 helper 显式定义)
- **D117** Meta 对象 InternPool 承载(commit `6e264fd`)— D098 §决策 2 §Phase B 落地,本 D169 Phase A → Phase B 跨 Phase 接口稳定性论证的实施基础

## 下一步

- **[x] Done at 3710016** Phase 1.5a Execute(2026-05-20 本轮):**D098 §决策 1 4 helper**(`mvKnownOf`/`mvValOf`/`mvRuntime`/`mvError`)落 `interp_value.ss:207-218` + comptimeMustBeKnown flag 落 `ct_driver.ss:25` + enterComptimeBlock/exitComptimeBlock 落 `ct_driver.ss:27-35` + `runComptimeBlockBody` 改用 enter/exit + UNARY POC 4 处 mvRuntime(`eval_expr.ss:48/61/65/70`)+ §POC 失败实证 落档。RED→GREEN:`grep -c "function mvKnownOf\|function mvValOf\|function mvRuntime\|function mvError" bootstrap/eval/interp_value.ss` 0 → 4
- **[~] In Progress** Phase 1.5b Execute:eval_expr.ss 5 处类 B 入口消除(callsite 走 `mvKnownOf`/`mvValOf`/`reg`)
  - **[x] Done at e423591** 1.5b 单点起手 — UNARY case 入口双轨消除(`bootstrap/eval/eval_expr.ss:23-74` 单 dispatch + `genVal` 反向编码 `isCt(v) == 1 ? v : 0 - v - 1` 回 mv 空间 + `mvKnownOf` 判定 fold(`interpNewInt/Bool/Null + ctVal`)/ runtime emit IR + `mvRuntime(constVal(reg))` / `comptimeMustBeKnown == 1 && mvKnownOf == 0 → comptimeError` 三路径)。known double fold 留 1.5c interp*Double 双列入口(本轮 §POC N1:跨读 tvS1 string 列 → 0.0 regression)。RED→GREEN:`grep -c "comptimeDepth > 0" bootstrap/eval/eval_expr.ss` = 3 → 2
  - **[x] Done at 4573341** 1.5b BINARY 子轮 — BINARY case 入口 ct-depth 字面消(`bootstrap/eval/eval_expr.ss:96-157`)。架构:`if (comptimeMustBeKnown == 1) { ...内部纯 valType dispatch... }` 总块 + per-op runtime pre-route(NullCoalesce/Instanceof/As/Pow 不 eager genVal 避 delegate genBinary 后 `f()+g()` 函数副作用 emit 两次)+ 通用 binop int/bool runtime 走 mv 协议(eager genVal + mvKnownOf 判定 + genIntBinary pre-eval reg)+ string compare / 非 int-bool / Pow 走 genBinary delegate(保 OLD 语义)。RED→GREEN:`grep -c "comptimeDepth > 0" bootstrap/eval/eval_expr.ss` 2 → 1(消 BINARY line 98;留 line 76 COMPTIME_EXPR 类 C)。**§POC N3 实证 落档**(详 §POC 失败实证 N3 节):首版按 inferType pre-route 在 comptime 路径引入 17 处 i021_requestbody*/d123_phase1_smoke/spring_web_params 等 regression — comptime `let acc = ""` 注册 ctVars 而非 varTypes,inferType IDENT fallback 返 "int"(`gen/gen_types.ss:331-336`),致 `acc != ""` 走 int interpAsInt → 0 → Ne 恒 false;修正改 1:1 `comptimeDepth > 0 → comptimeMustBeKnown == 1` rename + 内部纯 valType dispatch(对齐 OLD 行为),「真单 dispatch」(eager genVal + 纯 valType + 单 leaf gate)留 1.5d
  - **[x] Done(1.5c 起手吸收)** 1.5b 后续子轮 — TERNARY 子模块入口消除归 1.5c 同批(详 1.5c In Progress 子项)
- **[~] In Progress** Phase 1.5c Execute:bootstrap/eval/ 其他 ~10 处类 B 入口消除(ternary/short_circuit/index_access/template_lit/array_lit/ident/member_access/postfix_inc/method_call/call/new_expr 各自子模块)+ genBinary/genStringConcat/genValStringCompare 接口扩 take pre-eval reg(消除 1.5b BINARY 中 NullCoalesce/Instanceof/As/Pow/string-compare delegate 路径的 double-eval 桥)
  - **[~] In Progress(2026-05-20 本轮)** 1.5c 起手 — TERNARY case 入口 ct-depth 字面消(`bootstrap/eval/ternary.ss:10`):`comptimeDepth > 0 → comptimeMustBeKnown == 1` 字面 rename + OLD silent null `ctVal(interpNewNull())` 升 loud error `comptimeError("ternary condition not compile-time known", astId)` + `comptimeMustBeKnown == 1` 第三 read callsite 接入。本子模块 cond 已先 `genVal + isCt` 判定(line 5-9),本轮 1:1 字面消(单 dispatch 形态 sibling 间最干净 +1/-1 swap);真单 dispatch(eager genVal + mv 协议 + 桥消除)留 1.5d(§POC 失败实证 N3 §1.5c/d 物理依赖链:1.5c 后续子轮需先 genBinary/genStringConcat/genValStringCompare 改 take pre-eval reg)。对齐 plain string sibling one-liner 风格(`eval_expr.ss:76` / `index_access.ss:18` / `template_lit.ss:36`)。RED→GREEN:`grep -c "comptimeDepth > 0" bootstrap/eval/ternary.ss` 1 → 0;`comptimeMustBeKnown == 1` read callsite 累计 4 active(UNARY 2 + BINARY 1 + 本轮 TERNARY 1)
  - **[ ] Planned** 1.5c 后续子轮 — short_circuit/index_access/template_lit/array_lit/ident/member_access/postfix_inc/method_call/call/new_expr ~9 处类 B 入口消除 + genBinary/genStringConcat/genValStringCompare 接口扩(take pre-eval reg)
- **[ ] Planned** Phase 1.5d Execute:evalExpr 入口双轨彻底消除(ct/runtime 分支合一)+ 回 Phase 1 原目标(do-while / while / for 类 A 消除)+ D093 §0.3 验收 5 项全达成。**接口返回类型保持 int**(D098 §决策 1 §Phase A→B 接口稳定性),不引 class

**本 D169 §A §修订落档后,Phase 1.5a 起 Execute 轮**;每 sub-phase 完成时双轨必须**局部消除**(不保留过渡态,D093 §张力 #4 联动)。
