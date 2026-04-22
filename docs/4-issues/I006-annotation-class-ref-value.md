# I006 — Class 引用作 annotation value

**父决策:** D123 §C.5 层 A 翻案 第 5 项(Other expression forms - class ref)
**状态:** Draft(含语法子决策)
**颗粒度:** ~3-5 万 token
**依赖:** I003、I004(共享 `MEMBER_ACCESS` / `IDENT` 路径)
**创建:** 2026-04-22

## 上下文

Spring Boot 典型用法:

```java
@Import(MyConfig.class)
@ConditionalOnClass(name = "com.foo.Bar")
@AliasFor(annotation = RequestMapping.class)
```

`.class` 是 Java 特有语法(类字面量),SS 是否跟进?

## 子决策:class 引用语法

### 方案 A:SS 风格,裸类名 `@Import(MyConfig)`

**优点:**
- 与 TS 对齐(TS 类是值,裸名即引用)
- 语法简洁,无新关键字

**缺点:**
- 与 Java 原生不同(用户从 Java 迁移要改一次)
- parser 需识别"裸标识符在 annotation value 位置 + 是类名"

### 方案 B:Java 风格,`@Import(MyConfig.class)`

**优点:**
- 与 Java 1:1 对齐
- 明确意图(`.class` 作为类字面量关键字)

**缺点:**
- SS 无 `.class` 语法,需新增(MEMBER_ACCESS 的特例)
- 违反 `feedback_no_new_keywords`(不引入新关键字)
- 与 D088 Zig route 有张力

### 方案 C:两者都支持

**缺点:** 双轨违反 single-path 原则 → 拒绝

## 推荐方向(待用户裁决)

**方案 A**(裸类名)。理由:
1. 符合 SS "Java/TS 优先" 原则中 TS 侧
2. `no_new_keywords`(不引入 `.class`)
3. parser 实现与 I004 `MEMBER_ACCESS` / `IDENT` 路径复用:`Foo` 是 IDENT 节点,checker 判"类名" vs "enum 名" vs "变量名" 分派到不同 CtValue
4. 从 Java 迁移成本:`.class` → 裸名是 sed 级改写

## 范围

- `bootstrap/comptime/eval_annotation.ss`(I003):`IDENT` 节点在类名查表命中 → `ClassRef` value
- CtValue(方案 B 若采用)新增 `ClassRef` tag;或 AstNodeId(方案 A)直接存节点
- annotation handler API:`args.getClass(k)` 读 Class 引用(返回 TypeInfo 或 class 名)

## 步骤

1. 子决策裁定(A / B)
2. eval_annotation.ss 新增 `IDENT → ClassRef` 分派
3. 新测试 `tests/phase4/annotation_class_ref.ss`:
   ```ss
   class MyConfig {}
   @Import(MyConfig)
   class App {}
   ```
4. annotation handler 读回 `@Import.value` 应得 MyConfig 的 TypeInfo / class 名

## 反向

不做 → `@Import(Config)` / `@ConditionalOnClass(Config)` 无法解析 → Spring Boot 配置类、条件装配机制无法复刻

## 验收 RED 命令

```bash
bin/ss run tests/phase4/annotation_class_ref.ss   # PASS
./build.sh bootstrap                              # 固定点
```

## 备注

- 本 issue **有子决策**(class 引用语法)。若用户选方案 B,实现 LOC + 1-2 万 token(新增 `.class` 关键字 + parser + lexer)
- IDENT 在 annotation value 位置的查表顺序:enum 名(I004) → 类名(I006) → 未定义报错
- 与 I004 共享代码路径,可合并实现为一个 PR(但拆成两个 issue 便于独立裁决语法方向)
