# I001 — Parser: ASSIGN 命名参替 COLON

**父决策:** D123 §C.5 层 A 翻案 第 1 项 / D121 R2-A 反转
**状态:** Draft
**颗粒度:** ~1-2 万 token
**依赖:** 无(起点)
**创建:** 2026-04-22

## 上下文

D121 R2-A 原定 annotation 参数语法:`@Name(k: v, ...)`(COLON)。
user turn 5(2026-04-22)推翻,要求对齐真实 Java Spring Boot 语法:

```java
@RequestMapping(value = "/{accessLogId:.+}", method = RequestMethod.GET)
```

也即 ASSIGN `=` 替 COLON `:`。

本 issue 只解决**纯 string value + ASSIGN 语法**,其余值类型由 I003-I006 覆盖。

## 范围

- `bootstrap/parse/parse_exprs.ss` 或 `parse/parse_stmts.ss`:定位 annotation arg list 解析函数(大概率 `parseAnnotation()` / `parseAnnotationArgs()`)
- 把消费 `COLON` token 的位置改为消费 `ASSIGN` token
- lexer 无需改(`ASSIGN =` 已有)
- 新增测试文件 `tests/phase4/annotation_assign_args.ss`

## 反向 / 备选

**备选 A:** 双支持(ASSIGN + COLON 过渡期)
- 优点:不破坏 D121 R2-A 已有测试
- 缺点:违反 user turn 5 "这个是不对的" 明确否定 → 拒绝

**备选 B:** 纯 ASSIGN(推荐)
- 优点:对齐 Java 真实,无双轨
- 成本:D121 原 COLON 测试全改写

不做:D123 Phase 1 永远无法进入真实 Spring Boot 复刻。

## 步骤

1. `grep -rn "parseAnnotation\|ANNOTATION" bootstrap/parse/` 定位解析入口
2. 读原 COLON 消费点,改 ASSIGN
3. 原 COLON 测试样例更新为 ASSIGN 写法
4. 新测试 `tests/phase4/annotation_assign_args.ss`:
   ```ss
   @Foo(a = "x", b = "y")
   class Bar {}
   ```
5. `./build.sh bootstrap` 固定点验证

## 验收 RED 命令

```bash
bin/ss run tests/phase4/annotation_assign_args.ss   # 打印 PASS
./build.sh bootstrap                                # 固定点 pass
```

## 备注

- 此 issue 单独落地时,annotation value 仍限 string literal,其他类型(enum/int/bool/array/class)parser 仍报错 — 这是有意的,防止无类型支持时提前放出语法
- 消费侧 `AnnotationMeta.args: Map<string, string>` 暂不改,I002/I003 重新设计
