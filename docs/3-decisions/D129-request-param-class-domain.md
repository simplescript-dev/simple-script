# D129: @RequestParam V=class 域归属辨析(I021d 跨域 — @RequestParam vs @RequestBody / @ModelAttribute)

**Status:** Decided(2026-04-25 起草 → 同日 next_prompt option a 用户审议接受锁定 + I021-requestbody 起子档落地 §5 line 130)
**Depends on:** I021(Done at `lib/spring/boot/application.ss:37-79` + `bootstrap/eval/interp_obj.ss MethodMeta.params` + `bootstrap/parse/prelude.ss ParamMeta.annotations` + commit 75f0516 + 8844e5f) / I021bc(Planned, V=int + V=double 同根因合并子档,不在本 D 文档 scope)/ D123 §247-259 §Phase 4 §第一性需求
**Triggered by:** I021 §v0 scope §留下轮 §"I021d — @RequestParam V=class(I020c mirror,需 D067 T? narrow 配合可空形参)" 描述与 @RequestParam 域契约破裂(2026-04-25 用户分流推荐时识别)
**Date:** 2026-04-25
**Last Updated:** 2026-04-25

---

## 核心目标 (Goal)

- **为什么**:I021 §v0 scope §留下轮 line 68 原列 "I021d — `@RequestParam` V=class(I020c mirror,需 D067 T? narrow 配合可空形参)";按 CLAUDE.md §Root Cause 第一法则(commit 3744f4a + d0a109f)按根因解决度分流推荐时识别 — **"I020c mirror" 描述与 @RequestParam 域语义边界破裂**:I020c 是 typed Map<K,ClassName>.get **cast lowering**(map.set 时存的 class 实例,map.get 时反向 inttoptr cast,**class 实例先于 get 已存在**);@RequestParam V=class 是从 query string `?user=...` **反序列化创建** class 实例(query string 是 url-encoded 字符串,无 deserializer 路径,**class 实例不存在**)— 两者性质完全不同,前者是 cast,后者是 deserialization
- **是什么**:辨析 @RequestParam V=class 域归属:**应在 @RequestBody / @ModelAttribute 域,不在 @RequestParam 域**。Spring 框架自身契约即如此 — @RequestParam 域 = url-encoded primitive/string from query string;@RequestBody 域 = JSON/form body deserialization;@ModelAttribute 域 = query string 多 key → class 多字段 binding(数据源 query string,本质也是 deserialization)
- **单一判据**(辨析结论 → I021 §下轮 list 改写):
  1. I021 §下轮 list line 68 "I021d — @RequestParam V=class(I020c mirror,需 D067 T? narrow)" 改写为 "I021d 域归属辨析 — @RequestParam V=class **不在 @RequestParam 域**,跨域问题独立 D129 讨论 → docs/3-decisions/D129-request-param-class-domain.md"
  2. 后续 V=class 反序列化能力起独立 I021-requestbody / I021-modelattribute issue,**不**作为 I021 子 issue
  3. 本 D 文档不动代码,纯辨析 + I021 §下轮 list 描述修正

> 口号:I020c 是 cast,@RequestParam V=class 是 deserialization,**两个域**。

---

## 核心原则 (Principles)

1. **域语义优先于 V 类型机械对称** — I021 §下轮 list 按 V 类型机械分 I021b/I021c/I021d 是表面分类(按 V 表面分),实质 V=int + V=double 与 V=class 跨域(cast 域 vs deserialization 域)。CLAUDE.md §Root Cause 第一法则按根因解决度分流要求拒绝表面分类
2. **Spring 框架契约 alignment** — Java Spring 自身 @RequestParam 不支持 V=class(需 @ModelAttribute / @RequestBody 等其他 annotation),SS 作为 Java parity 实现不应越过此契约。SS 用 SS 写但语义对齐 Java,不发明 SS 私有 @RequestParam(complex=true) 跨域形态
3. **deserializer 路径独立** — query string → class 实例 反序列化能力是独立 lib 层基础能力(类比 lib/json.ss 反序列化),不应在 @RequestParam invoke sentinel cast 路径堆 deserializer。独立 issue 落地 lib/spring/boot/deserializer.ss(或类似)+ 在 @ModelAttribute / @RequestBody 域消费
4. **本 D 文档不触代码** — 纯辨析 + 描述修正(I021 §下轮 list 改写),不动 bootstrap / lib / runtime 代码,无 reflection_linter 影响

