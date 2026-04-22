# I005 — Array / Bool / Int / Double 字面量作 annotation value

**父决策:** D123 §C.5 层 A 翻案 第 5 项(Other expression forms)
**状态:** Draft
**颗粒度:** ~3-5 万 token
**依赖:** I003
**创建:** 2026-04-22

## 上下文

Spring Boot 典型用法:

```java
@RequestMapping(value = {"/x", "/y"})           // array
@Cacheable(timeout = 5000)                      // int
@Bean(primary = true)                           // bool
@Value("${app.rate:1.5}")                       // string (Java 里一般 string,占位 double 场景较少)
```

SS annotation value eval 需覆盖 array literal、int literal、bool literal、double literal。string literal 已在 I003 基础路径覆盖,此处不重复。

## 范围

- `bootstrap/comptime/eval_annotation.ss`(I003 分派表):新增 `ARRAY_LIT` / `INT_LIT` / `BOOL_LIT` / `DOUBLE_LIT` 分支
- `ARRAY_LIT` 内部元素**递归 eval**(允许 `[EnumA.X, EnumA.Y]` 嵌套 I004 的 enum member)
- 消费侧 API:`annotation.args.getArray(k)` / `getInt(k)` / `getBool(k)` / `getDouble(k)`(命名随 I002 结构)

## 步骤

1. eval_annotation.ss 扩四种 literal 分派
2. `ARRAY_LIT` 特殊:元素递归 eval,产 `Array<CtValue>` 或 `Array<AstNodeId>`(随 I002 决策)
3. 新测试 `tests/phase4/annotation_literal_value.ss`:
   ```ss
   @Cfg(paths = ["/a", "/b"], timeout = 5000, enabled = true, rate = 1.5)
   class Foo {}
   ```
4. annotation handler 读回四种值类型正确
5. 嵌套测试:`@Cfg(methods = [HttpMethod.GET, HttpMethod.POST])`(依赖 I004)

## 反向

不做 → array 类 annotation(`@RequestMapping paths`)全部回退到 string CSV workaround,违反 no_workaround

## 验收 RED 命令

```bash
bin/ss run tests/phase4/annotation_literal_value.ss   # PASS
./build.sh bootstrap                                  # 固定点
```

## 备注

- 单行 array vs 多行 array 语法(如 `[\n  "/a",\n  "/b"\n]`)由 parser 通用 array literal 覆盖,不在本 issue 范围
- double 通常不出现在 annotation(Java 常用 int/string),但免费支持,防未来补补丁
- 嵌套 eval 边界:array 元素可以是任意 CtValue 类型(string/int/enum/class),但 **不允许嵌套 array**(即不支持 `[["a"], ["b"]]`)— Java 也不支持 2D annotation array,对齐即可
