# SS-LIM-6 JsonNode chain + class-allocation corruption — 修法方案对比

## 实测修正（2026-05-16 — SS-LIM-6 Execute 轮 RED 核验）

本表原 §决策行「A + B + E 三层联修」结论经 Execute 轮 RED 核验后**部分订正**，以实测为准：

- **构建**：tip `f21271d` 三阶段固定点 PASS（`Stage 2 = Stage 3`），无断裂树；D168 §C.9 的 `gen_rc.ss` WIP 处于可 build 状态。
- **§E 已独立落地**：`bootstrap/gen/gen_builtins.ss:140-143` 当前已是 `emitRetainForType(val, pushType)`（替换旧 `ss_rc_retain` 硬编码），`f21271d` 顺带落地 —— 即本表候选 §E。**§E 决策列标 `Done-via-D168§C.9`**。
- **RED 实测 GREEN**：`bin/ss run tests/ss_lim6_jsonnode_chain_corruption_test.ss` 连续 10/10 稳定输出 `k=0..3 = a/b/c/d`、exit 0。**corruption 不复现 —— §E 单独已消除 corruption。**
- **§决策行 / §跨修法联动 的「三层缺一环 corruption 仍存在」论断经实测证伪**：§E 单独足以消除 corruption；§A（over-retain）、§B（chain-temp）修的是**内存泄漏**（不产生错值），SS-LIM-6 功能测试只断言 `v == ""` 故观测不到。
- **§A + §B 改判**：不是 corruption 修复，是 RC 泄漏修复 —— 按 MNK §衍生 issue 归档「非阻挡 → 独立立项」拆出 **`docs/4-issues/I023-methodcall-class-rc-leak.md`**，需独立的 leak-观测 RED，留后续轮 Execute。
- **§C / §D 维持原判**：C（lib/json 重设计）远期；D（PIR INDEX_ACCESS class schedule）留 SS-LIM-7 独立 spike。

下方 §决策行 与 §跨修法联动 的原始 Plan 推演**保留作历史**；§候选对比表 §决策列已就地订正。

## 现象

repro：

```ss
function expand(elem: E, data: JsonNode, out: Array<N>) {
    const arr = data.get("items")          // METHOD_CALL → class JsonNode
    const sz = arr.size()
    let k = 0
    while (k < sz) {
        out.push(cloneE(elem))             // EXPR_STMT 内夹带 user class allocation (new T / new E)
        const v = arr.get(k).asString()    // chained METHOD_CALL: inner 返 class temp 给 outer 用
        println("k=" + `${k}` + " v='" + v + "'")
        k = k + 1
    }
}
```

观测：`k=0 v='a'`，`k=1 v='b'`，`k=2 v=''`，`k=3 v=''`（应为 c / d）；用户报告甚至有 mimalloc free list corruption 证据。

去掉 `out.push(cloneE(elem))` 一行 → 全部 GREEN，故触发因子是 **class allocation 与 chained method-call 同函数交错**。

## 假设破裂入口

