# D166 contextual keywords (`from` / `as`) 修复方案对比

## 问题

SS lexer `bootstrap/lexer/lexer.ss:keywordKind()` 对 `from` / `as` 全局硬保留,导致用户不能用作参数名 / 局部变量 / 类字段 / 函数名。

RED 命令实测:

```bash
# from
echo 'function f(from: int): int { return from + 1 }
function main() { println(f(5)) }' > /tmp/from_repro.ss
bin/ss check /tmp/from_repro.ss 2>&1 | grep "expected identifier, found FROM"
# 输出:parse error at line 1: expected identifier, found FROM(预期:0)

# as
echo 'function main() { let as = 5; println(as) }' > /tmp/as_repro.ss
bin/ss check /tmp/as_repro.ss 2>&1 | grep "expected identifier, found AS"
# 输出:parse error at line 1: expected identifier, found AS(预期:0)
```

业界对标:TypeScript spec 把 `from` / `as` / `of` 列为 **contextual keywords**(只在特定语法位识别),`in` / `instanceof` / `class` 等列为 **reserved words**(全局)。SS 当前把 `from` / `as` 错放进 reserved 类。

## 假设破裂入口(2 项)

1. **假设**「`keywordKind()` 只要识别 SS 内出现的关键字 token 即可」在 contextual 场景下**假设破裂** — `from` / `as` 只在一处当关键字(import 上下文 / type cast 二元运算符),其他位置应为普通 IDENT,但 lexer 设计无 contextual vs reserved 二分,统一 emit token kind → 用户标识符全局被吃掉。

2. **假设**「parser `pExpect("FROM")` 与 `pExpect("AS")` 通用通路是合理表达」在 contextual 化下**假设破裂** — 需要替换为 `curKind()=="IDENT" && curValue()=="X"` 的 contextual 检查;且 `parser.ss:629` 既有 `import { Foo as Bar }` 别名识别用 `curValue()=="as"` 但 `as` 永远 lex 为 `AS` 不是 `IDENT` → 永远 false → **dead code 且 import alias 实际不工作**(本轮顺带修)。

## 候选方案对比

| 候选 | 方案 | 层次 | 优 | 缺 |
|---|---|---|---|---|
| **A** | **lexer `keywordKind()` 删 `from`/`as` 全局保留 + parser 在 `parseImport` / `parseTypeOrCast` / import alias 三处加 contextual `IDENT && curValue()=="X"` 检查;`in` 保留 reserved(对标 TS spec)** | **接口**(parser dispatcher 加 contextual 分支)+ **数据**(lexer keywordKind 表删两行)+ **架构对标**(TS spec contextual vs reserved 二分清晰) | 改动局限两文件(lexer.ss + parser.ss / parse_exprs.ss),对标 TS / JS 业界标准;同时修 parser.ss:629 dead code(`as` import alias 还原工作);`of` 已是 contextual(parse_stmts.ss:333,354),与 `from`/`as` 修法形式一致;`in` 对标 TS reserved 不动,scope 清晰;LOC 约 +15 业务 +10 注释 | 仍是逐词 if-else,未抽象 contextual keyword 机制(下次扩 `set`/`get`/`async` 仍逐词加),留 §F 远期;`as` 中缀运算符位修法比 `from` import 位略复杂(parse_exprs.ss:105 二元运算符表) |
| **B** | **抽象 lexer `contextualKeywords: Map<string, int>` 统一机制,parser 所有 contextual 位查表** | **架构**(lexer 引入 contextual vs reserved 二分抽象)+ **接口**(parser 通用 helper `expectContextual(text)`)+ **数据**(contextualKeywords Map 集中管理) | 一劳永逸 — 未来扩 `set`/`get`/`async` 等 TS contextual 仅加 Map entry;消除 lexer "硬保留每词逐 if" 重复;架构层根治 | scope 大膨胀至 lexer 重构(keywordKind 整体替换 + Map 数据化 + parser helper 函数 + 全 contextual 位重写约 +60 LOC);N 年返工度评估 = 低(SS contextual keywords 总数 ≤5,逐词可承受);**长久演化对标**:TS lexer 实际也是逐 case if-else(`scanner.ts` source 实证),抽象 Map 不是业界标准,过度工程;**否决根因度高:scope 不匹配本轮目标** |
| **C** | **不改 lexer,在 parser 所有 `pExpectIdent()` 调用处加 fallback "AS / FROM token 也接受为 IDENT"** | **接口**(parser `pExpectIdent` 加宽接受 reserved token 的 fallback) | lexer 不动,改动表面看小 | 错误根因方向 — **把 lexer 设计错误下沉到 parser** workaround,违反 §Root Cause "调用方加 workaround" 反模式;`pExpectIdent` 33 处调用,都要 fallback 转换 token kind;新增隐藏假设"哪些 reserved 词可降级 IDENT" — 维护成本高;**否决** |
| **D** | **用户层 workaround:`from` → `start` / `as` → `castAs` 等改名指引** | (none — 不修代码) | 零代码改动 | 违反 CLAUDE.md §Java/TS 语法优先(TS 允许 `from`/`as` 作标识符,SS 不允许 = 偏离);违反 §Root Cause 第一法则(把"编译器限制"留给用户);永久债务 — 用户每次踩雷都要改名;**否决** |

