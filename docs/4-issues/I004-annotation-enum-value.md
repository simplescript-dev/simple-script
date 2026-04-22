# I004 — Enum 成员访问作 annotation value

**父决策:** D127 §A.1 第 4 项(D123 §C.5 层 A 翻案)
**状态:** Done at `bootstrap/eval/interp_obj.ss:148-177` (2026-04-22)
**颗粒度:** ~3-5 万 token
**依赖:** I003(annotation value eval 分派表)
**创建:** 2026-04-22

## 上下文

Spring Boot 典型用法:

```java
@RequestMapping(value = "/x", method = RequestMethod.GET)
```

`RequestMethod.GET` 是 enum 成员访问。SS annotation value eval 需识别 `MEMBER_ACCESS` 节点且 LHS 是 enum 类型时,产出 enum value。

## 范围

- `bootstrap/comptime/eval_annotation.ss`(I003 建立的):新增 `MEMBER_ACCESS` 分支
- checker 识别 `MEMBER_ACCESS.LHS` 是否为 enum 定义(走 `enumDecls` map 查询)
- eval 输出:enum ordinal + enum name(或 enum value 对象,视 I002/I003 结构)
- 错误场景:
  - LHS 不是 enum(是类) → 交给 I006 class 引用路径
  - LHS 未定义 → 报 "undefined symbol" 错

## 步骤

1. checker 侧增加 `MEMBER_ACCESS → enum` 的解析逻辑(若已有,复用)
2. comptime eval MEMBER_ACCESS:
   - LHS 是 enum 名 + RHS 是合法 member → 返回 enum value
   - LHS 是类名 → 抛"交给 I006"的 TODO(如 I006 先落,直接走 I006)
3. 新测试 `tests/phase4/annotation_enum_value.ss`:
   ```ss
   enum HttpMethod { GET, POST, PUT }
   @Route(method = HttpMethod.GET)
   function handler() {}
   ```
4. annotation handler 读回 `@Route.method` 应得 `HttpMethod.GET` 的 ordinal + name

## 反向

不做 → `@RequestMapping(method = RequestMethod.GET)` 无法解析 → 控制器路由表 codegen 阶段 fail

## 验收 RED 命令

```bash
bin/ss run tests/phase4/annotation_enum_value.ss    # PASS
./build.sh bootstrap                                # 固定点
```

## 备注

- 本 issue 不涉及 enum 定义本身的特性(SS 已有 enum,见 D066)
- 只扩 annotation value eval 路径对 enum member 的识别
- 与 I006 共享 `MEMBER_ACCESS` / `IDENT` eval 分派点,二者先后落地任一都 OK,另一方补 else 分支即可
