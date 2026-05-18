# I023 — METHOD_CALL 返 user class 的 owned/borrowed RC 协议错配 → over-retain + chain-temp 双泄漏

**父决策:** D168《统一双 RC 系统为 Perceus 主线》（RC 协议正确性）；axiom C4「Deterministic memory management only (Perceus RC)」
**状态:** Planned —— leak-观测 RED 已落地并复现(见 §2026-05-18);A+B 对泄漏有效(实测 276MB→396KB)但**候选 A 实现机制不安全**(`isOwnedExpr` 调 side-effectful `inferType`),A/B 已回退 baseline,待 A 机制重设计后 re-Execute
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

## 2026-05-18 Execute 轮实测 —— RED 落地 + A 机制缺陷

**leak-观测 RED 已落地并复现** —— `tests/phase5/i023_methodcall_class_rc_leak.ss`：

- 泄漏模式放在 helper 函数 `leakRound`（`pirActive=1`，PIR 正确管理 class 局部）：`const x = box.make()`（A over-retain）+ `box.make().fresh()`（B chain-temp + y over-retain）。**不能放 `main`**：`main` 不跑 PIR（`gen_decls.ss:129`），其 class 局部走非-PIR 释放路径（`emitReleaseVarList` 对非-array user class 仍发旧系统 `ss_rc_release`，D168 §C.9「P3+ 切完统一」遗留）会混入无关泄漏噪声。
- 量化探针：编译 → 后台运行 → 外部采样 `/proc/<pid>/status` 的 `VmHWM`（峰值 RSS，单调）。无新增编译器能力 —— `ss_readFile` 对 `/proc`（size 0）不可用,改用外部 Bash 探针。
- **实测**：当前编译器峰值 RSS ≈ **276 MB**（3M 迭代 × ~3 Cell 泄漏）；对照（同结构循环改 `new Cell()` NEW_EXPR）= **404 KB** → 证明脚手架有界,276 MB 全系 METHOD_CALL 泄漏。

**A+B 对泄漏有效（已实测）**：RED 276 MB → A-only 94 MB（over-retain 消除）→ A+B **396 KB**（chain-temp 消除,GREEN）。IR 核验：A 后 caller `ss_retain` over-retain 消失;B 后链式 receiver temp 有 `ss_release`。

**但候选 A 实现机制不安全 —— 触编译器 segfault 回归**：

- A-only 全量测试 vs baseline（此 WIP 分支 baseline = 45 fail）→ 净增回归 **1 个**:`tests/phase5/d095_setter_mixed.ss`（`@Getter`+`@Setter` 双 comptime 注解同类）→ **编译器 `bin/ss build` segfault**;baseline 通过。（`generic_constraint_basic.ss` 经 4× 单跑全过,系 `bin/ss test` 并发 flaky,非 A,排除。）
- **机制缺陷**：候选 A 写 `isOwnedExpr` METHOD_CALL 分支调 `inferType(nodeId)` 查返回类型 —— 但 `inferType` **非纯函数**:对 `COMPTIME_EXPR` 子节点会跑 `runComptimeBlockBody` + `flushComptimeIR/SS`（`gen_types.ss:279-330`)。`isOwnedExpr` 原是纯查询,A 让它获得 comptime 执行副作用 —— `options.md §候选对比` 与本 issue §候选修法 **均未预见的「假设破裂入口」**(`inferType` 隐式 codegen/comptime 副作用)。
- **诚实声明 — 未精确定位**：本轮最小化用例 `t1` 不忠实(把操作移出 `test()` arrow 入 `main`,自身在 baseline 即崩于 main 路径既有 bug),污染了 core-dump bisect;`d095_setter_mixed` segfault 与上述机制缺陷的因果链 **尚未坐实**,留下轮精确诊断(`bin/ss` 无 `gdb`,可用 `addr2line` + core NT_PRSTATUS 解析 RIP/栈)。

**下轮 A 重设计方向（属候选 A 实现机制重设计,非重选 A/B/C/D/E）**：`isOwnedExpr` 不得调 side-effectful `inferType`。候选:(a) `isOwnedExpr` 增类型形参,8 个调用点传入各自 `genExpr` 之后(`COMPTIME_EXPR` 已 cache、安全)的 `inferType` 结果;(b) 提供 side-effect-free 的返回类型查询入口。

**B 状态**：B（`evalMethodCall` 链式 receiver owned temp 在 method call 发射后 `emitReleaseForType` 释放,`method_call.ss:254` 后）对泄漏有效;但其 `isChainOwnedTemp` 同样调 `isOwnedExpr`+`inferType` → 同源不安全,须与 A 一并重设计。**B 实际修复点是 `evalMethodCall` 而非 `gen_methods.ss:422 genMethodCall`** —— 正常 method call 的 receiver 由 `method_call.ss:29 genVal(mcObjNode)` 求值后作 `preObj` 传入 genMethodCall,§候选修法 §B 的「`gen_methods.ss:453 objVal=genExpr(objId)`」定位有误,下轮按 `evalMethodCall` 修。

**本轮交付**:leak-观测 RED 测试 + 本节findings。A+B 代码已回退至 baseline(`git diff bootstrap/` 空、bootstrap 固定点 Stage2=Stage3 已 `cmp` 自验)。I023 维持 **Planned**。

---

## 备注

- **SS-LIM-6 corruption 本体已闭合**：由 §E（`gen_builtins.ss:140-143` `emitRetainForType` 替换 `ss_rc_retain`，`f21271d` 落地）消除；`options.md §跨修法联动` 原写「三层缺一环 corruption 仍存在」经 RED 实测（10/10 GREEN）证伪 —— 见 `ss_lim6_jsonnode_chain_corruption.options.md §实测修正`。
- **与 D168 时序**：A/B 是现存 RC 系统内的协议正确性 bug，**不依赖** D168 Phase 2-5 的 RC 合并即可独立修；但 D168 Phase 5「PIR 接入消除 30+ 处手工 retain/release」会重写本 issue 触及的 codegen 路径 —— A/B 应在 D168 Phase 5 之前修，否则 Phase 5 在错协议上铺路、后续返工。
- **scope 边界**：不碰 §C（lib/json wrapper 重设计，`options.md` 远期）、§D（PIR `INDEX_ACCESS` class init 漏 schedule，留 SS-LIM-7 独立 spike）。
