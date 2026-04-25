# I021 codegen const literal comptime ref — 方案对比表(轨 1 自证 demonstration)

> 反写于本轮流程升级 — 用 commit 8844e5f 的 bug 自证 `tools/bug_options_linter.ss` + MNK §M §字段 10 双轨 gate。

## bug 概述

module-level `const X = "<literal>"` 在 comptime block 内引用,emit 出野生 `%N = load ptr, ptr @<global>` 到模块顶层(currentFunc=="" 时 genIdent 无 function 容器,IR 喷顶层导致 llc 解析失败 `expected 'type' after '='`)。

## 假设破裂入口

`bootstrap/eval/ident.ss:52` `evalIdent` 的 fallback `0 - constVal(genIdent(astId)) - 1` 设计意图是 "comptime 求值期间遇到 runtime-only 表达式 → 调 genIdent emit IR + 返 register"。该意图**只在 currentFunc != "" (function 体内) 有效**。在 module 顶层 (currentFunc == ""),**假设破裂** —— genIdent 仍然 emit IR 但无 function 容器,IR 直接喷模块顶层。

## 候选方案对比

| # | 方案 | 层次 | 根因深度论证 | 工程量 |
|---|---|---|---|---|
| A | 数据层 patch:修 1 (gen_decls.ss CONST 入 ctVars) + 修 2 (ident.ss `:${name}` fallback type 白名单从 array/object/map 放宽至任意 isCt) | 数据层 | 让 const literal 走 ct 路径,evalIdent 在 fallback 前命中 ctVars,**不触发**假设破裂入口。但**未消除假设破裂入口本身** — 任何未来 module-level IDENT 漏注册 ctVars 的模式仍会撞同 bug | 标准改 ~31 LOC, 2 文件 |
| B | 接口层 trap:修 3 (evalIdent line 52 fallback 之前加 `currentFunc==""` trap,报 comptime IDENT not resolvable as ct value 编译错误) | 接口层 | **消除假设破裂入口** — evalIdent 在 module 顶层不再调 genIdent,任何"应是 ct value 但漏注册"的模式立即报错而非默默喷野生 IR。**单独不够** — 需配合 A 注册 ctVars(否则合法 const literal 也被报错 break) | 小改 ~5 LOC, 1 文件 |
| C | 架构层 refactor:重构 inferType→runComptimeBlockBody→flushComptimeIR 链,comptime evaluator 解耦 codegen IR emit(comptime = 编译期纯求值,不应有 IR side effect) | 架构层 | **消除 comptime 与 codegen 耦合**(最深根因),但 break 既有 `@comptimeEmit` 合法 metaprogramming 路径(SS 源码片段拼接 → codegen 处理),改动面巨大,需新 D 文档审查 | 大改 ~50-100 LOC + 新 D 文档审查 phase |

## 决策

**本轮 commit 8844e5f 选 A 因 P0 紧急解锁 D123 Phase 4 byte-identical Java parity;但用户打断指出"未达根因",反思后承认正确选应是 A + B 组合**(数据通路补全 + 接口层 trap 消除假设破裂入口),C 留 I023 架构层 D 文档审查后另起。

**为何不选 deeper layer (C)**:C 改动 break 既有 `@comptimeEmit` 路径,审查周期长,会 BLOCK D123 Phase 4 解锁;且 `@comptimeEmit` 是合法 metaprogramming 设计意图,解耦需重新设计 comptime evaluator 与 codegen 的契约,超 bug fix scope。

**修 3 误标"defensive"反思**:本轮把修 3 标为 defensive 留独立 issue 是错误 — 修 3 消除的是"假设破裂入口"(已发生 bug 的设计漏洞),不是"防 hypothetical 未发生 bug",**根因不可降权**,应本轮做。

## 流程改进沉淀

本份 options.md 是 MNK §特定领域 §Bug 修复 Harness §轨 1 + §M §字段 10 的**首次 demonstration**。下次 bug fix 必须在 detected 阶段后、Execute 第一次修改性 tool call 之前产出本表 + 跑 `tools/bug_options_linter.ss` GATE OK,杜绝"方案锁定后用户打断纠偏"的高频信号。
