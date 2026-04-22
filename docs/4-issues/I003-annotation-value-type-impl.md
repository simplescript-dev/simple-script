# I003 — Annotation args 值类型落地实现

**父决策:** D123 §C.5 层 A 翻案 第 2-3 项
**状态:** Draft(待 I002 决策)
**颗粒度:** ~7-10 万 token(上限;若实际写时超,按 003a/003b 二分)
**依赖:** I001(ASSIGN parser)、I002(类型选型)
**创建:** 2026-04-22

## 上下文

I002 裁决后的类型(假定方案 A `Map<string, AstNodeId>`)在 checker / comptime / getArg 全链路落地。

## 范围

- checker 层 `AnnotationMeta` 结构:args 改 `Map<string, int>`(AstNodeId 即 int)
- parser 层 `parseAnnotation`:存 AST 节点 ID 而非字符串化
- comptime 层 `evalAnnotationArg(key)`:新增,按节点 kind 分派 eval
- 所有现有 `annotation.args.get(k)` 消费点 review:原来返回 string,现在要走 eval
- 向后兼容:I001 已落地的 pure-string annotation 测试应继续 pass

## 影响面调查(实现前必做)

```bash
grep -rn "AnnotationMeta" bootstrap/ lib/ tools/ tests/
grep -rn "annotation\.args\|\.args\.get" bootstrap/ lib/ tools/ tests/
```

估算:checker 存储点 1-2 处,读取点 5-15 处(取决于 D121 R2-A 落地范围)。**若读取点 > 10 处**,本 issue 拆 003a/003b。

## 步骤

1. `bootstrap/checker/` 下 AnnotationMeta 定义改类型(Map<string,string> → Map<string,int>)
2. parser 改:存 AST node id
3. 新增 `bootstrap/comptime/eval_annotation.ss`(或扩现有 comptime eval 入口):
   - `STRING_LIT` → string(I003 本身落)
   - `INT_LIT` → int(I003 本身落)
   - `BOOL_LIT` → bool(I003 本身落)
   - `MEMBER_ACCESS`(enum) → 交给 I004
   - `ARRAY_LIT` → 交给 I005
   - `IDENT`(class 引用) → 交给 I006
4. 消费点适配(优先级:依赖 annotation 的内置处理 → 用户代码 annotation handler)
5. 向后兼容测试:`tests/phase4/annotation_assign_args.ss`(I001 落地的)继续 PASS
6. bootstrap 固定点验证

## 反向

不做 → annotation 只能读 string,enum/array/class/int/bool 值无法消费 → Spring Boot 复刻无法进 Phase 1 以上

## 验收 RED 命令

```bash
./build.sh bootstrap                                    # 固定点 pass
bin/ss run tests/phase4/annotation_assign_args.ss       # I001 兼容
bin/ss run tools/reflection_health_linter.ss            # 反射指标不漂
```

## 备注

- 本 issue 只落**基础 string/int/bool** 消费路径。enum(I004)、array(I005)、class(I006)是各自独立实现 eval handler,插入本 issue 建立的分派表
- 拆分兜底:若实际实现时 token 超 10 万,按"parser + AnnotationMeta 改"(I003a)与"所有消费点适配"(I003b)二分
