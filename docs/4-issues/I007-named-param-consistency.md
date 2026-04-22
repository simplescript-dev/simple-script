# I007 — SS 全局命名参数语法一致性

**父决策:** D123 §C.5 层 A 翻案 第 2 项(turn 5 引申的元问题)
**状态:** Draft(元决策)
**颗粒度:** ~3-5 万 token
**依赖:** 无(可独立裁决,但影响 I001 边界)
**创建:** 2026-04-22

## 上下文

user turn 5 将 annotation 参数从 COLON(`@X(k: v)`)改为 ASSIGN(`@X(k = v)`),对齐 Java。
但 SS 现有其他命名参场景(如 class 实例化 `new Foo(name: "x")`)仍用 COLON。

**元问题:** 一个语言是否允许两种命名参语法(ASSIGN 在 annotation,COLON 在 function call)?

## 候选方案

### 方案 A:按语义分场景(ASSIGN-for-annotation, COLON-for-call)

**优点:**
- annotation 对齐 Java(已在 I001 落实)
- function call 对齐 TS/Dart(`foo(name: "x")`)
- 两者语义不同:annotation key 是元数据赋值,call key 是形参名标签

**缺点:**
- 同一语法"位置感"(命名参赋值)出现两种符号,新学者可能混淆

### 方案 B:全局统一 ASSIGN

**优点:** 单一符号,最简

**缺点:**
- 与 TS `foo({name: "x"})`、Dart 命名参 `:` 冲突
- function call ASSIGN 会与表达式 `k = v` 混淆(需判上下文)

### 方案 C:全局统一 COLON

**缺点:**
- annotation COLON 违反 user turn 5 明确否定 → 拒绝

## 推荐方向(待用户裁决)

**方案 A**(按语义分场景)。理由:
1. annotation key = "参数赋值" 语义(Java `k = v`)
2. call named arg key = "形参标签" 语义(TS/Dart `k: v`)
3. 两种语义天然不同,符号区分反而清晰
4. Java + TS 双源参考均已如此分化
5. 方案 A 下,I001 的 "纯 ASSIGN" 方向正式确认,双支持路径永久关闭

## 范围

- 输出元决策文档(D128 新建 or 合入 D127)
- **不改代码**(但影响 I001 的"纯 ASSIGN 还是双支持"决定 — A 方案下 annotation 仅 ASSIGN,call 仅 COLON,无双支持负担)

## 步骤

1. 列三方案优缺点
2. 推荐方案 A(用户最终裁决)
3. 写 D 文档

## 反向

不裁决 → 语言层面裂痕,未来 call 场景扩 annotation-like 特性时无指引;I001 方向悬空

## 验收 RED 命令

```bash
ls docs/3-decisions/D128*.md   # 决策文档存在(或合入 D127)
```

## 备注

- 此 issue 只输出决策,不改代码
- 裁决后 I001 的"纯 ASSIGN"方向正式确认(方案 A 下)
- 此决策也波及 function call 未来是否支持 ASSIGN(方案 A 下:永不支持)