---

## 1. Context Management(上下文管理)

### 必读清单(clear 后 Claude 动手前)

1. 本文档(D129)
2. `docs/4-issues/I021-request-param-string-binding.md` §v0 scope 切分说明 §留下轮(原 line 68 "I021d — @RequestParam V=class(I020c mirror)" 描述破裂源)
3. `docs/4-issues/I020c-typed-map-get-class.md` §I020c 子决策 段(cast lowering 域,作为对比锚 — 不是 mirror)
4. `docs/4-issues/I021bc-typed-request-param-cast.md`(同父 I021 子档,V=int + V=double 同根因合并 — 不含 V=class)
5. CLAUDE.md §Root Cause 优先 (commit 3744f4a + d0a109f) 第一法则
6. Spring 框架 @RequestParam / @RequestBody / @ModelAttribute 三 annotation 域契约文档(Spring Boot 3.x Reference Guide)

### 关键代码位置(本 D 文档无代码改动 — 纯辨析)

- `lib/spring/boot/application.ss:37-79` 已落地 @RequestParam V=string comptime block(I021 v0 收关产物,本 D 文档不改)
- `bootstrap/parse/prelude.ss` ParamMeta.annotations 字段(I021 v0 加入,本 D 文档不改)
- `bootstrap/eval/interp_obj.ss` MethodMeta.params 填充(I021 v0 加入,本 D 文档不改)

---

## 2. 问题陈述

I021 §v0 scope §留下轮 line 68 原列:

> **I021d** — `@RequestParam` V=class(I020c mirror,需 D067 T? narrow 配合可空形参)

**两层描述破裂**:

### 破裂层 1 — "I020c mirror" 表面对称错误归类

I020c(`docs/4-issues/I020c-typed-map-get-class.md`)的核心问题是 **typed Map<K,ClassName>.get cast lowering**:
- map.set("k", alice) 时,alice 是已构造的 User class 实例,经 `bitcast ptr→i64` 存入 map i64 值槽
- map.get("k") 时,反向 `inttoptr i64→ptr` cast + ss_retain 取出 class 实例 ptr
- **class 实例先于 get 已存在**,问题是反向 cast + RC 契约

@RequestParam V=class 设想的 `function hello(@RequestParam(name="user") user: User)` 场景:
- HTTP `curl :8080/hello?user=alice` 携带 query string `?user=alice`
- query string `"alice"` 是 url-encoded 字符串(I018 已 split 入 req map: `req.get("user") == "alice"`)
- @RequestParam 域期望从 string → User class 实例:**class 实例不存在,需创建**
- 创建路径无定义:`"alice"` → User { name: "alice", age: ?, email: ? } 字段缺失,无 deserializer

**两者性质完全不同**:
- I020c = **cast**(typed inttoptr,RC 契约)
- I021d 设想 = **deserialization**(string → class 实例,需 deserializer 路径)

按 "I020c mirror" 路径实施 I021d 等于 I020c 的 cast 模式机械套用到反序列化场景 → 物理不可行(query string 单 string 值无字段映射信息)

### 破裂层 2 — "需 D067 T? narrow 配合可空形参" 域错位

D067 T? narrow 是 SS 全局 null safety 主策略,Kotlin/Dart 风格(memory `project_null_safety_design.md`),适用于 nullable 引用类型在编译期强制 narrow check(`if (u != null) { u.name }`)。

