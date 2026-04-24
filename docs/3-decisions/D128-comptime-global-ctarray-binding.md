# D128: 顶级 const Array/Object/Map = comptime{...} ctVars 全局 scope binding

**Status:** firm(D098 §D112 同模式扩三 kind,工程闭合)
**Depends on:** D098 §决策 3 Phase A(代号 D112,type kind 全局 ctVars `:${name}` 路径已调通);D120(reflect.classes 是顶级 ctArray comptime 展开枚举入口);I014 §路径 A(本地 CONST ctArray binding 已支持,gen_decls.ss L508-516)
**Triggered by:** I015 §风险 §"SS 顶级 ctArray binding 未实测"
**Date:** 2026-04-24
**Last Updated:** 2026-04-24

---

## 核心目标 (Goal)

- **为什么**:I015 路径 A 要求顶级 `const _ssRoutes: Array<RouteMeta> = comptime { ... }` 全局绑定供 dispatch 与 SpringApplication.run 跨函数复用,消除 routes comptime block 跨函数 copy-paste(I015 §第一性需求 enterprise 尺度兑现的 maintenance 债)。**实测**(本轮 /tmp/i015_repro.ss + bin/ss build --emit-ir)证实当前编译器顶级 ctArray binding **不支持** —— `genGlobalVar` array/object/map 走 runtime alloca + globalInitIds 队列(`@_items = global ptr null` + `store ptr 0`),消费侧 for-in 走 `ss_arrayLen` / `ss_arrayGet` runtime for 而非 ct-array unroll,且 inferType 对 runtime alloca pointer 推 int 撞类型错。
- **是什么**:把 D098 §D112 已为 `type` kind 调通的全局 ctVars `:${name}` 模式 + evalIdent fallback,**平推**至 `array` / `object` / `map` 三 kind。两点工程改动:`gen_decls.ss` `genGlobalVar` 加 array/object/map CONST 分支 → ctVars `:${name}` + return 跳 runtime alloca;`eval/ident.ss` `evalIdent` 加 `:${ctIdName}` 全局 ctArray/Object/Map fallback。
- **单一判据**:
  1. 顶级 `const _arr: Array<UserClass> = comptime{...}` build 成功且 `--emit-ir` 不含 `@_arr = global ptr null`(应不 emit;ctVars 绑定不落 runtime IR)
  2. 跨函数 `for (x in _arr)` 走 ct-array unroll(IR 不含 `forin.cond` label / `ss_arrayLen` / `ss_arrayGet` 调用)
  3. I015 hello example `bin/ss build examples/spring-parity/hello/ss/main.ss` GREEN,`/tmp/hello_ss --serve` 行为 byte-identical "Hello, World!"

> 口号:D098 §D112 type 通了一格,D128 把 array/object/map 三格平推填齐。

---

## 核心原则 (Principles)

1. **D098 §D112 同模式平推,非新设计** — type kind 全局 ctVars 路径已立决,本 D 文档仅做工程闭合(扩两点 N kind),不引入新机制
2. **CONST 强制条件** — let 可变 ctArray 全局绑定语义复杂(ctInvalidated 跨函数链路未实测),本轮仅扩 CONST,let 推迟
3. **runtime alloca fallback 保留** — 仅当 (a) array/object/map kind + (b) CONST + (c) ceTv > 0 三条件全满足才走 ctVars binding,失败回落 runtime 路径(不破坏既有顶级 let / 非 ctTv 全局变量)
4. **MNK §特定领域 §COMPTIME_EXPR 非标量返回扩展 gate** — 本 D 文档对 D112 全局 scope 同模式平移,扩 `genGlobalVar` 而非 inferType 三处(inferType 已在 I014 §路径 A 扩 array/object/map);本 D 文档不需要新增 inferType 分支

---

## 1. Context Management(上下文管理)

### 必读清单(clear 后 Claude 动手前)