| 假设 | 状态 | 论证 |
|---|---|---|
| H1: METHOD_CALL 返类实例时 codegen 把 callee 已 `new X()` rc=1 owned 误判为 borrowed → caller 又 `emitRetainForType` 多 +1 | 待破/已破 | `gen_decls.ss:60-75 isOwnedExpr` METHOD_CALL 直接 `return 0`，不区分返类型；`gen_decls.ss:644-647` PIR 路径 + `isOwnedExpr==0` → 强制 `emitRetainForType(val, "JsonNode")` → arr rc=2，PIR liveness drop 1 后 rc=1 永不 free → leak（不直接 corrupt 但污染 RC）|
| H2: chained `arr.get(k).asString()` 内 inner METHOD_CALL 返 owned class temp 给 outer 用作 receiver,outer 完成后 inner temp 在寄存器无 release | 待破/已破 | `gen_methods.ss:421-565 genMethodCall` line 452 `objVal = genExpr(objId)` 直接拿 ptr 用,无 chainTemps 跟踪;`new JsonNode(...)` 每 iter 一个 mimalloc block leak |
| H3: lib/json `JsonNode` wrapper 设计本身把 RC 拽进每次 `.get()` | 不破（设计选择） | 改 lib/json 改 raw int 是 N+1 工程,本轮 scope 远超 |
| H4: PIR `pirLowerVarDecl` 对 INDEX_ACCESS class init 无 RC_INC schedule（cloneE 内 `const c = e.children[i]` leak 路径） | 待破 | `pir_lower.ss:108-138` 仅 NEW_EXPR/IDENT/CALL/METHOD_CALL 四 case,INDEX_ACCESS class 落到 line 137 `return buf` 不进 classVars;但与本 bug **直接因果链待实测验证**(cloneE 的 leak 是否是 corruption 触发因) |
| H5: `genArrayMethod("push")` 对 ptr 元素强制 `ss_rc_retain` 而非 `emitRetainForType` 双 RC 分派,class instance 走旧 RC 系统 magic 比对 | 待破 | `gen_builtins.ss:140-142` `if (pushNonOwning == 0) emitIR(call ss_rc_retain ptr val)`,class instance 在 mimalloc 分配 magic at -4 偏移读到的是 mimalloc 元数据,概率命中 1397969747 → ss_rc_release destroy 路径 → mimalloc 状态污染。SS-LIM-2 §A 已对 array indexed write 走 emitRetainForType,本处 push 漏修同模式 |

## 候选对比

| 候选 | 层次 | 描述 | 优 | 劣 | 假设 | 根因解决度 / 长久维度 | 决策 |
|---|---|---|---|---|---|---|---|
| **A** | 数据/codegen 分发器 | `isOwnedExpr` METHOD_CALL 改为按返类型分派：返 user class → return 1（owned，callee 都 `return new X(...)`）；返 string / 容器 → 仍 0（borrowed） | 真根因（caller-borrow vs callee-owned 总入口分发统一）；与 SS-LIM-2 §A 「`ssTypeToLLVM(vt)=='ptr'` 取代字符串名」按返类型分派同范式；6 调用点（assigns × 3 / decls × 3 / stmts_simple × 2）一次扫齐 | 6 处调用点对称性巡检；可能 break 其他依赖「METHOD_CALL 一律 borrow」假设的测试 | H1 破裂证据 | 高根因解决度（消除分发抽象层 caller-callee RC 协议错配）；底层依赖：emitRetainForType 已落地无前置；业界对标：Perceus / Koka 都按返类型决定 caller 是否 retain；N 年返工度低（这是 RC 协议的根） | ✓→I023（实测改判：leak 修复，见文首 §实测修正） |
| **B** | 接口/codegen chain 临时管理 | `genMethodCall` line 452 `objVal = genExpr(objId)` 后,若 objId 是 METHOD_CALL/CALL 返 user class → 入 `chainTempReleases` stack；外层 method 完成后 `emitReleaseForType(temp, type)` 释放 | 真根因（chain temp 漏管的接口层补全）；与 SS-LIM-4 alloca hoist 同模式（codegen window 内 sub-expression resource 跟踪） | 跨递归状态管理（嵌套 chain a.b().c().d() 要正确 push/pop）；增加复杂度 | H2 破裂证据 | 中-高根因解决度（chain temp 是接口层缺口，A 修后 inner METHOD_CALL 仍返 owned 但 outer 不 release → leak 持续）；底层依赖：A 修法先（A 让 METHOD_CALL 返 owned 才有 release 必要）；业界对标：Rust borrow checker / Swift ARC 都对 chain temp 自动 release | ✓→I023（实测改判：leak 修复，依赖 A） |
| C | 架构/lib/json 重设计 | `JsonNode` wrapper class 全删,jnGet 等返 raw int(类似 jnGetField 内部 helper);public API 改 raw int + `JSON.getString(json, key)` 自由函数 | 长期最干净（消除每次 `.get()` 的 heap allocation + 双 RC 跨）| lib/json 全面 refactor + 所有 caller adaptation；本轮 scope 爆炸（≥10 文件）；当前 SS 用 lib/json 处不算多但每处都要改 | H3 不破（设计选择，非 bug） | 高根因解决度但远期工程；底层依赖：A+B 已修后此路价值减弱；业界对标：JSON 库多用值类型 wrapper（serde Value）也 OK，wrapper 不是错；N 年返工度低 | ✗（远期 §F，A+B 修后再评估） |
| D | 数据/PIR liveness 补全 | `pirLowerVarDecl` INDEX_ACCESS class init 加 case → 发 RC_INC PIR(S1=name S2=name 自借),纳入 classVars + lastUseStmt schedule | 闭合 PIR cloneE 的 c leak;对称 NEW_EXPR/CALL 等已有处理 | 与本 bug 因果链未实测验证(cloneE 的 c leak 不直接 corrupt arr);PIR 改有 bootstrap 固定点风险 | H4 待实测 | 中根因解决度(补全 PIR coverage,但非本 bug 直接根);底层依赖:无;业界对标:Perceus 完备 liveness 必须覆盖所有 class-typed init kind;N 年返工度低 | △(留 SS-LIM-7 单独 spike,不本轮捆绑) |
| E | 数据/codegen runtime contract | `genArrayMethod("push")` 用 `emitRetainForType(val, pushType)` 替换 `ss_rc_retain` 硬编码 | 与 SS-LIM-2 §A 同模式根因消除（按 ssType 分派 RC 系统）；改一处即覆盖所有 push class instance 路径 | 与 H1 + H2 因果链是「同伴根因」非「替代根因」 — A+B 修后 push 仍要修，否则 E ptr 入 array 后 RC 系统不一致 | H5 破裂证据 | 高根因解决度（但单独修不够，A+B 是更上游）；底层依赖：emitRetainForType 已落地；业界对标：双 RC 系统必须 caller 按值类型分派；N 年返工度低 | ✅ Done-via-D168§C.9（f21271d gen_builtins.ss:140-143） |