@RequestParam V=class 设想"miss → null"对接 D067 narrow,但**前提是 class 实例存在或不存在**;实际 query string `?user=alice` 是 string `"alice"`,不是 User 实例 ptr 也不是 null —— 是**第三态**:**有 string 但无 deserializer**。D067 narrow 解决不了这个问题(narrow 只处理 ptr null vs ptr 非 null,处理不了 string 待反序列化)。

---

## 3. 域归属辨析

### Spring 框架契约(Java Spring 3.x Reference)

| Annotation | 域语义 | V 类型支持 | 数据源 |
|---|---|---|---|
| `@RequestParam` | url-encoded primitive/string from query string | string / int / long / double / boolean / Date(parseable types)/ List<String>(repeated key) | query string `?key=value` |
| `@RequestBody` | HTTP body JSON / XML / form → class 反序列化 | 任意 class(含嵌套)+ Jackson/Gson 反序列化器 | HTTP body |
| `@ModelAttribute` | query string + form body 多 key 自动映射到 class 字段 | class(字段级 binding,字段名匹配 query key)| query string + form body |
| `@PathVariable` | URL 路径占位符 | string / int / long / double(parseable types) | URL `/users/{id}` |

**Spring 自身 @RequestParam 不支持 V=class**(参考 Spring Boot 3.x 官方文档 §Web § Request Mapping § @RequestParam):"@RequestParam supports primitive types and their wrappers, plus String, with type conversion via ConversionService". V=class 走 @ModelAttribute(field-level binding from query/form)或 @RequestBody(body 反序列化)。

### SS 域归属决策

按 Java Spring parity 契约 + CLAUDE.md §Root Cause 优先 §按根因解决度分流:

- **I021 / I021bc 域** = @RequestParam 域,V 限定 string + int + double + boolean + parseable primitive(本 D 文档外,I021bc 修 V=int/double,V=boolean 留 I021-bool)
- **V=class 跨域**:
  - 子域 1(@ModelAttribute 域)= query string 多 key → class 多字段 binding(`?user.name=alice&user.age=30` → User { name: "alice", age: 30 }),起独立 **I021-modelattribute** issue
  - 子域 2(@RequestBody 域)= HTTP body JSON 反序列化 → class 实例(`POST :8080/users` body = `{"name":"alice","age":30}` → User),起独立 **I021-requestbody** issue
  - 两子域共享 lib 层 deserializer 基础能力(query → class field map / JSON → class field map),未来可能起独立 lib/spring/boot/binding.ss 或 lib/json.ss 扩展

---

## 4. 候选路径(选 A)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | V=class **不在 @RequestParam 域**,改写 I021 §下轮 list line 68 描述,V=class 反序列化能力起独立 I021-modelattribute(query → class field binding)+ I021-requestbody(JSON body → class)issue。**本 D 文档不动代码**,纯辨析 + 描述修正 | 严格 alignment Java Spring 框架契约;按域语义优先 V 类型机械对称(根因解决度分流);未来 lib 层 deserializer 基础能力独立落地不污染 @RequestParam 域 ✅ |
| **B** | 扩 @RequestParam 域支持 V=class(`?user=alice` 自动构建 User { name: "alice", 其他字段缺失或默认值 }) | 违反 Spring 框架契约;query string 单值 → class 多字段 物理不可行(字段缺失);需发明 SS 私有"单值映射首字段"语义,Java parity 永久断裂 ✗ |
| **C** | 为 V=class 起独立 @RequestParam(complex=true) 形态(`@RequestParam(name="user", complex=true) user: User`)— SS 私有扩展 | 增添 SS 私有语义,非 Java parity;违反 CLAUDE.md §Java/TS 语法优先 + Spring 框架契约;未来用户混淆 SS @RequestParam 与 Java @RequestParam 行为差异 ✗ |
| **D** | I021d 保留按 "I020c mirror" 走 cast lowering(`?user=ptr_int_value` 用户手动序列化 ptr 整数 → inttoptr cast 取 User 实例) | 物理不可行 — query string `"alice"` parseInt fail / `"123456789"` 即使 parse 成 i64 也是任意整数,不是有效 User ptr;未来 segfault;违反 §Java/TS 语法优先(用户用户手 ptr cast = 内存裸操作,SS 编译器不暴露)✗ |