1. 本文档
2. `docs/3-decisions/D098-sema-value-model.md` §决策 3 Phase A(代号 D112,type kind 全局 ctVars 路径)
3. `docs/4-issues/I015-spring-routes-global-const.md` §风险节
4. 关键代码位置:

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/gen/gen_decls.ss` | `genGlobalVar` L213-264 | 扩 array/object/map CONST → ctVars `:${name}` 分支 |
   | `bootstrap/eval/ident.ss` | `evalIdent` L4-43 | 扩 `:${ctIdName}` 全局 ctArray/Object/Map fallback |
   | `bootstrap/eval/ct_driver.ss` | `ctLookupTypeVal` L155-162 | D112 双 scope 查 type kind 范本(本 D 文档不复用,因 type-only 语义内嵌) |

### Stable Facts

| 项 | 值 |
|---|---|
| 决策状态 | firm(本文档锁) |
| 实现进度 | I015 同 commit 一并落地 |
| 下轮起点 | 无独立后续(I015 单一判据 GREEN 即闭环) |

---

## 附录 A: 决策内容

### A.1 `gen_decls.ss` `genGlobalVar` 扩展

L237-241(原 array/object/map fallthrough → runtime alloca)前插分支:

```
} else if ((ceType == "array" || ceType == "object" || ceType == "map") && nGetS2(id) == "CONST") {
    const ceTv = parseInt(ceLit)
    if (ceTv > 0) {
        ctVars.set(`:${name}`, `${ctVal(ceTv)}`)
        return  // 跳 runtime alloca + globalInitIds 队列
    }
}
```

**位置依据**:`if (ceType == "type") { ... return }`(L233-236)同模式平推三 kind,return 不 emitIR 不入 globalInitIds。

### A.2 `eval/ident.ss` `evalIdent` 扩展

L21-23(原 `ctLookupTypeVal` 全局 type fallback)后插分支:

```
// D128: 全局 array/object/map ctVars fallback(D098 §D112 type 同模式扩三 kind)
const ctGlobalKey = `:${ctIdName}`
if (ctVars.has(ctGlobalKey) == 1) {
    const ctGlobalVal = parseInt(ctVars.getString(ctGlobalKey))
    if (isCt(ctGlobalVal) == 1) {
        const ctGptType = interpType(payload(ctGlobalVal))
        if (ctGptType == "array" || ctGptType == "object" || ctGptType == "map") { return ctGlobalVal }
    }
}
```

**位置依据**:D098 §D112 已在 `ctLookupTypeVal` 内做双 scope 查询(`${currentFunc}:${name}` / `:${name}`),type kind 单点收敛;array/object/map 三 kind 因 evalIdent L16-20 已查 `${currentFunc}:${name}`(本地 CONST ctArray),全局 fallback 仅需补 `:${name}`,**不复用** `ctLookupTypeVal`(后者 type-only 语义内嵌)。

### A.3 拒绝方案 B/C

- **方案 B**(全 kind 收敛进 `ctLookupTypeVal` 改名 `ctLookupGlobalCt`):破坏 D098 §D112 type-only 语义内嵌(下游 `resolveCtTypeAlias` 依赖 type kind 守卫),改名涉及多处外链 grep + 兼容旧用法,工程负担大于收益
- **方案 C**(顶级 ctArray binding 强制无 CONST 限定):let 可变 ctArray 跨函数 ctInvalidated 链路未实测,本轮风险敞口

---

## 附录 B: 验证步骤

| 步骤 | 命令 | 期望 |
|---|---|---|
| 1 | `bin/ss build /tmp/i015_repro.ss --emit-ir 2>&1 \| grep '@_items'` | 仅 declare/use,**不含** `global ptr null` |
| 2 | `bin/ss build /tmp/i015_repro.ss --emit-ir 2>&1 \| grep -c 'forin.cond'` | dump() 内 = 0(ct-array unroll) |
| 3 | `bin/ss build examples/spring-parity/hello/ss/main.ss -o /tmp/hello_ss && /tmp/hello_ss --serve & sleep 1 && curl -s http://localhost:8080/hello` | "Hello, World!" byte-identical |
| 4 | `bin/ss build examples/spring-parity/hello/ss/main.ss --emit-ir 2>&1 \| grep -c 'call.*@HelloController_hello'` | ≥ 1(静态分派) |
| 5 | `bin/ss run tools/reflection_health_linter.ss` | GATE PASS,M/N 不升 |
| 6 | `./build.sh bootstrap` | 固定点 |

---

## 附录 C: 扩容申报(F1 gen_decls.ss)

**触发**:本 D128 §A.1 在 `bootstrap/gen/gen_decls.ss` `genGlobalVar` 加 array/object/map CONST 分支 4 行(注释 + condition + ctVars.set + return),首次抵消通过把 `else` 分支内 `if (globalInitIds == "") { ... } else { ... }` 4 行三元化为 1 行(`globalInitIds == "" ? \`${id}\` : \`${globalInitIds},${id}\``),F1 cur=705 = bm=705 紧贴预算。

**reverse 触发**:simplify §Phase 2 readability agent veto 三元(rubric e:simplify 时可读赢简洁;`feedback_root_cause_no_cost`:F1 budget 不是让可读性次优的理由),回 if/else 4 行 → cur=706 触 F1 BLOCK。

**抉择**:走 §B 路径(本文档申报扩容)而非压可读性。本地远距离抵消(改 gen_decls.ss 其他无关函数榨指标)= A 路径远距离禁项。

**delta 表**:

| 指标 | bv 旧 | bm 旧 | cur 新 | bv 新 | bm 新 | 理由 |
|---|---|---|---|---|---|---|
| F1:bootstrap/gen/gen_decls.ss | 690 | 705 | 706 | 706 | 708 | D128 §A.1 净 +4 行(含 readability fallback if/else 救 1 行),buffer 2 行余 |

**抵消路径**:本地半径内已极致(D128 分支压 4 行 + 守卫 `parseInt > 0` ceTv==0 fallthrough else 通用路径 + readability 否决三元后回 if/else 是最低妥协)。无远距离改动。

**新 baseline 预期值**:706(=cur 实测)。

**VCM 实测 vs 预估对账槽**:本轮 cur=706(预估同 cur 实测),无偏差。

---

## 参考

- `docs/3-decisions/D098-sema-value-model.md` §决策 3 Phase A(代号 D112,type kind 全局 ctVars 路径,本 D128 平推三 kind 的范本)
- `docs/4-issues/I015-spring-routes-global-const.md` §风险节(本 D128 触发点)
- `docs/3-decisions/D120-reflect-classes-global-enumeration.md`(reflect.classes 是顶级 ctArray comptime 枚举入口)
- `docs/3-MNK.md` §特定领域 §COMPTIME_EXPR 非标量返回扩展 gate(I014 §路径 A 已扩 inferType / eval_expr / gen_decls 三处,本 D128 在 D112 全局 scope 同模式平移)
- `bootstrap/gen/gen_decls.ss` `genGlobalVar`(实施点 A.1)
- `bootstrap/eval/ident.ss` `evalIdent`(实施点 A.2)