## 决策行

> ⚠ **见文首 §实测修正（2026-05-16）** —— §E 已由 `f21271d` 独立落地、单独消除 corruption（RED 测试 10/10 GREEN）；§A/§B 经实测改判为内存泄漏修复，移交 `docs/4-issues/I023-methodcall-class-rc-leak.md`。下方原始 Plan 论断（含「三层缺一环」）保留作历史推演。

**选 A + B + E 三层联动根因修法 因 RC 协议错配的根因横跨三层：A 修分发器（caller-callee owned/borrowed 协议），B 修接口层（chain intermediate temp 释放），E 修 runtime contract（push 双 RC 分派统一）；三层缺一环 leak/corruption 都仍存在。** D 留 SS-LIM-7 独立 spike，C 留远期 §F lib/json 重设计评估。

## 跨修法联动

A 让 METHOD_CALL 返 owned class 不再 over-retain → arr rc 不再 stuck 1。
B 让 chain temp 释放 → 每 iter inner JsonNode 不再 leak。
E 让 push class 实例走 ss_retain → 旧 RC 系统 magic 偶发命中 ss_rc_release destroy 路径的 corruption 入口消除。

三者协同后:`arr` rc 正确 + chain temp 正确 + push 不污染 mimalloc → free list 干净 + arr.nodeId 不会被 reused-block 覆盖 → `arr.get(k).asString()` 跨 iter 全 GREEN。

## 假设破裂总览

- H1（METHOD_CALL→class isOwnedExpr 漏判）破裂 → 选 A
- H2（chain intermediate class temp 无 release）破裂 → 选 B（依赖 A）
- H3（lib/json 设计是根）不破 → 否 C（远期）
- H4（PIR INDEX_ACCESS class 漏 schedule）待实测 → △ D（独立 spike）
- H5（push class 走 ss_rc_retain 双 RC 错配）破裂 → 选 E