---

## 5. 决策

**选 A — V=class 不在 @RequestParam 域,起独立 I021-modelattribute / I021-requestbody issue**:

1. **I021 §下轮 list line 68 改写**:`"I021d — @RequestParam V=class(I020c mirror,需 D067 T? narrow 配合可空形参)"` → `"I021d 域归属辨析 — @RequestParam V=class **不在 @RequestParam 域**,跨域问题独立 D129 讨论 → docs/3-decisions/D129-request-param-class-domain.md"`
2. **未来 V=class 反序列化能力**起独立 issue:
   - `I021-modelattribute` — @ModelAttribute query string 多 key → class 多字段 binding **[Status: Dropped 2026-04-25 — 详 §9 备注 §"I021-modelattribute Dropped 锚"]**
   - `I021-requestbody` — @RequestBody JSON body → class 反序列化
3. **本 D 文档不动代码** — 纯辨析 + 描述修正(I021 §下轮 list 改写本轮同步);未来 I021-modelattribute / I021-requestbody 实施时再起 lib 层 deserializer 基础能力 issue
4. **lib 层 deserializer 基础能力**(query → class field map / JSON → class field map)如何落地由未来 I021-modelattribute / I021-requestbody 决策 — 本 D 文档**不预设**实现路径(留独立决策档讨论)

---

## 6. 反向 / 备选

**备选 B(扩 @RequestParam 域支持 V=class)**:
- 优点:I021d 保留在 I021 子档族,无需改 §下轮 list
- 缺点:违反 Spring 框架契约;query string 单值 → class 多字段 物理不可行;Java parity 永久断裂 ✗

**备选 C(SS 私有 @RequestParam(complex=true))**:
- 优点:SS 自定义灵活
- 缺点:非 Java parity;违反 CLAUDE.md §Java/TS 语法优先;混淆 Spring 框架契约 ✗

**备选 D(按 I020c mirror 走 cast lowering)**:
- 优点:复用 I020c inttoptr cast 路径
- 缺点:物理不可行 — query string 是 url-encoded string 非 ptr 整数;cast 任意 string → ptr 直接 segfault ✗

**不做(选 A 的反向 → 后果)**:
- I021 §下轮 list "I020c mirror" 描述持续破裂,未来 Claude 接 I021d 任务时按 cast 模式实施 → 物理 RED + 跨域污染 @RequestParam 实现
- @RequestBody / @ModelAttribute 域基础能力(deserializer)永久无独立 issue 承载,Phase 4+ Spring parity enterprise 尺度兑现在 class 反序列化维度永久断裂

---

## 7. 单一判据 验证

本 D 文档不动代码,验证只在文档层:

- ✅ I021 §下轮 list line 68 改写完成(I021bc 子 issue 创建轮同步改写,本 D 文档创建轮同时进行)
- ✅ I021 §下轮 list 不再出现 "I021d — V=class(I020c mirror)" 表述
- ✅ 未来 Claude 接 I021d 任务时,先读 D129 →明确 V=class 不在 @RequestParam 域 → 起独立 I021-modelattribute / I021-requestbody issue,不在 I021 / I021bc 子档族扩 V=class
- ✅ d_doc_index_linter.ss 验 D129 引用通(I021 §下轮 list line 68 引 D129;本 D 文档引 I021 / I021bc / I020c)

---

## 8. 影响

- **文档层**:I021 §v0 scope §留下轮 line 68 改写(本 D 文档创建轮同步改);后续未来 I021-modelattribute / I021-requestbody 起立时各引 D129 §5 决策段(域归属确认)
- **代码层**:**零改动**(本 D 文档不动代码)
- **reflection_linter**:**零影响**(无代码改动)
- **commit**:本轮(D129 落档轮)commit 含 I021bc 子 issue + D129 + I021 主 issue 状态翻译 + §下轮 list 改写,文档变更聚合一次 commit

---

## 9. 备注

