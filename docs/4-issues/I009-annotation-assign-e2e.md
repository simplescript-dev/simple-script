# I009 — 端到端验收:ASSIGN + 混合值类型 annotation

**父决策:** D123 §C.5 层 A 翻案 端到端验收
**状态:** Draft
**颗粒度:** ~1-2 万 token
**依赖:** I001-I006 全部 Done
**创建:** 2026-04-22

## 上下文

I001-I006 各自独立落地,需端到端测试保证集成无回归。典型场景取自真实 Spring Boot 用法:

```java
@RequestMapping(
  value = "/api/users",
  method = RequestMethod.GET,
  headers = {"Accept=application/json"},
  produces = MediaType.APPLICATION_JSON_VALUE
)
```

## 范围

新建 `tests/phase5/spring_annotation_e2e.ss`:
- ASSIGN 命名参语法(I001)
- string value(I003 基础)
- enum member access(I004)
- array literal(I005)
- class / enum mixed value(I006)

annotation handler 读回所有值类型正确。

## 步骤

1. 写 e2e 测试文件(覆盖 5 种值类型,组合 annotation)
   ```ss
   enum HttpMethod { GET, POST }
   class JsonHandler {}

   @RequestMapping(
     path = "/api/users",
     method = HttpMethod.GET,
     headers = ["Accept=application/json"],
     handler = JsonHandler
   )
   function users() {}

   function main() {
     const meta = reflect.getAnnotation(users, "RequestMapping")
     assertEqual(meta.args.getString("path"), "/api/users")
     assertEqual(meta.args.getString("method"), "HttpMethod.GET")
     assertEqual(meta.args.getArray("headers")[0], "Accept=application/json")
     assertEqual(meta.args.getString("handler"), "JsonHandler")
   }
   ```
2. bootstrap 固定点验证
3. 对比 legacy `tests/phase5/spring_web_params.ss`:后者用旧 D121 R2-A COLON 语法,同步重写为 ASSIGN 或删除(legacy 残留,import `@/lib/spring/boot` 路径也不存在)
4. 跑 `tools/spring_boot_annotation_linter.ss` 确保 annotation 白名单无 fake

## 反向

不做 → I001-I006 各自单测,集成 bug 潜伏(annotation value 类型分派在同一个 eval 函数,跨类型交互场景单测覆盖不到)

## 验收 RED 命令

```bash
bin/ss run tests/phase5/spring_annotation_e2e.ss     # PASS
./build.sh bootstrap                                 # 固定点
bin/ss run tools/spring_boot_annotation_linter.ss    # 0 fake annotation
```

## 备注

- 本 issue 是 D123 **Phase 1 的前置 gate**
- e2e 通过后,D123 Phase 1(`@SpringBootApplication` comptime entry)方可启动
- annotation handler API 最终锁定于 D127 §A.1 SSoT:`getString` / `getInt` / `getBool` / `getDouble` / `getArray`(落地于 `bootstrap/gen/exprs/exprs_ct_builtin.ss:ctMapMethod` 230 行)。`getEnum` / `getClass` 未实装 —— enum 成员访问 (`HttpMethod.GET`) 由 `getString` 返字符串化形态 `"HttpMethod.GET"`,class 裸类名引用 (`JsonHandler`) 由 `getString` 返类名字符串 `"JsonHandler"`(D127 §A.2 / I006 锁定方向)
