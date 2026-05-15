# D166: contextual keywords (`from` / `as`) 修法

**Status:** Done
**Depends on:** None
**Date:** 2026-05-09
**Last Updated:** 2026-05-09

---

## 核心目标 (Goal)

- **为什么**:SS lexer `keywordKind()` 把 `from` / `as` 全局硬保留,导致用户不能用作参数 / 局部变量 / 类字段名,违反 TS/JS 语义(SS-LIM-1 用户报告)。
- **是什么**:lexer 删 `from`/`as` 全局保留,parser 在 import / type-cast 上下文用 contextual `IDENT && curValue()=="X"` 检查;`in` 保留 reserved 对标 TS spec。
- **单一判据**:`bin/ss check /tmp/from_repro.ss` + `/tmp/as_repro.ss` (参数 / 局部 / 字段 / type cast 等场景) exit 0,且 `bin/ss test tests/` 继承 baseline 306/17/323 不 regression。

> contextual vs reserved:lexer 边界二分,只有"任何位置都当关键字"的词才 reserved;"只在某语法位当关键字"的词应 contextual。

---

## 核心原则 (Principles)

1. **业界对标优先** — TS spec 把 `from`/`as`/`of` 列为 contextual,`in`/`instanceof` 列为 reserved。SS 应对标 TS,不自创第三种分类。
2. **调用方零 workaround** — 修在 lexer + parser 两端,不在用户代码 / parser fallback / pExpectIdent 加宽容机制(违反 §Root Cause 反模式)。
3. **scope 严格控制** — 本 D 仅修 `from` + `as`(用户字面 SS-LIM-1 + 同形 bug 顺带);`in` 不扩(对标 TS reserved 是正解);抽象 contextual keywords Map 留 §F1 远期(N 年返工度低)。
4. **dead code 顺带修** — `parser.ss:629` `import { Foo as Bar }` 别名识别已是 contextual `IDENT && curValue()=="as"` 形式,但 lexer 永远 emit `AS` 导致永远 false → 本轮 lexer 改后自动还原工作。
5. **bootstrap 固定点保护** — 改 lexer / parser 必须 `./build.sh bootstrap` 三阶段 Stage 2 = Stage 3。
6. **基线继承** — 全测 306/17/323(对照 4c38d01 D165 §Phase 4 baseline)0 regression。

---

## §A.1 候选方案对比

详见 `d166-contextual-keywords.options.md`(repo root)。决策:**选 A**(lexer 删 from/as 全局保留 + parser contextual 分支)。

候选 B(lexer Map 抽象)/ C(parser fallback)/ D(用户改名)否决理由:见 options.md。

---

## §A.2 隐藏假设挑战

| # | 假设 | 状态 | 实证 / 证据 |
|---|---|---|---|
| H1 | `from` 全局移除 keywordKind 不破坏 import 语法 | ✓ | `main.ss:resolveImports` 是 line-based 文本扫描,在 lexer/parser 之前已处理合法 import 行;parser `parseImport` 兜底 contextual 检查覆盖直接进 parser 边界情况;spike `import_ok.ss` 编译通过 |
| H2 | `as` 同样 contextual 化无破坏 type cast 主路径 | 待验 | `parse_exprs.ss:105` 中缀运算符表移除 AS,加 `IDENT && value=="as"` 分支 + line 110 分支处理;tests/ 内既有 type cast 测试继承 baseline |
| H3 | `parser.ss:629` import alias dead code 修复后 `import { Foo as Bar }` 工作 | 待验 | 本轮 lexer 删 `as` keyword 后,line 629 contextual 检查自动还原工作;补 spike `import_alias.ss` 验证 |
| H4 | `in` 不动是正解(对标 TS reserved) | ✓ | TS spec / JS spec `in` 是 reserved word(`for...in` 和关系运算符 `x in obj`);SS 当前行为对齐 TS;不扩 scope |
| H5 | `of` 已 contextual 无需动 | ✓ | `parse_stmts.ss:333,354` 已用 `curKind()=="IDENT" && curValue()=="of"`,lexer `keywordKind` 中 `of` 没有 if 分支(默认走 IDENT)— 现有实现已正确 |
| H6 | bootstrap 三阶段固定点不破 | ✓ Phase 1 from 修法 | Stage 2 = Stage 3 通过(已实证) |
| H7 | 全测 baseline 继承 | ✓ Phase 1 from 修法 | 306/17/323 实测继承 4c38d01 D165 §Phase 4 baseline |

