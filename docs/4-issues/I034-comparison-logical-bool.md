# I034 — runtime comparison/logical→bool 推断残留致显示 parity 偏离

**父决策:** D171 §收口验收 runtime-parity 族(`docs/3-decisions/D171-sema-q2-comptime-coverage.md` 行 169);是 I033 字面量折叠 + comptime-bool-return 折叠的**镜像同根第三站点**(gen 层 bool→int 折叠族)。
**状态:** **[x] Done**(2026-05-29,commit `b3315ac`)。
**颗粒度:** 标准改(`gen_types.ss` 单站点 + 假设破裂闭合)。
**依赖:** I033(`gen_types.ss:278` 字面量站点)/ comptime-bool-return(`gen_types.ss:324` 站点)已落地的 `genExprAsString` bool 分支(`exprs_str_conv.ss:35`)+ `ss_joinBool`(`gen_methods.ss:544`)+ `inferType(UNARY)` 委派(`gen_types.ss:586`)。
**创建:** 2026-05-29
**编号溯源:** 本文件为 **I037 编号冲突修复**(2026-05-30)补建的 canonical 文件。comparison/logical→bool 工作自始即以 **I034** 落于 commit `b3315ac` / `i034_comparison_logical_bool.options.md` / `.bugfix` / `tests/phase5/i034_comparison_logical_bool.ss` / `bootstrap/gen/gen_types.ss:376,388` 注释,但 I034 号曾被 array-elem-infer backlog 占用(已迁 `I038`)。本文件令 I034 引用语义归位。详见 `I037-i034-issue-number-collision.md`。

---

## 现象 / RED

- `let b=1<2; ${b}`(模板)→ "1"(应 "true")
- `let c=true&&false; ${c}` → "0"(应 "false")
- `[1<2,3>4].join("-")` → "1-0"(应 "true-false")

偏离 comptime oracle `interpNewBool`(`interp_op.ss:50-55` 比较 + short-circuit 逻辑均返 bool tv)→ "true"/"false" + JS `String(1<2)="true"`。

## 根因(单一概念根 = gen 层把 comparison/logical/instanceof BINOP 折叠成 int)

`gen_types.ss:377` `inferType(BINARY)` 对 comparison(Eq/Ne/Lt/Gt/Le/Ge)+ logical(And/Or)+ instanceof 一律 `return "int"` → 三显示 sink(模板 / 拼接 / join)经 `inferType` 拿不到 "bool"。是 I033 字面量站点 `gen_types.ss:278` + comptime-bool-return 站点 `gen_types.ss:324` 的镜像同根**第三折叠站点**。

## 修复(候选 C 接口层根因 — inferType 单站点 + 假设破裂闭合)

- **站点 A(根)**:`gen_types.ss:377` comparison/logical/instanceof BINOP `return "int"` → `return "bool"`(各 cmp/短路/instanceof 出口仍 `zext i1→i32`,bool@IR=i32 `ssTypeToLLVM:750`/mangling `i`,**无 ABI break**)→ bool 类型经 `inferType` 流过 var 传播 / join dispatch(`ss_joinBool`)/ `genExprAsString` bool 分支 / Not-unary 委派,单一真相源,零新 runtime IR/函数。
- **假设破裂闭合**:`gen_types.ss:383` 算术/位运算 fallthrough 既有 `if(binLt=="i64")` guard 合并 `binLt=="bool"` → `return "int"`(JS bool→number 强制,防 `(a<b)+1` 误显 "true",parity comptime `(1<2)+1`=2;附带闭合 I033-latent `true+1` 漏)。

## 证据

- 方案对比:`i034_comparison_logical_bool.options.md`(bug_options GATE 6/6)
- bugfix 证据:`i034_comparison_logical_bool.bugfix`(`.bugfix` 6 gate PASS)
- 回归:`tests/phase5/i034_comparison_logical_bool.ss`(24 assert,含 rt==ct 逐一比对)
- commit `b3315ac`;bootstrap 三阶段固定点 + 全测 346→347(3 pre-existing 不变);reflection_health GATE PASS(gen_types 927≤1050);sunset GATE OK
- D171 §下一步 行 169

## 范围外(维持 backlog,不混入)

- global 顶层非字面量 comparison `let g=1<2` 全局物化 ptr null 路径 = 独立根因 → 后续由 `global_scalar_materialize`(int/bool) / `I035`(元素类型传播) / `I036`(double 物化)闭环。
- Map.getInt typed-getter 含混消息 = `I003b` strict marker,deferred。
