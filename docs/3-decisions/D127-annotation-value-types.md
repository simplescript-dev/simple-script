# D127: Annotation 参数 — ASSIGN 语法 + 任意表达式值承载

**Status:** firm(三项子决策锁定)
**Depends on:** D123 §C.5(层 A 翻案触发点)、D088(comptime eval 一阶设施)、D120(reflect.classes)
**Date:** 2026-04-22
**Last Updated:** 2026-04-22

---

## 核心目标 (Goal)

- **为什么**:D123 §C.5 层 A 翻案后,annotation 参数从 `@X(k: "v")` COLON 改为 Java 原生 `@X(k = v)` ASSIGN,且 value 不再限 string。原决策(D123 §A.2.5 "COLON 是语法译本")被 user turn 5 推翻。下游 9 个 issue(I001-I009)含三项**子决策**(I002 值类型选型 A/B/C、I006 class ref 语法 A/B、I007 命名参全局一致性 A/B),未锁 D 文档时,下游实现者无 ground truth,必然回来再问用户。
- **是什么**:本 D 文档**一次性锁**三项子决策 + 反向拒绝论证,承接 D123 §C.5 的决策出口,作为 I001/I003-I006 实现阶段的唯一 ground truth。
- **单一判据**:
  1. 本文件存在且三个 "§A" 小节各含"方案 X 锁定 + 反向拒绝 Y/Z 的原理性理由"
  2. I001-I009 每个 issue 能从本文件找到对应锁定锚点
  3. D123 §C.5 line 547/548/551 三个 `[ ]` 待审项在本文档里有对应决策落点

> 口号:turn 5 推翻 COLON,本 D 文档关闭 ASSIGN + 值类型 + class ref + 命名参一致性四个敞口。

---

## 核心原则 (Principles)

1. **子决策单一出口** — 每项 A/B/C 选型只给**一个锁定方向** + 拒绝他项的**原理性**理由(非"成本最小"),不给用户选项菜单
2. **从语言原理推,不从代码现状推** — 拒绝"既有 parser 已支持 X 故选 X"的循环论证(feedback_design_no_code_authority)
3. **SS 无原生 tagged union,不造轮子** — 值承载不走 CtValue 新类型,复用 AST 节点 + nKind 天然 tag
4. **Java/TS 优先,按语义域分侧采纳** — annotation 对齐 Java `k = v`,call named arg 对齐 TS/Dart `k: v`,不是"裂痕"而是"双源语义分采"
5. **class literal 用 TS 侧方案** — SS 裸类名即类引用(`@Import(MyConfig)`),不引入 Java `.class` pattern

---

## 1. Context Management(上下文管理)

### 必读清单(clear 后 Claude 动手前)

