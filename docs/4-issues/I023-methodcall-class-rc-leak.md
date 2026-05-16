# I023 — METHOD_CALL 返 user class 的 owned/borrowed RC 协议错配 → over-retain + chain-temp 双泄漏

**父决策:** D168《统一双 RC 系统为 Perceus 主线》（RC 协议正确性）；axiom C4「Deterministic memory management only (Perceus RC)」
**状态:** Planned —— A/B 未实施，待 leak-观测 RED 落地后 Execute
**颗粒度:** 预估 A ~3-6 LOC（`gen_decls.ss` isOwnedExpr 1 分支）+ B ~15-30 LOC（`gen_methods.ss` genMethodCall 链式 receiver temp 释放）；需新增 leak-观测测试
**依赖:** 无（根因独立）；**B 依赖 A 先落地**（A 把 METHOD_CALL→class 标 owned 后，chain 中间 temp 才确定为 owned、才有 release 必要）
**创建:** 2026-05-16
**立项由:** SS-LIM-6 Execute 轮 RED 核验 —— `ss_lim6_jsonnode_chain_corruption.options.md` 原 §决策行选「A+B+E 三层联修」；实测 §E（push `emitRetainForType`）已由 `f21271d` 落地、`tests/ss_lim6_jsonnode_chain_corruption_test.ss` 10/10 稳定 GREEN、corruption 不复现。核实 §A/§B 是泄漏修复非 corruption 修复（SS-LIM-6 功能测试观测不到），按 MNK §衍生 issue 归档「非阻挡 → 独立立项」拆出。

---

## 问题

两个 RC 泄漏，均**不产生错值**，SS-LIM-6 功能测试（只断言 `v == ""`）观测不到：

**A 类 — over-retain leak**：`isOwnedExpr`（`bootstrap/gen/gen_decls.ss:60-75`）对 `METHOD_CALL` 硬 `return 0`（一律判 borrowed），不区分返回类型。但 user-class 方法的返回值实际是 **owned** —— callee `genReturn`（`gen_decls.ss:739`）对 borrowed 返回值已 `emitRetainForType` +1，`return new X()` 自带 +1，故**任何 user 方法返 class 都已 +1**（与 `CALL` 已 `isOwnedExpr==1` 对称）。`isOwnedExpr==0` 致 8 个调用点（`gen_assigns.ss:176/340/408`、`gen_decls.ss:647/657/739`、`stmts_simple.ss:106/140`）再 retain 一次 → `const x = obj.method()`（method 返 class）x 被 over-retain → PIR liveness drop 后 rc 永 ≥ 1 → 永不 free → leak（违反 axiom C4 确定性回收）。

**B 类 — chain intermediate temp leak**：`genMethodCall`（`bootstrap/gen/methods/gen_methods.ss:422`，line 453 `objVal = genExpr(objId)`）对链式 receiver `a.b().c()` 的中间结果 —— inner METHOD_CALL/CALL 返 owned class temp，被 outer 当 receiver 借用后**无人 release** → 每个 chain 中间 temp 每次求值 leak 一个 mimalloc block。

最小复现（即 SS-LIM-6 spike 代码，功能 GREEN 但泄漏）：

```ss
const arr = data.get("items")        // A 类:JsonNode.get 返 new JsonNode(owned),caller over-retain
const v = arr.get(k).asString()      // B 类:arr.get(k) 中间 JsonNode temp 无 release
```

---

## 单一根因

caller↔callee 的 **owned/borrowed RC 协议** 在 METHOD_CALL 的总入口分发器 `isOwnedExpr` 缺一格 —— METHOD_CALL 未按返回类型分派，user-class 返回值被误判 borrowed。A 修分发器（分类），B 是 A 的下游必然（分类成 owned 后，chain 中间 temp 才确定需 release）。同根因（协议错配）双修复点。

---

## 候选修法（来自 `ss_lim6_jsonnode_chain_corruption.options.md` §候选对比 A/B）

| 候选 | 层次 | 改动 |
|---|---|---|
| **A** | 数据层 / codegen 分发器 | `gen_decls.ss:64` `isOwnedExpr` METHOD_CALL 改 `if (isUserClass(inferType(nodeId)) == 1) return 1`，否则 `return 0`。与 `ss_lim2_array_class_indexed_write.options.md §A`「按 ssType 分派」同范式；与 `CALL` 已 `return 1` 对称 |
| **B** | 接口层 / chain temp 管理 | `gen_methods.ss:422` `genMethodCall`：receiver `objId` 是返 user class 的 METHOD_CALL/CALL 时，中间 temp 在该 method call 发射后 `emitReleaseForType` 释放（实现可选 wrapper-按 `preObj` 传入、或 `chainTempReleases` 显式 stack —— 注意嵌套 `a.b().c().d()` push/pop 正确性） |

实施序：**B 依赖 A** 先落地。

---

## 待补验收（本 issue 未做 — 待 Execute 轮）

- **leak-观测 RED**：SS-LIM-6 现有功能测试 GREEN 前后不变、观测不到 leak。需构造能量化泄漏的 RED —— 候选：大循环（N 万次 `obj.method()` / chain）+ mimalloc 活跃 block 统计探针 / rc 字段探针。leak RED 复现后才进 Execute。
- **A 巡检**：8 个 `isOwnedExpr` 调用点对称性；留意 `find()` 返 user class 元素（`inferType` line 503-506）/ `Map.get()` classV 返 `"X?"`（line 449）等 builtin 路径是否被 A 误判（builtin 元素访问的 owned/borrowed 语义与 user 方法不同 —— `Map.get` classV 已在 `genMapMethod` 内 retain，`find` 待核）。
- VCM 六验 + bootstrap 三阶段 Stage2=Stage3 + 全测 0 regression + `reflection_health_linter` GATE（A/B 触 `gen_decls.ss`/`gen_methods.ss` 反射邻域）。

---

## 备注

- **SS-LIM-6 corruption 本体已闭合**：由 §E（`gen_builtins.ss:140-143` `emitRetainForType` 替换 `ss_rc_retain`，`f21271d` 落地）消除；`options.md §跨修法联动` 原写「三层缺一环 corruption 仍存在」经 RED 实测（10/10 GREEN）证伪 —— 见 `ss_lim6_jsonnode_chain_corruption.options.md §实测修正`。
- **与 D168 时序**：A/B 是现存 RC 系统内的协议正确性 bug，**不依赖** D168 Phase 2-5 的 RC 合并即可独立修；但 D168 Phase 5「PIR 接入消除 30+ 处手工 retain/release」会重写本 issue 触及的 codegen 路径 —— A/B 应在 D168 Phase 5 之前修，否则 Phase 5 在错协议上铺路、后续返工。
- **scope 边界**：不碰 §C（lib/json wrapper 重设计，`options.md` 远期）、§D（PIR `INDEX_ACCESS` class init 漏 schedule，留 SS-LIM-7 独立 spike）。
