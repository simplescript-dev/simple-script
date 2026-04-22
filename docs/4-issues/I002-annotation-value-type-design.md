# I002 — Annotation args 值类型选型决策

**父决策:** D123 §C.5 层 A 翻案 第 2-3 项 / D121 R2-A 扩展
**状态:** Draft(决策待裁)
**颗粒度:** ~3-5 万 token
**依赖:** 无(可与 I001 并行)
**创建:** 2026-04-22

## 上下文

`AnnotationMeta.args: Map<string, string>` 不够承载:
- enum 成员访问:`method = RequestMethod.GET`
- int / bool / double 字面量:`timeout = 5000`、`required = true`
- array 字面量:`value = ["GET", "POST"]`
- class 引用:`handler = MyHandler.class` 或 SS 风格 `handler = MyHandler`

需重新设计 args 值承载机制。

## 候选方案

### 方案 A:`Map<string, AstNodeId>`

存原 AST 节点 ID,comptime 阶段 eval。

**优点:**
- 实现最小(parser 改一行,把字符串化改成存节点 ID)
- 保留完整源位置信息(node.line / col)
- 表达式可任意复杂

**缺点:**
- 消费侧每次 getArg 都要 eval,性能劣于预 eval
- checker 校验时要反复走 node 结构

### 方案 B:`Map<string, CtValue>`(CtValue = tagged union)

新类型 `CtValue { tag: string, str?, int?, bool?, enumName?, ... }`。checker 阶段把 AST 表达式 eval 成 CtValue。

**优点:**
- 消费侧读取简单:`ct.str` / `ct.intVal`
- 所有 annotation 值在 checker 完成 eval,之后只读
- 类型边界清晰

**缺点:**
- 新增 CtValue 类型 + 所有消费点改
- SS 现无 tagged union,需用 class 或 Map 模拟(增加 LOC)

### 方案 C:`Map<string, string>` + eval-on-read(保存表达式文本)

保持 Map<string,string>,value 存表达式源文本,读时 parse+eval。

**优点:** 零结构改动

**缺点:**
- string ↔ AST 双向转换 ugly(违反 human_readable)
- 源位置丢失
- 违反 no_workaround(string 编码内部数据)
- **直接拒绝**

## 推荐方向(待用户裁决)

**方案 A**(AstNodeId 存法)。理由:
1. 实现颗粒度最小(I003 可压到 3-5 万 token,不超 10 万)
2. 源位置完整保留,错误信息友好
3. 与 D088 comptime 路线一致(annotation 本就是 comptime 消费)
4. A → B 可演进(未来性能敏感时 checker 缓存 CtValue),反向不通

## 输出

裁决后产物:
- 新建 `docs/3-decisions/D127-annotation-value-types.md`(或扩 D121 R3 / R4)
- 记录选型 + 方案比较 + 拒绝 C 的理由

## 反向

不做 → I003 卡住 → 所有非 string value issue(I004-I006)全卡住 → D123 Phase 1 永不启动

## 步骤

1. 列三方案的 LOC / 复杂度 / 演进性
2. 推荐方案 A(或用户指定)
3. 写 D 文档(D127 新建 or D121 R3 扩)

## 验收 RED 命令

```bash
ls docs/3-decisions/D127*.md     # 决策文档存在(若选方案 A 且新建 D127)
# 或
grep -n "R3\|R4" docs/3-decisions/D121*.md   # 若扩 D121
```

## 备注

- 此 issue **只输出决策**,不改代码
- 决策裁定后,I003 按决策实现
- CtValue 若采方案 B,需同时裁"用 class 还是 Map 实现 tagged union"(次级选型)
