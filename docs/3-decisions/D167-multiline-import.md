# D167: multi-line import 支持

**Status:** Done
**Depends on:** D166(contextual keywords `from`/`as`)
**Date:** 2026-05-10
**Last Updated:** 2026-05-10

---

## 核心目标 (Goal)

- **为什么**:SS 当前 import 子句必须折单行,长 import 列表(项目内 `bootstrap/main.ss` line 17 `import { initPir, pirAnalyzeFunc, ..., pirActive }` 9 项 ~200 列)不可读,违反"陌生人秒懂"+ "Java/TS 语法优先"(SS-LIM-3 用户报告)。
- **是什么**:`import { Foo, Bar, Baz } from "./mod"` 与 `import {\n    Foo,\n    Bar,\n    Baz\n} from "./mod"` 语法等价,与 TS / ESM 业界一致。
- **单一判据**:`bin/ss check /tmp/multiline.ss` exit 0 + 端到端 `bin/ss run` 输出符合预期 + bootstrap 三阶段固定点 + `bin/ss test tests/` 继承 baseline 不 regression。

---

## 核心原则 (Principles)

1. **业界对标 TS/ESM** — 多行 import 是 ESM spec 标配,TS 1.x+ 一直支持;SS 应对标。
2. **双层根因修复** — 接口层 (resolveImports 字符串扫描) + 数据层 (parser skipNL) 双层不变量同时修复,不留 robustness 缺口。
3. **不切 token-based AST 模块图** — 业界演化 TS 1.x line-scan + 2.0 ModuleResolver AST diff,SS 当前在字符串阶段,跨阶段切换是 N+1 工程,留 §F1 远期(依赖 lexer 重入)。
4. **行号矫正对称** — 多行 import 按"每个 import 占 1 mainCode 行"对齐单行行为,避免行号漂移更严重。
5. **bootstrap 固定点保护** — 改 main.ss / parser.ss 必须 Stage 2 = Stage 3。
6. **基线继承** — 全测 307/17/324 (D165 §Phase 4 baseline 306/17/323 + ss_lim2 spike +1)0 regression。

---

## §A.1 候选方案对比

详见 `ss_lim3_multiline_import.options.md`(repo root)。决策:**选 C**(双层修法 — main.ss resolveImports 多行块累积 + parser.ss parseImport 加 skipNL)。

候选 A(只改 parser)/ B(只改 resolveImports)/ D(切 token-based AST 模块图)否决理由:见 options.md。

---

## §A.2 隐藏假设挑战

| # | 假设 | 状态 | 实证 / 证据 |
|---|---|---|---|
| H1 | parser 是唯一拦点 | 破裂 → 否 A | `bootstrap/main.ss:206 line.startsWith("import ")` 字符串 line-scan 在 parser 之前已吞掉多行块 line 1,后续行错入 mainCode → parser 永远收不到 IMPORT token 开头多行内容 |
| H2 | resolveImports 是唯一入口 | 破裂 → 否 B | parser 应是 robust 下游 invariant,不应假设上游 100% 过滤;parseEnumDecl line 612 / parseSwitch line 144 同模式已 skipNL,parseImport 缺 skipNL 是不一致 |
| H3 | 双修是过度工程 | ✓ 选 C | 双层各自破裂入口客观存在(grep main.ss:206 + parser.ss:622 同时锚到),不可互相吸收 |
| H4 | 现在就需要 token-based AST 模块图 | 破裂 → 否 D | TS 演化 1.x line-scan → 2.0 AST 模块图,SS 当前在字符串阶段;D 依赖 lexer 重入(基础未落地) |
| H5 | bootstrap 三阶段固定点不破 | ✓ | Stage 2 = Stage 3 通过(已实证) |
| H6 | 全测 baseline 继承 | ✓ | 307/17/324 实测继承(D165 §Phase 4 306/17/323 + ss_lim2 spike +1)|
| H7 | 行号矫正不增加偏移 | ✓ | pad 单行→0 / N行→N-1,与单行 import 行号偏移行为对齐 |

---

## §A.3 废案

- **只改 parser**(候选 A):resolveImports 上游字符串扫描已吞掉多行块,parser 永远收不到多行内容,候选 A 单修完全无效。
- **只改 resolveImports**(候选 B):parser 自身 robustness 缺角,违反"上下游各自负责自己 invariant"原则。
- **切 token-based AST 模块图**(候选 D):跨阶段 N+1 工程,依赖 lexer 重入未落地基础;留 §F1 远期。

---

## §Phase 收关锚

| Phase | 内容 | 状态 |
|---|---|---|
| Phase 0 | D 文档 + options.md 起首 + bug.ss detected + 轨 1 GATE OK | [x] 本轮 |
| Phase 1 | resolveImports 多行累积 + parseImport skipNL 双修 + bootstrap 固定点 + spike 5 case GREEN + 全测 307/17/324 + bump F1 baseline | [x] 本轮 |
| Phase 2 | §After Done 三步:simplify + commit + next_prompt | [x] 本轮 |

---

## §扩容申报-Phase-1-multiline-import

| metric | bm_old | bm_new | delta | 业务理由 |
|---|---|---|---|---|
| F1:bootstrap/main.ss | 630 | 645 | +15 | `resolveInner` 把 `for (line in lines)` for-of 循环替换为 `while (li < lines.length())` while-index 循环 + multi-line `from` lookahead accumulator + 行号 pad 逻辑;真实业务 LOC 净增 13(while header / startIdx 跟踪 / inner accumulate while / pad while),可读性优先(必要注释 2 行 + pad 算法不直观需说明)不字符级压缩;§A.1 候选 C 根因解决度评估通过(双层修法消除"字符串 line-scan 假设单行 import" + "parser 不 robust NEWLINE" 双层破裂入口)。已最小化重写(pad 内联 `;` 单行 + 注释 6 行→2 行 + 算法等价精简)。 |

---

## §F1 远期

- **切 token-based AST 模块图**:把 resolveImports 字符串 line-scan 完全替换为 lexer 输出 IMPORT token 节点 list 后的 AST 模块图;消除"字符串扫描 vs token 解析"双轨制。**前置依赖**:lexer 重入(SS 当前 lexer 单全局 `src` / `pos` 状态),需先做 lexer 状态隔离才能多文件 tokenize → 起独立 D 文档。**业界对标**:TS 2.0 ModuleResolver AST diff(2016)。**N 年返工度**:本轮 parser skipNL 修法在 D 落地后**可直接继承零返工**(parser 仍需 robust 多行 IMPORT 解析);resolveImports 多行累积修法被替换,语义可迁移返工幅度小。