- **辨析锚源**:用户 2026-04-25 立项分流推荐时识别 "I021 §下轮 list 'I020c mirror' 描述与 @RequestParam 域语义破裂"(commit 3744f4a + d0a109f §Root Cause 第一法则按根因解决度分流推荐之一)
- **Spring 框架契约源**:Spring Boot 3.x Reference Guide §Web §Request Mapping(@RequestParam / @RequestBody / @ModelAttribute / @PathVariable 四 annotation 域契约定义)
- **未来 V=class 反序列化能力**:lib 层 deserializer 基础能力(query → class field map / JSON → class field map)如何落地由未来 I021-modelattribute / I021-requestbody 决策档讨论,本 D 文档不预设实现路径
- **D067 T? narrow alignment**:本 D 文档不破 D067 主策略;未来 I021-modelattribute / I021-requestbody 实施时若涉及 V=class 可空形参,各自子决策段引 D067 narrow 机制(类比 I020c §I020c 子决策段对 D067 alignment 模式)
- **Status=Decided 锚**:用户 2026-04-25 立项时明示"起草 docs/3-decisions/D129 独立讨论 I021d V=class 域归属",起草 + 独立讨论 暗示用户预留审议空间;同日 next_prompt option a "D129 V=class 域辨析正式 Decided + I021-requestbody 起子档" 用户拍板 = 审议接受 + 锁 Decided + 起 I021-requestbody 子档(本文 §5 line 130 决策落地于 `docs/4-issues/I021-requestbody.md`,I021-modelattribute 留 next 轮择期立项)
- **I021-requestbody Execute 落地锚**:2026-04-25 next_prompt option a + sub-option b 单轮端到端 Execute 完成(I021-requestbody.md 状态 Planned → Done at 13 file:line);本 D 文档 §5 line 130 "未来 V=class 反序列化能力起独立 I021-requestbody / I021-modelattribute issue" 第二支柱第一半(I021-requestbody)兑现,第二半(I021-modelattribute query string → class 多字段 binding)留 next 轮择期立项
- **I021-modelattribute Dropped 锚**(2026-04-25):§5 line 129 第二半承诺 I021-modelattribute 翻 **Status: Dropped**(本轮 next_prompt option A+C 用户拍板,与 D129 §5 line 129 标 Dropped + I021-requestheader 起子档承载第四主流注解 同轮决策)
  - **deferred-reason**:@ModelAttribute 仅在传统 server-rendered 模板(JSP/Thymeleaf form submit)+ multipart 复杂表单字段两类场景使用,纯 REST 微服务/前后端分离架构几乎不碰;Phase 4 三支柱(@PathVariable + @RequestParam + @RequestBody)+ I021-requestheader 第四注解已覆盖现代 REST API 95%+ 真实场景,留 backlog 不开发
  - **锚源**:本轮(2026-04-25)next_prompt option A 推 I021-modelattribute 起子档时,用户判断"这个东西我怎么没有用过?不重要吧?这个功能可以不实现吧" — 反思 next_prompt 推此 option 时**没反问"这个承诺本身指向真实需求吗"** 漂违 §第一性需求覆盖度排序原则(对应 memory `feedback_root_cause_no_cost`),即时改 A+C 重排消除"为决策而决策"漂移
  - **跨档历史 trace 保留**:§9 上方 §"未来 V=class 反序列化能力" / §"D067 T? narrow alignment" / §"Status=Decided 锚" / I021-pathvariable §95 / I021-multi-param §82 / I021-requestbody §120/§252/§267/§277/§289 等历史 ModelAttribute 提及保留作辨析当时记录,不批量改写(SSoT 单点登 §9 本锚足,§M §字段 9 deprecate-gate 已跑语义覆盖验证);未来 Claude 触碰这些位置先读 §9 本锚确认 Dropped 状态
  - **重启路径**:若未来 enterprise 用户实证需求出现(server-rendered 模板回归 / multipart 复杂表单场景),可重新起 I021-modelattribute v0 落地