## 决策

**选 A** 因(根因解决度评分):

1. **根因解决度最高**(第一法则):lexer keywordKind 表层根因消除(`from`/`as` 不再硬保留)+ parser contextual 分支落地 + 顺带修 parser.ss:629 dead code,三处缺口同源 — 都是 contextual vs reserved 边界错置。本轮目标 = `from`/`as` 工作即可,A 直接消除根因。

2. **`in` scope 不扩**:对标 TS spec `in` 是 reserved word(`for...in` / `in` 关系运算符),业界统一不允许 `let in = 5`。SS 当前 `in` 行为 = TS,正确,不动。

3. **B 否决**(根因度低、scope 不匹配):抽象 contextual keywords Map 是 lexer 重构,scope 远超本轮 `from`/`as` 修复。N 年返工度评估 = 低(SS contextual keywords 总数 ≤5),业界对标 TS scanner 也是逐词 if-else,抽象 Map 是过度工程。本轮选 A,§F1 远期若 SS 引入 `set`/`get`/`async` 等再考虑 B。

4. **C 否决**(违反 §Root Cause 反模式):不改 lexer 而在 parser 加 fallback = 下沉 workaround,违反"调用方加 workaround"反模式;33 处 `pExpectIdent` 调用要 fallback 转换 token,维护成本高。

5. **D 否决**(违反 §Java/TS 语法优先 + §第一法则):把编译器限制留给用户,永久债务。

## 落地步骤

1. **lexer.ss line 458**:删 `if (text == "from") { return "FROM" }`(已完成 ✓);**line 472**:删 `if (text == "as") { return "AS" }`(待做);加注释指向 parser contextual 处理。
2. **parser.ss `parseImport` line 639**:`pExpect("FROM")` → contextual 检查 `IDENT && curValue()=="from"`(已完成 ✓);**line 629**:`as` import alias 检查已是 contextual `IDENT && curValue()=="as"` 形式正确,本轮 lexer 改后该 dead code 自动还原工作。
3. **parse_exprs.ss line 105**:`while curKind() ∈ {LT, GT, LE, GE, INSTANCEOF, AS}` → 移除 AS,加 `(curKind()=="IDENT" && curValue()=="as")` 分支;line 110 同步分支处理。
4. **bootstrap 三阶段固定点**:`./build.sh bootstrap` Stage 2 = Stage 3。
5. **spike 验证**:`bin/ss run /tmp/from_repro.ss` + `/tmp/from_local.ss` + `/tmp/from_field.ss` + `/tmp/as_repro.ss`(参数/字段/局部/type cast 全 GREEN)。
6. **回归**:`bin/ss test tests/` 继承 baseline 306/17/323;`import { Foo as Bar }` 别名实测 GREEN(line 629 dead code 还原)。