---

## §A.3 废案

- **抽象 contextual keywords Map**(候选 B):scope 远超本轮目标,业界 TS scanner 实证也是逐 case if-else,抽象 Map 是过度工程。N 年返工度评估 = 低(SS contextual keywords 总数 ≤5)。留 §F1 远期若引入 `set`/`get`/`async` 等再起独立 D 文档。
- **parser pExpectIdent fallback 接受 reserved token**(候选 C):违反 §Root Cause "调用方加 workaround" 反模式,33 处 `pExpectIdent` 调用都要 fallback 转换 token,维护成本高。
- **用户层改名指引**(候选 D):违反 §Java/TS 语法优先 + §第一法则,把编译器限制留给用户。
- **本 D 内修 contextual keyword 抽象机制**(scope 膨胀考虑):本轮按 §scope 严格控制原则只修 `from` + `as`;抽象机制留 §F1。

---

## §Phase 收关锚

| Phase | 内容 | 状态 |
|---|---|---|
| Phase 0 | D 文档 + options.md 起首 | [x] commit `2bb204d` |
| Phase 1 | `from` 修法(lexer 删 + parser contextual) + bootstrap 固定点 + spike 三 case GREEN + 全测 306/17/323 | [x] DONE commit `2bb204d` |
| Phase 2 | `as` 修法(lexer 删 + parse_exprs 中缀分支 + parser:629 dead code 还原) + spike type cast + import alias GREEN + bootstrap 固定点 + 全测继承 | [x] DONE commit `2bb204d` |
| Phase 3 | §After Done 三步:simplify + commit + next_prompt;跨 D 起首回填 D166 §Phase 0/1/2 hash | [x] DONE commit `2bb204d` |

---

## §扩容申报-Phase-1-from-as-contextual

| metric | bm_old | bm_new | delta | 业务理由 |
|---|---|---|---|---|
| F1:bootstrap/parse/parser.ss | 877 | 885 | +8 | `parseImport` 把 `pExpect("FROM")` 1 行替换为 contextual 检查 5 行(if header + println + exit + closing brace + pAdvance)+ 1 行注释 = 净 +5 业务 LOC;`parse_exprs.ss` 的 `as` contextual 修法不影响 parser.ss。已最小化(可读性优先,不字符级压缩 `;` 内联);D166 §核心目标根因解决度评估通过。 |

## §Followup

| # | 项 | 触发 | 状态 |
|---|---|---|---|
| F1 | lexer 抽象 contextual keywords Map(候选 B 远期) | 若 SS 引入 `set`/`get`/`async`/`yield` 等 ≥3 个新 contextual,起独立 D 文档评估 | 待触发 |
| F2 | `pExpectIdent()` 33 处调用统一 helper(reserved keyword 误用错误信息改进)| 用户多次踩雷 reserved word 误用时 | 待触发 |

---

## Status 时间线

- 2026-05-09 D166 起首,Phase 0 D 文档 + options.md 落地;Phase 1 `from` 修法 GREEN;Phase 2 `as` 修法 GREEN(lexer 删 + parse_exprs 中缀分支 + parser:629 dead code 还原);Phase 3 §After Done simplify + commit + next_prompt + 跨 D 起首回填一并落地;commit `2bb204d` 一次性涵盖 Phase 0-3,主线 close。