1. 本文档
2. `CLAUDE.md` §项目技术规则
3. `docs/3-decisions/D123-spring-boot-replication.md` §C.5 层 A 翻案 / §A.2.5 原 COLON 决策(待 I008 标 SUPERSEDED)
4. `docs/4-issues/I001-I009-*.md`(9 个独立子 issue)
5. 关键代码位置:

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/parse/parse_exprs.ss` | `parseArgs` ~556-587 | COLON 命名参现址,I001 改 ASSIGN |
   | `bootstrap/checker/` | AnnotationMeta 结构体 | I003 扩 args value 类型 |
   | `bootstrap/gen/exprs/exprs_ct_reflect.ss` | D120 reflect 入口 | I004/I006 MEMBER_ACCESS / IDENT 分派点 |

### Stable Facts

| 项 | 值 |
|---|---|
| 决策状态 | 三项子决策 firm(本文档锁定) |
| 实现进度 | I001-I006 未启动,I007/I002/I006 决策已锁 |
| 下轮起点 | I001(parser COLON → ASSIGN,仅 annotation) |

---

# 附录 A: 三项子决策裁决

## A.1 I002 裁决 — Annotation args value 承载机制

### 锁定方向:方案 A `Map<string, AstNodeId>`

- `AnnotationMeta.args` 类型由 `Map<string, string>` 改 `Map<string, int>`(AstNodeId 即节点 ID,SS 中为 int)
- parser 存 AST 节点 ID 而非字符串化
- checker / comptime 阶段调 `evalAnnotationArg(nodeId)` 按 `nKind` 分派 eval:
  - `STRING_LIT` → string
  - `INT_LIT` / `DOUBLE_LIT` → 数值
  - `BOOL_LIT` → bool
  - `MEMBER_ACCESS`(LHS 是 enum 名)→ enum value(I004)
  - `IDENT`(命中类名)→ ClassRef(I006)
  - `ARRAY_LIT` → 元素递归 eval(I005)
- 源位置 `node.line` / `node.col` 完整保留,annotation 错误消息可定位到源码

### 拒绝方案 B `Map<string, CtValue>`(tagged union)

- **原理性拒绝**:SS 无原生 tagged union,CtValue 需用 class 或 Map 模拟 —— class 一半字段永 null(违反 `feedback_human_readable_code`),Map 以 string key 再编码内部数据(违反"禁 string 编码内部结构")
- AST 节点**本身就是 tagged by nKind**,存 AstNodeId 即复用现有 tag 机制;CtValue 是**重复抽象**
- 新增 CtValue 类型 + 所有消费点改 → 反而增加 LOC,未简化消费侧

### 拒绝方案 C `Map<string, string>` + eval-on-read

- 表达式文本序列化/反序列化 ugly,违反 `feedback_no_workaround`(string 编码内部数据)
- 源位置丢失 → annotation 错误消息无行号
- 已在 I002 issue 原文标"直接拒绝"

### 演进路径

A → (未来若 annotation eval 成为 comptime hot path)checker 缓存 eval 结果为 CtValue,反向不通。当下 annotation 是 build-time 一次性展开,性能不敏感。

---

## A.2 I006 裁决 — Class 引用语法

### 锁定方向:方案 A 裸类名 `@Import(MyConfig)`

- IDENT 节点在 annotation value 位置,comptime eval 查表顺序:
  1. enum 名(I004)→ enum value
  2. 类名(本节)→ ClassRef(TypeInfo / class 名引用)
  3. 未定义 → `undefined symbol` 错
- annotation value 语境是 comptime 作用域,**不看** let 绑定的运行时变量 → 无歧义
- 与 I004 `MEMBER_ACCESS` / `IDENT` 路径共享,实现复用

### 拒绝方案 B Java 风格 `@Import(MyConfig.class)`

- **原理性拒绝**:`.class` 是 Java 特有语法 pattern,SS 无此语法,需扩 lexer 或 parser 特例(MEMBER_ACCESS RHS 的 "class" 关键字识别)
- 违反 `feedback_no_new_keywords`(即便 `.class` 在 Java 里是软关键字,SS 引入 `.class` 是新 pattern)
- TS 世界里类就是值(`const X = MyClass`),裸名对齐 TS —— SS 的 Java/TS 优先原则里,对于"类字面量"这一项 TS 侧胜出(TS 简洁、无特例 token)
- 与 SS 内部一致性:函数是值(`onClick = handleClick`)、class 应也是值(`@Import(MyConfig)`),裸名形式统一

### 拒绝方案 C 双支持

- 违反 single-path 原则,D123 §C.5 §1 已禁双形
- 已在 I006 issue 原文拒绝

### Java 迁移成本

`.class` → 裸名是 sed 级改写。Spring Boot 实战中 `.class` 用例集中在 `@Import` / `@ConditionalOnClass` / `@AliasFor` 等配置类 annotation,可控。

---

## A.3 I007 裁决 — SS 全局命名参数语法一致性

### 锁定方向:方案 A 按语义分场景

- **annotation 命名参**:`@Foo(k = v)` — **ASSIGN**,对齐 Java annotation 字段赋值语义
- **function call 命名参 / 构造器**:`foo(k: v)` / `new Foo(k: v)` — **COLON 保留**,对齐 TS/Dart named argument
- I001 只改 annotation 位置的 COLON → ASSIGN,**不动** call / constructor 的 COLON

### 拒绝方案 B 全局 ASSIGN

- **原理性拒绝**:
  - 与 TS `foo({name: "x"})` / Dart 命名参 `foo(name: "x")` 语义习惯冲突,违反"Java/TS 优先"(TS 明确用 COLON)
  - parser 在 call context 需区分 "named arg `k = v`" vs "赋值表达式 `k = v`" → 上下文歧义,增加 parser 复杂度
- function call `foo(k = v)` 与普通表达式 `k = v` 语法形态相同,无法仅凭 token 序列区分,需引入 lookahead 或语义判定

### 拒绝方案 C 全局 COLON

- 已由 user turn 5 直接否定("这个是不对的" 对应 `@RequestMapping(value = "/x", method = RequestMethod.GET)` Java 真实语法)

### 心智模型说明

两种符号对应两种**语义域**,不是"语言裂痕":

- annotation `k = v` → "元数据字段赋值"(annotation 语义上是元数据对象,每个 key 是 field)
- call `k: v` → "形参名标签"(给函数形参贴名字)

同文件出现时有 `@` 前缀的视觉上下文切换,新学者建立心智模型成本低。Java 本身 annotation 用 `=`、method call 参数无命名参(所以无对比);TS/Dart 有 named arg 用 `:`、无 annotation。**SS 同时采两者是"双源语义分采",不是"两个符号语义相同但写法不同"**。

---

# 附录 B: I001-I009 映射

| issue | 本 D127 锁定锚点 | 状态 |
|---|---|---|
| I001 parser ASSIGN | §A.3 锁 "annotation ASSIGN,不动 call COLON" | Ready to implement(下轮起点) |
| I002 值类型选型 | §A.1 锁方案 A | **Done(本 D 文档锁定)** |
| I003 值类型落地 | §A.1 分派表框架(STRING/INT/BOOL/DOUBLE 基础路径) | Ready to implement(依赖 I001) |
| I004 enum 成员访问 | §A.1 `MEMBER_ACCESS` 分支 | Ready to implement(依赖 I003) |
| I005 literal 四种 | §A.1 `ARRAY_LIT` 分支(INT/BOOL/DOUBLE I003 已吸收) | **Done at bootstrap/eval/interp_obj.ss:`evalAnnotationArg` ARRAY_LIT 分支 + bootstrap/gen/exprs/exprs_ct_builtin.ss:`ctMapMethod` getArray(2026-04-24)** |
| I006 class ref | §A.2 锁方案 A(裸类名) | **Done(本 D 文档锁定)** |
| I007 命名参一致性 | §A.3 锁方案 A(按语义分场景) | **Done(本 D 文档锁定)** |
| I008 D123 回写 | §C D121 锚点澄清 + §A.2.5 标 SUPERSEDED | Blocked by I001-I007 全 Done |
| I009 e2e | `tests/phase5/spring_annotation_e2e.ss` | Blocked by I001-I006 全 Done |

---

# 附录 C: D121 锚点澄清

D123 全文多处引用 "D121 R1" / "D121 R2-A" / "D121 R3" 作为决策锚点(line 60 / 62 / 93 / 425 / 489 / 510 等)。**物理事实**:

- `docs/3-decisions/D121*.md` **不存在**(2026-04-22 `ls` 验证)
- `docs/3-decisions/` 真实文件清单:D088-098 + D120 + D123 + `_template.md`(共 12 条)
- "D121 R1 blocker"(`ann.args.get("value")`)、"D121 R2-A COLON 已确认" 等叙述源于更早阶段决策脚本,D 文件未独立落地,内容已被吸收进 D123 §A.2.5(原 COLON 决策)和 D123 §C.1 A1/B 条(已 Done 的基础 annotation 能力)

### 本 D127 的处理

- 不复用 "D121 R2-A" 虚锚
- 直接用 "D123 §A.2.5" 作为被替代的原决策锚点
- §A.3 拒绝方案 C 时引用 "user turn 5 推翻"(D123 §C.5 触发事件)而非 "D121 R2-A 反转"

### I008 承接对齐(后续工作)

I008 回写 D123 时的具体操作清单:

1. D123 §A.2.5 标 `[SUPERSEDED 2026-04-22 by D127 §A.3]`,保留原文(历史审计价值)
2. D123 §6 核心原则第 6 条("annotation 语法就是 `@Ann(key: "val")` COLON")改写或补 `[SUPERSEDED]` 链接 D127 §A.3
3. D123 §C.1 A2 层的"当前 `Map<string,string>` 不够,D121 R2-A COLON 被推翻" 语句:"D121 R2-A" 改为"D123 §A.2.5"
4. D123 §C.3 "Phase 1 blocker D121 R1 已清零":保留(D121 R1 是 D120/D123 §C.1 B 层 "ann.args.get" Done 的虚锚叙述,不影响决策)
5. D123 全文 grep "D121 R" 所有命中:按"虚锚 → 真锚点"对齐(部分 → D123 §A.2.5,部分 → D127,部分标"历史虚锚已消化")

I008 实施时直接读本 §C 作为对齐依据。

---

# 附录 D: 后续工作路径

| 步骤 | issue | 依赖 | 颗粒度 |
|---|---|---|---|
| 1 | I001 parser annotation COLON → ASSIGN | 无(本 D 文档 §A.3 就绪) | 1-2 万 token |
| 2 | I003 值类型落地(基础分派表 + STRING/INT/BOOL/DOUBLE) | I001 | 7-10 万 token(超则拆 I003a/I003b) |
| 3a | I004 enum 成员访问 | I003 | 3-5 万 token |
| 3b | I005 literal 四种 | I003 | 3-5 万 token |
| 3c | I006 class ref | I003 | 3-5 万 token |
| 4 | I009 e2e 验收 | I001-I006 全 Done | 1-2 万 token |
| 5 | I008 D123 回写(§A.2.5 标 SUPERSEDED + §C D121 锚点对齐) | I001-I007 全 Done | 5 千 token |

I004/I005/I006 可并行实现(都往 I003 建立的分派表加分支,互不干扰)。

---

## 参考

- `docs/3-decisions/D123-spring-boot-replication.md` §C.5 — 层 A 翻案触发事件 + 九项待审
- `docs/3-decisions/D088-comptime-zig-route.md` — comptime eval 一阶设施(annotation eval 是其一 use case)
- `docs/3-decisions/D120-reflect-classes-global-enumeration.md` — reflect.classes 是 annotation comptime 展开的枚举入口
- `docs/4-issues/I001-I009-*.md` — 9 个子 issue
- `CLAUDE.md` §项目技术规则 — Java/TS 优先 + no_new_keywords + no_workaround
- MNK §核心原则 5 — 结论立即落 D 文档或本文档锚
