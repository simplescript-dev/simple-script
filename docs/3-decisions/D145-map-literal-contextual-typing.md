# D145: SS Map Literal Contextual Typing — Map 字面量 K,V 双类型从调用上下文反推

**Status:** Phase 1 — RED 复现 + 信息源探查 [✓] Done at commit `<placeholder>` (2026-04-28)— Phase 0 commit `d2fb4e1` 已锁;Phase 1 RED 铁证 `[genVal] unknown kind: OBJ_LITERAL` + LLC error + IR `%5 = call ptr @takesMap1(ptr 0)` silent miscompile + §A.2 H1/H10 实证 PASS + §A.2 H12 parser 不扩错估发现(parse_exprs.ss:508 限定 IDENT key,Phase 2 决策 D 仅 IDENT key 反推,STRING/INT key 留 §Followup)+ D052 入口名修正(ss_mapNew 非 ss_newMap)+ Phase 2 入口锁修正(MAP_LIT 新 kind rewrite + 11 dispatch site 加 case + ss_mapSet i64 cast 复用 gen_builtins.ss:235-246);Phase 0 — D 文档落档 [✓] Done at commit `d2fb4e1` (2026-04-28)— D142 §Followup F5 + D143 §Followup F2 + D144 §Followup F1 **同位三合 sub-D** 起首落档;Map literal `{ "k": "v" }` 在 fn 实参 `Map<string,string>` / class field init / var decl typeAnn 反推 K + V 双类型 — D141 反推机制 + D142 elemType 反推机制 + D143 className 反推机制 + D144 branchType 反推机制同模式扩到 Map literal(K, V 双 inferType 反推);callee PARAM 已结构化 SSoT 复用 + codegen 阶段反推 + eval pre-eval 时序前移 + funcParamTypes 信息源单点;比 D143 略重 — Map literal 反推目标是 K + V 双类型(vs D143 单 className / D142 单 elemType / D141 单 PARAM s2 / D144 单 branchType),且 OBJ_LITERAL 节点与 D143 共享 — callee 类型分叉判定(`Map<K,V>` → Map literal 反推 K+V;`class<X>` → 走 D143 既有 className 反推);D135/D136/D137/D140/D141/D142/D143/D144 范式延续(D144 Phase 0 commit `02415c9` 同模式 — Phase 0 D 文档落档 + Phase 1-5 计划草案 + §A.1 三主候选 + §A.1.1 三实施路径 + §A.2 H1-H13 隐藏假设挑战 + §A.3 废案 + Followup F1-F6 同位映射 D144 §F2-F7)

**Depends on:**
- D141(lambda 参数类型推断 + interface dispatch 集成 — §Followup F4 同位锚)
- D142(array literal contextual typing — §Followup F5 同位锚)
- D143(object literal contextual typing — §Followup F2 同模式合并锚 + **OBJ_LITERAL 节点共享**)
- D144(ternary contextual typing — §Followup F1 同位三合锚)
- D141/D142/D143/D144 §A.1.1 G1 路径(callee PARAM 结构化签名 + codegen 阶段反推 + eval pre-eval 时序)— D145 G1 同模式复刻
- D141/D142/D143/D144 §A.2 H1-H13(funcParamTypes 时序 / setVarType 自然链路 / callee 结构化必要 / 失败硬错粒度 / cross-D 反推时序验证)— D145 同模式假设挑战
- D025(interface dispatch — Map<K,V> 实现含 vtable indirect dispatch 路径不动)
- D052(Map keys array — Map<K,V> 数据结构 + ss_mapNew 入口 + ss_mapSet/ss_mapGet 运行时 + Map keys array 实现)
- D131(`Array<T?>` nullable inner field — Map values 含 nullable inner 时不破契约)
- `bootstrap/parse/parse_exprs.ss:OBJ_LITERAL parser`(待 Phase 1 探查精确 line 号 — D143 已落)
- `bootstrap/checker/check_exprs.ss:OBJ_LITERAL case`(待 Phase 1 探查精确 line 号 — D143 已扩反推)
- `bootstrap/checker/check_types.ss:inferType OBJ_LITERAL case`(待 Phase 1 探查 — D143 已落 fallback "auto")
- `bootstrap/gen/gen_types.ss:isClassType + extractClassName + inferObjLiteralFromType + inferObjLiteralFields`(D143 helper — D145 加 `isMapType` + `extractMapKVTypes` + `inferMapLiteralKVTypes` 同模式扩)
- `bootstrap/gen/gen_runtime.ss + gen/rt/gen_rt_*.ss:ss_mapNew + ss_mapSet`(D052 已落 — D145 codegen 复用)
- CLAUDE.md §Java/TS 语法优先(TS Record literal `const m: Record<string, number> = { "a": 1 }` 主线;Java Map.of(...) 静态工厂兼容;**SS 复用 OBJ_LITERAL `{...}` 语法,callee 类型分叉判定 Map<K,V> 走 Map literal 路径**)
- CLAUDE.md §Root Cause 优先 第一法则(数据层 patch 不允许,接口层 trap 单点信息源)
- `memory/feedback_root_cause_no_cost.md`(成本不是选次优的理由)
- `memory/feedback_no_option_menu.md`(三候选论证 + 决策行)
- `memory/feedback_no_derive_workaround.md`(主线能力缺口不允许 annotation 替代)
- `memory/feedback_h10_cross_d_verify.md`(H10 cross-D 反推时序验证 — D143 实证教训:不可仅 grep 字面 handler,outer call site 通用 pre-eval `genVal(argId)` 才是反推时序关键;D144 H10 PASS 继承)
- `docs/3-MNK.md` §M PSM 九问 + §N VCM 六验(Plan 型 §④ 替换「替代方案对比 + 隐藏假设挑战」)+ §字段 8 "Layer 跨越触发 stop / D 文档独立审查窗口不许吞"

**Date:** 2026-04-28
**Last Updated:** 2026-04-28

---

## 核心目标 (Goal)

- **为什么**:Map literal `{ "k": "v" }` 在 fn 实参 `Map<string,string>` 期望 + class field init / var decl typeAnn 反推 K + V 双类型 — 当前 OBJ_LITERAL 节点(D143 已落 OBJ_LITERAL contextual typing 反推 className 走 class ctor 路径)无 Map literal 路径分叉:`takesMap({ "key": "value" })` 期望 callee `m: Map<string,string>` 时 OBJ_LITERAL 反推到 className 路径走 `<unknown>_new(...)` ctor 失败;用户必须显式 `let m = new Map<string,string>(); m.set("key", "value"); takesFn(m)` 三行临时绑定 + .set 链。D052 Map keys array + ss_mapNew/ss_mapSet 运行时已落,但 callee `Map<K,V>` 期望与 OBJ_LITERAL 反推链路缺失;同样在 fn 实参 `class<User>` 期望 + `{ name: "X", age: 18 }` 走 D143 既有 className 反推不变。D142 §Followup F5 + D143 §Followup F2 + D144 §Followup F1 锁此 follow-up 是反推机制同模式扩到 Map literal 的合并锚。**末层断言可观测否定证据**(Phase 0 实测): `ls docs/3-decisions/D145*.md 2>&1` 当前 = `No such file or directory`(exit=2)— D145 文档落档 RED 成立,本轮 Phase 0 GREEN(commit hash 回填后 `ls` 命中)。
- **是什么**:在 Map literal 作 fn/method 实参时,从 callee 签名查 `funcParamTypes` 反推 OBJ_LITERAL 节点 keyType + valueType 双类型期望(callee 形参类型字符串 `Map<string,string>` / `Map<int,User>` / `Map<string,Array<int>>` 等);**callee 类型分叉判定**:callee = `Map<K,V>` → Map literal 反推 K + V 双类型 → codegen emit `ss_mapNew()` + 多个 `ss_mapSet(m, "k", "v")`;callee = `class<X>` → 走 D143 既有 className 反推 → codegen emit class ctor `X_new(...)`(D143 路径不破)。配合 `check_exprs.ss:OBJ_LITERAL case` 改:callee 类型分叉判定 + Map literal K + V 双 inferType 反推回填(节点 slot nSetS2 存 keyType / nSetS3 存 valueType,或单 nSetS2 存 `Map<K,V>` 复合 string),与 ARROW_FUNC `fn(P,...):R` + ARRAY_LIT `Array<elemType>` + OBJ_LITERAL `class<ClassName>` + TERNARY `branchType` 结构化前置完全同形(扩到双类型);参 D141/D142/D143/D144 H1 实证 — checker 阶段 funcParamTypes 用户函数为空,反推必须在 codegen 阶段;参 D141/D142/D143/D144 H10 实证 — eval pre-eval 在 OBJ_LITERAL emit 之前,反推必须前移到 outer call site 通用 pre-eval `genVal(argId)` 之前。
- **单一判据**:untyped Map literal spike(写 `takesMap({ "key": "value", "key2": "value2" })` 直接传入 fn 形参 `m: Map<string,string>`)= D145 §第一性需求 末层断言 RED → 根因修后实测 spike GREEN(对照 IR emit `ss_mapNew()` + `ss_mapSet(m, "key", "value")` + `ss_mapSet(m, "key2", "value2")` 链 + Map<K,V> 类型契约不破 + ss_mapGet 取值返回正确路径不破;无 silent miscompile / 无 D143 className 路径回归);且 lib/ + tests/ 现存 fn 实参 Map literal workaround(若有 `let m = new Map<...>(); m.set(...); takesFn(m)` 形态)Phase 4 cleanup 全删。

> 一句口号:**Map literal K, V 双类型从调用上下文反推 — 用户不必每处 new Map() + .set() 链**(D141 反推机制 + D142 elemType 反推机制 + D143 className 反推机制 + D144 branchType 反推机制同模式扩到 Map literal)

---

## 核心原则 (Principles)

1. **接口层 trap,非数据层 patch** — 信息源单点回填(eval pre-eval 阶段 OBJ_LITERAL 节点 keyType + valueType slot 反推),codegen 路径分叉(`Map<K,V>` callee → emit `ss_mapNew` + `ss_mapSet * N`;`class<X>` callee → 走 D143 既有 class ctor 路径);不在 gen_calls.ss / check_types.ss / gen_decls.ss 多处零散补 fallback(`feedback_root_cause_no_cost.md` 红线)
2. **D141/D142/D143/D144 反推机制同模式扩** — eval pre-eval 时序 + funcParamTypes 信息源 SSoT + codegen 阶段反推 + 失败硬错粒度均沿 D141/D142/D143/D144 §A.1.1 G1 路径;D141 §A.2 + D142 §A.2 + D143 §A.2 + D144 §A.2 假设挑战范式直接复刻
3. **bidirectional type checking 局部** — 仅 Map literal 作 fn/method 实参 + class field init / var decl typeAnn 反推场景,不扩到全编译器全表达式 contextual typing(scope 防爆炸,D141/D142/D143/D144 同位)
4. **TS / Java contextual typing 主线** — TS `const m: Record<string, number> = { "a": 1 }` 等价 + Java Map.of(...) 静态工厂兼容;**SS 复用 OBJ_LITERAL `{...}` 语法 callee 类型分叉判定 Map<K,V> 走 Map literal 路径**(parser 不扩 — `{...}` 仍是 OBJ_LITERAL 节点,反推机制内分叉)
5. **D052 ss_mapNew + ss_mapSet 运行时复用** — D052 已落 Map<K,V> 数据结构 + ss_mapNew 入口 + ss_mapSet/ss_mapGet/ss_mapHas/ss_mapKeys/ss_mapDelete 运行时;D145 反推得 callee `Map<K,V>` 后 codegen emit ss_mapNew + 多个 ss_mapSet 链复用 D052 机制(无重写)— Map<K,V> 类型 annotation 已 D052 落地解析,parser 不扩
6. **OBJ_LITERAL 节点共享 — callee 类型分叉判定**(与 D143 共用 OBJ_LITERAL 节点)— D143 OBJ_LITERAL 反推 className 单一路径(callee = `class<X>`);D145 加 callee 类型分叉判定 + `Map<K,V>` → Map literal 反推 K + V 双类型 → codegen emit ss_mapNew + ss_mapSet * N;`class<X>` → 走 D143 既有 className 反推 → codegen emit class ctor;两路径互不干扰,共享 OBJ_LITERAL 节点 + check_exprs.ss case
7. **callee PARAM `Map<K,V>` 已结构化(无需 G1 callee 升级)— 比 D143 同位** — D141 G1 必须先升级 lib/spring/(jdbc+data).ss 7 处 `setter: fn`;D142 callee `Array<T>` 已结构化无升级前置;D143 callee `class X` 已结构化 + parser 已就绪;D144 callee `T?` 已结构化(D067 已落);D145 callee `Map<K,V>` 已 D052 落地结构化(`Map<int,string>` / `Map<string,Array<int>>` 嵌套泛型 parser 已支持) + funcParamTypes 已注册结构化字符串 — Phase 2 不需要 parser 扩 + 不需 callee 升级
8. **bootstrap 隔离破例** — D141 §核心原则 5 + D142 §核心原则 6 + D143 §核心原则 7 + D144 §核心原则 7 同位例外,D145 主线改 bootstrap 修编译器(checker + codegen + eval),与其他 sub-D scope 独立
9. **interface dispatch 不破** — D025 `interface IFoo` 契约 + vtable indirect dispatch 路径不动;Map<K,V> 自身实现含 vtable 不动
10. **funcParamTypes SSoT 复用** — 信息源 `bootstrap/gen/codegen.ss:110-112 + gen/gen_registry.ss:56-57`(`funcParamTypes` Map "funcName:paramIndex" → SS type,含 `Map<K,V>` / `class X` / `Array<T>` / `T?` 等结构化签名),codegen 阶段反推时直接消费,不重复注册
11. **零破坏既有 OBJ_LITERAL** — 现存 OBJ_LITERAL → class ctor 反推路径(D143 已落)继续走原 className 路径,Phase 2 反推仅在 callee = `Map<K,V>` 时 fallback Map literal 路径,显式优先级 > 推断
12. **Phase 计划独立 commit** — 大改档位:Phase 0 D 文档落盘 + Phase 1+ bootstrap 改各独立 commit,§MNK 大改档不打包(D135/D136/D137/D140/D141/D142/D143/D144 范式延续)
13. **VCM 六验全跑** — bootstrap 三阶段固定点 + tests/ 不降 + tests/d052_map_baseline 等 D052 baseline 不降 + tests/d143 D143 路径不回归 + reflection_health_linter GATE PASS no regressions
14. **K, V 双类型反推 — 比 D143 略重** — D143 单 className 反推(单 inferType 调用 + 单 helper extractClassName);D145 双 keyType + valueType 反推(2 个 inferType 调用 + 双 helper extractMapKVTypes 解析 `Map<K,V>` → (K, V) 元组),且 codegen 路径分叉判定 — 比 D143 略重但仍 < D141 ~267 LOC < D144 ~150 LOC(预估 ~140 LOC)
15. **H10 cross-D 反思继承** — D143 H10 教训(`feedback_h10_cross_d_verify.md`)+ D144 H10 PASS 实证 — Phase 1 探查 OBJ_LITERAL eval 时序时不能仅 grep 字面 handler `evalObjLiteral`,必须确认 outer call site 通用 pre-eval `genVal(argId)` 是否在 OBJ_LITERAL 子节点 emit 之前,反推必须前移到 outer call site

---

## 1. Context Management

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D145)
2. CLAUDE.md §Java/TS 语法优先 + §Root Cause 优先 第一法则 + §高层架构 + §交互式单文档
3. 依赖 D 文档:
   - D141 §A.1.1 G1 路径 + §A.2 H1/H10/H11/H13
   - D142 §A.1.1 G1 路径 + §A.2 H1-H13(全 PASS)
   - D143 §A.1.1 G1 路径 + §A.2 H1-H13(全 PASS,**OBJ_LITERAL 节点共享锚**)
   - D144 §A.1.1 G1 路径 + §A.2 H1-H13(全 PASS,H10 cross-D 反思继承)
   - D142 §Followup F5 + D143 §Followup F2 + D144 §Followup F1 — D145 入口同位三合锚
   - D025 interface dispatch
   - D052 Map keys array(`Map<K,V>` 数据结构 + ss_mapNew/ss_mapSet 运行时 + Map<K,V> 类型 annotation 解析)
   - D067 null safety(可空 Map values `Map<string, User?>` 反推)
4. 关键代码位置(Phase 1 探查后精确化 line 号):

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `bootstrap/parse/parse_exprs.ss` | **521-522**(D143 探查锚)| OBJ_LITERAL parser:`newNode("OBJ_LITERAL")` + `nSetList(id, fields)` 占用 nList,s1/s2/s3+i1-i4 全空闲 — Phase 2 选 **nSetS2** 存 keyType + **nSetS3** 存 valueType(双 slot)或单 **nSetS2** 存 `Map<K,V>` 复合 string(待 Phase 1 决策) |
   | `bootstrap/checker/check_exprs.ss` | **285**(D143 探查锚)| OBJ_LITERAL case 入口 — D143 已落 untyped 放行;**Phase 2 改:加 callee 类型分叉判定**(若 callee = `Map<K,V>` 反推 K + V 双类型;若 callee = `class<X>` 走 D143 既有 className 反推) |
   | `bootstrap/checker/check_types.ss` | **D143 OBJ_LITERAL inferType case**(待 Phase 1 探查精确 line 号)| inferType OBJ_LITERAL — D143 已落 fallback "auto";**Phase 2 改:优先读 nGetS2 + nGetS3(keyType/valueType)fallback `class<ClassName>`** |
   | `bootstrap/gen/gen_types.ss` | **544-551**(D143 探查锚)| codegen inferType OBJ_LITERAL — D143 已落 className 反推;**Phase 2 改:加 isMapType + extractMapKVTypes helper + Map literal K/V 反推回填路径** |
   | `bootstrap/gen/gen_calls.ss` | **284**(D143 落点)| args 循环 + inferObjLiteralFields(D143);**Phase 2 加 inferMapLiteralKVTypes 同位 4 落点**(D141/D142/D143/D144 G1 4 落点同模式) |
   | `bootstrap/gen/methods/gen_methods.ss` | **206**(D143 落点)| args 循环;**Phase 2 加 inferMapLiteralKVTypes 同位** |
   | `bootstrap/eval/method_call.ss` | **64**(D143 落点)+ Phase 2 同点追加第 5 行 inferMapLiteralKVTypes(D141/D142/D143/D144 H10 cross-D 反思 outer call site `genVal(argId)`) | outer call site pre-eval |
   | `bootstrap/eval/call.ss` | **36**(D143 落点)+ Phase 2 同点追加第 5 行 | outer call site pre-eval |
   | `bootstrap/eval/new_expr.ss` | **24**(D143 落点)+ Phase 2 同点追加第 5 行(D143 NAMED_ARG OBJ_LITERAL 嵌套反推扩到 Map literal)| outer call site pre-eval |
   | `bootstrap/gen/codegen.ss` | **110-112**(普通函数 funcParamTypes 注册)| `funcParamTypes.set(\`${fname}:${pCount}\`, nGetS2(fpId))` — 含 `Map<K,V>` 字符串(D052 已落)|
   | `bootstrap/gen/gen_registry.ss` | **56-57**(class method funcParamTypes 注册)| `funcParamTypes.set(\`${baseName}:${pCount}\`, nGetS2(pId))` — 含 `Map<K,V>` 字符串 |
   | `bootstrap/gen/codegen.ss` | **326**(`registerAllDecls(rootId)` 在 line 327 `emitGlobalsAndCode(rootId)` 之前)| funcParamTypes 时序保证 |
   | `bootstrap/gen/gen_runtime.ss` 或 `gen/rt/gen_rt_*.ss` | D052 ss_mapNew + ss_mapSet 入口(待 Phase 1 探查精确文件)| 运行时 emit IR `define ptr @ss_mapNew()` + `define void @ss_mapSet(ptr %m, ptr %k, ptr %v)` |
   | `bootstrap/checker/check_types.ss isTypeCompatible` | (Map<K,V> 兼容性判定)| Phase 2 验 Map<K,V> 与 K + V 双 widen 边界 |

### Context 不变量

| 不变量 | 状态 |
|---|---|
| funcParamTypes Map<K,V> 注册 | 已就绪 H1 实证 PASS(D141/D142/D143/D144 H1 同模式继承 — 普通函数 codegen.ss:110-112 / class method gen_registry.ss:56-57 直接注册原始 SS 类型字符串含 `Map<K,V>` 形态,registerAllDecls codegen.ss:326 在 emitGlobalsAndCode 之前)|
| ss_mapNew + ss_mapSet 运行时 | D052 已落 — Phase 2 codegen emit 直接调,无重写 |
| Map<K,V> 类型 annotation 解析 | D052 已落 — parser 支持 `Map<int,string>` / `Map<string,Array<int>>` 嵌套泛型 |
| OBJ_LITERAL inferType 当前 | **check_types.ss + gen_types.ss D143 已落 fallback "auto"** — D145 §A.1 主候选 C2 修复入口锁定;Phase 2 改入口加 callee 类型分叉判定 + Map literal K/V 反推 |
| OBJ_LITERAL checker case 当前 | **check_exprs.ss:285 D143 已落 untyped 放行** — Phase 2 加 callee 类型分叉(`Map<K,V>` vs `class<X>`)|
| OBJ_LITERAL 节点 slot 占用 | nList(D143 OBJ_LITERAL fields),s1/s2/s3+i1-i4 全空闲(D143 反推用 nSetS2 存 className) — **Phase 2 选 nSetS2 + nSetS3 双 slot**(K + V)或单 nSetS2 存 `Map<K,V>` 复合 string(待 Phase 1 决策) |
| OBJ_LITERAL kind dispatch site | 待 Phase 1 探查 8+ 处:parser + checker case + checker inferType + genVal + codegen inferType + eval dispatch + eval handler + PIR(D143 已 grep 全 PASS) |
| 反射 baseline | tools/reflection_health_linter.ss(本 D 不触反射) |
| d_doc_index_linter F1 | Phase 1 实测 PASS(D145 加入未破 referenced Ds — D025/D052/D067/D131/D141/D142/D143/D144 实存,F2 soft warn 含 D145 不阻)|

### 禁止的 Context 操作

- ❌ 改 parser(`Map<K,V>` annotation 已 D052 就绪 — §核心原则 7 + H12 弱)
- ❌ 改 funcParamTypes 注册路径(已就绪 — §核心原则 10)
- ❌ 改 D052 ss_mapNew / ss_mapSet 本体(已就绪,D145 反推得 callee `Map<K,V>` 后**复用** D052 路径,不重写)
- ❌ 改 D143 OBJ_LITERAL className 反推路径本体(D143 路径不破,D145 callee 类型分叉判定加并行路径,**两路径互不干扰**)
- ❌ 起 D146+(留 D141 §F4+ / D142 §F6+ / D143 §F3+ / D144 §F2+ 同模式合并队列,本 D 仅 Map literal;D145 §Followup F1+ 排队后续 sub-D)
- ❌ 改 D141/D142/D143/D144 文档本体(同位例外锚 D145 同模式继承,文档不动)
- ❌ 改 D025/D052/D067/D131 interface dispatch / Map / nullable / 反序列化契约
- ❌ 加全局 bidirectional type checking(C3 候选废 — 范围爆炸,留 SS 类型系统 v2)

---

## 2. Tools

| 工具 | 用途 |
|---|---|
| `./build.sh bootstrap` | 三阶段固定点(Phase 1+ bootstrap 改后必跑) |
| `bin/ss run /tmp/spike_map_lit_red.ss` | spike RED→GREEN 验证(主判据,Phase 1 写入 + Phase 2 实测) |
| `bin/ss test tests/d052_map_baseline/`(若有)| Map 路径 baseline 不降 |
| `bin/ss test tests/d141_lambda_inference/` | D141 反推机制 baseline 不破 |
| `bin/ss test tests/d142_array_literal_inference/` | D142 反推机制 baseline 不破 |
| `bin/ss test tests/d143_object_literal_inference/` | **D143 反推机制 baseline 不破(关键 — OBJ_LITERAL 节点共享路径)** |
| `bin/ss test tests/d144_ternary_inference/` | D144 反推机制 baseline 不破 |
| `bin/ss test tests/` | 全测 baseline 不降 |
| `bin/ss build /tmp/spike_map_lit_red.ss --emit-ir` | IR 层 RED 复现(Phase 1) |
| `bin/ss run tools/d_doc_index_linter.ss` | D 文档治理 gate |
| `bin/ss run tools/reflection_health_linter.ss` | 反射 baseline(本 D 不触反射) |
| `bin/ss run tools/next_prompt_ultrathink_linter.ss` | next_prompt.md 必含 ultrathink |

### 禁止引入

- ❌ 新关键字 / 新语法 / 新 AST 节点(Map literal 反推是反推机制扩展,非语法扩展;OBJ_LITERAL 节点已存 parse_exprs.ss 与 D143 共享)
- ❌ 新依赖(D052 Map 运行时已就绪)
- ❌ 改 codegen 全局 / parser / interpreter / lib(Phase 2 改 checker + 局部 codegen 反推 + eval pre-eval 反推插桩 + codegen Map literal emit 路径分叉,不重写 D052 ss_mapNew 本体 / 不破 D143 className 路径)

---

## 3. Orchestration

### 总体节奏(D141/D142/D143/D144 5 Phase 范式延续)

| Phase | 目标 | 关键产出 | 验证 |
|-------|------|----------|------|
| **Phase 0** | D 文档落档(本 Phase) | `docs/3-decisions/D145-*.md` | d_doc_index_linter F1 = 0 + ultrathink_linter PASS |
| **Phase 1** | RED 复现 + 信息源探查 | `/tmp/spike_map_lit_red.ss`(形态 1-7:单 K-V / 多 K-V / 嵌套 Map / Map<K,Array<V>> / Map<K,User> 类型化值 / Map<K,V?> nullable values / 显式 new Map() + .set 与反推同行)+ IR 层 RED 铁证(callee `Map<K,V>` + OBJ_LITERAL 反推到 className 路径走 `<unknown>_new(...)` ctor 失败)+ funcParamTypes Map<K,V> 字符串实测可用(grep 实证)+ OBJ_LITERAL eval pre-eval vs codegen emit 时序探查(D143/D144 H10 同形成立 — H10 cross-D 反思 outer call site `genVal(argId)`)+ 隐藏假设 H1/H10 复刻验证 + OBJ_LITERAL 节点 slot 占用探查(D143 已落 nSetS2 className,Phase 2 选 nSetS3 valueType 扩或单 nSetS2 复合)| IR RED 铁证 + 时序探查 fact 入 §1 + §A.2 H1/H10 实证记录 + 节点 slot 探查 PASS |
| **Phase 2** | codegen 阶段反推实施 + G1 路径(D141/D142/D143/D144 G1 同模式) | `bootstrap/checker/check_exprs.ss:OBJ_LITERAL case` 加 callee 类型分叉(`Map<K,V>` vs `class<X>`) + `bootstrap/gen/gen_calls.ss:resolveCallArgs` + `gen/methods/gen_methods.ss:emitClassMethodCall` + eval/method_call.ss/call.ss/new_expr.ss outer call site pre-eval 之前反推前移 + `bootstrap/gen/gen_types.ss` 三 helper(`isMapType` / `extractMapKVTypes` / `inferMapLiteralKVTypes`)对偶 D141 + D142 + D143 + D144 helper + **D052 ss_mapNew + ss_mapSet 路径复用**(反推得 callee `Map<K,V>` 后 codegen emit ss_mapNew + 多个 ss_mapSet 链复用 D052 机制)+ codegen 路径分叉(`Map<K,V>` 走 ss_mapNew + ss_mapSet * N;`class<X>` 走 D143 既有 class ctor) | bootstrap 固定点 PASS + spike untyped 反推 GREEN + tests/d143 D143 path 不回归 + tests/d052 baseline 不降 |
| **Phase 3** | 测试覆盖 + 隐藏假设挑战 | `tests/d145_map_literal_inference/` 新增(单 K-V / 多 K-V / 嵌套 Map / Map<K,Array<V>> / Map<K,User> 类型化值 / Map<K,V?> nullable values / 显式 new Map() + .set 与反推同行 / 反推失败硬错诊断)| 6+ test case 全绿 + 隐藏假设 H1-H8 全 PASS |
| **Phase 4** | workaround cleanup | grep + 删现存 fn 实参 Map literal 临时变量绑定 workaround(若有 `let m = new Map<...>(); m.set(...); takesFn(m)` 形态 — Phase 1 grep 实测后定计数;预估 lib/spring/jdbc.ss + lib/json/ + lib/argparse 等多处) | bootstrap 固定点 PASS + tests/ baseline 不降 |
| **Phase 5** | 全 Phase 收关 hash trail | D145 5 Phase commit hash 全列 + 兑现成果 a-g + 隐藏假设全 PASS / OOD 标 + Followup 锚明确 | D145 主线 close |

### Phase 间依赖

- Phase 0 → 1:D 文档落档后用户审,Phase 1 下一轮起
- Phase 1 → 2:RED 成立 + 时序探查就位才启 Phase 2;若 H1 funcParamTypes 时序不就(D141/D142/D143/D144 实证已 PASS,但 Map<K,V> 路径需独立验证)→ 调整 Phase 2 入口
- Phase 2 → 3:bootstrap 固定点 PASS + spike GREEN + D143 path 不回归才启 Phase 3 测试覆盖
- Phase 3 → 4:测试覆盖完整(隐藏假设全 PASS)才启 Phase 4 workaround cleanup
- Phase 4 → 5:cleanup 完整 + tests/ baseline 不降才启 Phase 5 收关

### 反模式

- ❌ 改 parser(`Map<K,V>` annotation 已 D052 就绪 — H12 比 D141/D142/D143/D144 都同位弱)
- ❌ 改 funcParamTypes 注册路径(已就绪)
- ❌ 把 D052 ss_mapNew / ss_mapSet 重写(已就绪,Phase 2 反推得 callee `Map<K,V>` 后 codegen emit 调原 D052 路径)
- ❌ 把 D143 OBJ_LITERAL className 反推路径重写(D143 路径不破,callee 类型分叉判定加并行路径)
- ❌ 顺带改 OBJ_LITERAL 在 var decl RHS 路径(scope 留 sub-D 后续轮 — H6 显式优先)
- ❌ 起全局 bidirectional type checking(C3 候选废,留 留独立 sub-D 评估 — memory feedback_d026_d027_phantom_anchor — generic 已落 gen_generic_class.ss,bidirectional 是真正剩余项)
- ❌ 实施 D141 §F4+ / D142 §F6+ / D143 §F3+ / D144 §F2+ 后续 sub-D(Tuple/spread/partial fields/反推失败粒度等留同模式扩 sub-D 后续轮)

---

## 4. State

### 编译时 state

- OBJ_LITERAL 节点 keyType/valueType slot(待定:nSetS2+nSetS3 双 slot vs 单 nSetS2 存 `Map<K,V>` 复合 — Phase 1 决策;D143 已用 nSetS2 存 className,共享时需互斥语义判定)
- funcParamTypes(已就绪,Phase 2 不改注册路径)
- evalObjLiteral pre-eval 缓存(eval pre-eval,Phase 2 反推前移到 outer call site 通用 pre-eval `genVal(argId)` 之前)
- D052 ss_mapNew + ss_mapSet 调用状态(已就绪,Phase 2 反推得 callee `Map<K,V>` 后 codegen emit 调原 D052 路径)

### 运行时 state

(N/A — 本 D 是 checker + codegen 编译时改,不影响运行时;D052 ss_mapNew + ss_mapSet 链 emit 路径不变)

### 中间产物

- `/tmp/spike_map_lit_red.ss`(Phase 1 写)
- 三候选评估矩阵(本 D §A.1 + §A.1.1)
- 隐藏假设挑战表(本 D §A.2)

### 会话间持久化

- D145 §Phase 进度(clear 后续 Plan 锚,Status 行单一事实源)
- bootstrap 三阶段固定点 commit hash(各 Phase 回填)

### 禁止 state 操作

- ❌ 把 OBJ_LITERAL keyType/valueType 信息保存到全局 Map(节点 slot 已足够 — 与 D141/D142/D143/D144 节点 slot 同范式)
- ❌ 把跨轮进度 / 摘要写到 handoff 文件(`.claude/next_prompt.md` 仅 terman preset 单次 payload)

---

## 5. Evaluation

### 单一判据(必须 GREEN)

```bash
# Phase 1 RED:untyped Map literal + fn 实参 Map<K,V> — 当前必须显式 new Map() + .set 链
cat <<'EOF' > /tmp/spike_map_lit_red.ss
function takesMap(m: Map<string,string>): string {
    return m.get("key")
}
function main() {
    let r = takesMap({ "key": "value", "key2": "value2" })
    println(r)
}
EOF

# Phase 1 RED:bin/ss run /tmp/spike_map_lit_red.ss
# 期望:checker 报错或 silent miscompile(OBJ_LITERAL 反推 className 路径走 <unknown>_new(...) ctor 失败)

# Phase 2 GREEN:bin/ss run /tmp/spike_map_lit_red.ss
# 期望:输出 "value"(反推回填 keyType=string + valueType=string + codegen emit ss_mapNew() + 2x ss_mapSet 链 + ss_mapGet("key") 取值正确)
```

### Phase 2 关键验证

- bootstrap 三阶段固定点 PASS(stage2 == stage3 字节比较)
- spike GREEN(主判据)
- tests/d052_map_baseline 等 D052 baseline 不降
- tests/d141_lambda_inference/ 5 处 baseline 不降(D141 反推机制不破)
- tests/d142_array_literal_inference/ 6 处 baseline 不降(D142 反推机制不破)
- **tests/d143_object_literal_inference/ 6 处 baseline 不降**(D143 反推机制不破 — OBJ_LITERAL 节点共享路径关键)
- tests/d144_ternary_inference/ 8 处 baseline 不降(D144 反推机制不破)
- tests/ 284/4/288 baseline 不降
- reflection_health_linter GATE PASS no regressions

### Phase 3 测试覆盖(隐藏假设挑战)

- 单 K-V `takesMap({ "key": "value" })` callee `Map<string,string>` — H1 反推 K + V + H2 K/V 类型 widen PASS
- 多 K-V `takesMap({ "k1": "v1", "k2": "v2" })` — H1 多 K-V 反推 + H2 ss_mapSet * N 链
- 嵌套 Map `takesMap({ "k": { "inner_k": "inner_v" } })` callee `Map<string,Map<string,string>>` — H3 嵌套反推 capture 链
- Map<K,Array<V>> `takesMap({ "k": [1, 2, 3] })` callee `Map<string,Array<int>>` — H4 嵌套泛型 + 与 D142 ARRAY_LIT 反推合作
- Map<K,User> 类型化值 `takesMap({ "k": new User("X", 18) })` callee `Map<string,User>` — H5 class 实例 value 走 D025 vtable
- Map<K,V?> nullable values `takesMap({ "k": null })` callee `Map<string,User?>` — H6 D067 nullable 复用 + null 分支类型化
- 显式 new Map() + .set 与反推同行(`let m = new Map<string,string>(); m.set("k","v"); takesMap(m)`)— H7 显式优先(D052 既有 + IDENT 实参 skip 反推)
- 推断失败 fallback(callee 不在 funcParamTypes / arity 不匹配 / 非 Map<K,V> callee)→ skip 反推或硬错(参 D141/D142/D143/D144 H13 粒度)

---

## 6. Constraints

### 硬约束

- 不引入 bidirectional type checking 全局(候选 C3 已废,scope 爆炸)
- 不动 D025 interface dispatch 契约
- 不动 D052 ss_mapNew / ss_mapSet 本体(D145 反推得 callee `Map<K,V>` 后复用 D052 路径)
- 不动 D067 nullable 路径本体
- 不动 D131 nullable inner field 反序列化路径
- **不动 D143 OBJ_LITERAL className 反推本体**(D143 路径不破 — D145 加 callee 类型分叉判定 + Map literal 反推并行路径)
- 不动 D141 lambda 反推机制 / D142 array literal 反推机制 / D144 ternary 反推机制(D145 是同模式扩,不重写信息源)
- bootstrap 改不许超过 800 LOC delta(`feedback_600_split_not_inline.md` + `feedback_structure_not_linecount.md`)— 实际预估 ≤ 140 LOC(check_exprs.ss + gen_calls.ss + gen_methods.ss + eval/method_call.ss + eval/call.ss + eval/new_expr.ss + gen_types.ss helper 局部改 — 比 D143 ~130 略重 + 比 D144 ~150 略轻)

### 软约束

- 推断失败时**优先编译期硬错**(参 D141 H13 + D142 H13 + D143 H13 + D144 H13 结构化 callee 硬错粒度);非结构化 callee skip 反推不破现状
- 显式注解仍优先级最高(`let m = new Map<...>(); m.set(...); takesFn(m)` 既有现存)
- 反推查 callee `funcParamTypes` 时,callee 必须已 register(D141/D142/D143/D144 H1 实证 codegen 阶段已就绪)— Phase 1 文档化时序保证

### 风险锚(R1-R5)

| # | 风险 | 描述 | mitigation |
|---|---|---|---|
| R1 | OBJ_LITERAL 节点 slot 占用与 D143 共享冲突 | D143 已用 nSetS2 存 className,Map literal 反推 K + V 双类型若用 nSetS2 + nSetS3 与 D143 nSetS2 互斥语义如何处理(callee = `Map<K,V>` 时 nSetS2 存 keyType vs callee = `class<X>` 时 nSetS2 存 className,语义读取需基于 nGetS2 prefix 判定)| Phase 1 决策 — (a) 单 nSetS2 存 `Map<K,V>` 复合 string + nGetS2 内 startsWith("Map<") 判定走 Map literal vs className;(b) nSetS2 存 keyType + nSetS3 存 valueType + 用 marker(nSetS1 = "MAP" / "" 区分)— Phase 2 实施 + Phase 3 嵌套 Map test |
| R2 | 嵌套 Map 反推链路断 | `{ "k": { "inner_k": "inner_v" } }` 内层 OBJ_LITERAL 字段是 OBJ_LITERAL,反推外层 callee = `Map<string,Map<string,string>>` 后内层也需反推 callee = `Map<string,string>` — 递归回填 | Phase 2 实施 + Phase 3 嵌套 Map test;若失败 → 内层反推回路 fallback 单层 + 用户嵌套时仍需显式 new Map() |
| R3 | Map<K,Array<V>> 嵌套泛型反推 — 与 D142 ARRAY_LIT 反推合作 | `{ "k": [1, 2, 3] }` callee `Map<string,Array<int>>` 反推 K=string + V=Array<int> + V 内层 ARRAY_LIT [1, 2, 3] 反推 elemType=int — D142 + D145 反推链合作 | Phase 1 实测 + Phase 2 决策 — Phase 2 helper extractMapKVTypes 解析 `Map<K,V>` 后 V 字符串若 startsWith("Array<") 自动触发 D142 inferArrayLitElems 链路 |
| R4 | Map<K,V?> nullable values 反推 — 与 D067/D144 nullable 合作 | `{ "k": null }` callee `Map<string,User?>` 反推 V=`User?` + null literal 类型化为 nullable User — D067 nullable + D144 ternary 同形 | Phase 1 grep + Phase 2 reuse D067 nullable 分配 helper + D144 propagate 机制不重写 |
| R5 | callee 类型分叉判定边界 — `Map<K,V>` vs `class<Map>`(用户自定义类名 Map)歧义 | 用户写 `class Map { constructor(...) }` 后 callee `m: Map` 实际是用户 class 而非 SS Map<K,V>,反推应走 D143 className 路径 | Phase 1 探查 — D052 Map 是关键字 / 内置类型 / 用户禁用 className "Map"?若 Map 是关键字保留 → 无歧义;若可与用户 class 同名 → Phase 2 加优先级 native Map<K,V> > 用户 class<Map> 判定 |

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| Phase 1 spike 已 GREEN(无 RED) | 改 spike 形态:多 K-V / 嵌套 Map / Map<K,Array<V>> / Map<K,User?> / 显式与反推同行;若全场景已 GREEN → D145 范围降级为 "类型表达力对齐 D141/D142/D143/D144"(Plan-only,无代码改)|
| Phase 2 build 失败 | git revert;调 OBJ_LITERAL slot 命名 + check_exprs.ss case 同步 |
| Phase 2 嵌套 Map 红 | R2 mitigation:内层反推单层 fallback + 文档化 H3 OOD scope |
| Phase 2 D143 path 回归 | callee 类型分叉判定边界错位 → 回 Phase 2 修判定 + 加 D143 path 回归 test 锚 |
| Phase 2 reflection_health_linter GATE BLOCK | 走 §MNK §反射路径根因 gate B 路径(扩容申报 + 升 baseline + D 文档 §扩容申报段)|
| Phase 4 grep 工作量超估 | 范围限定 lib/ + tests/d052_map_baseline/ 同域,其他 tests/ 留 sub-D 后续轮 |

### 回滚策略

- Phase 1+ 失败 → `git reset --soft HEAD^` 回上一 Phase
- Phase 0 文档已落盘,Phase 1+ 实施 commit 边界严格(D135/D136/D137/D140/D141/D142/D143/D144 范式延续)
- D145 失败回退不影响 D141/D142/D143/D144(D141 + D142 + D143 + D144 主线已 close,D145 仅同模式扩)

---

## A.1 主候选评估(§MNK §M §字段 10 + Plan 型 §④ 替换:替代方案对比)

| 候选 | 层次 | 描述 | 假设破裂入口 | 优势 | 劣势 | 决策 |
|---|---|---|---|---|---|---|
| **C1** | **数据层 patch** | `gen_calls.ss` fn 实参 OBJ_LITERAL 路径加 fallback — OBJ_LITERAL 类型未知时若 callee = `Map<K,V>` 直接 emit ss_mapNew + ss_mapSet 链不在 checker 反推 | 破裂入口在 OBJ_LITERAL inferType 在 D143 反推 className 单一路径,信息丢失;C1 仅在 fn 实参单点补 fallback,不消除根因 — D143 path / classFieldTypes / inferType 等其他消费者仍走错 | LOC 极小 5-10 行;不动 checker | 零散 patch — 多消费者(D143 className / classFieldTypes / inferType / D084 rewrite 等)都用 OBJ_LITERAL inferType,信息源不单点;同模式 Map literal 在 method 实参 / var decl typeAnn 等场景仍 RED | **不选** — 数据层不消除根因(`feedback_root_cause_no_cost.md` 红线,与 D141/D142/D143/D144 §A.1 C1 同形废)|
| **C2** | **接口层 trap** | checker `check_exprs.ss:OBJ_LITERAL case` 加 callee 类型分叉判定(`Map<K,V>` → Map literal 反推 K + V;`class<X>` → 走 D143 既有 className 反推) + codegen 阶段 fn/method 实参反推回填 OBJ_LITERAL keyType + valueType slot + eval pre-eval 时序 + funcParamTypes SSoT 复用 + D052 ss_mapNew + ss_mapSet 路径复用 + codegen 路径分叉 emit | **彻底消除** — OBJ_LITERAL 反推结构化分叉,所有下游(D143 className / classFieldTypes / inferType / Map literal codegen)信息源一致;eval pre-eval 反推前移避免 D141/D142/D143/D144 H10 同形时序破裂 | 单点信息源回填;TS / Java contextual typing 主线;D141/D142/D143/D144 G1 路径同模式复刻;workaround cleanup 落锚;D052 + D143 路径双复用 | LOC 中等 ~140(check_exprs.ss + gen_calls.ss + gen_methods.ss + eval/method_call.ss + eval/call.ss + eval/new_expr.ss + gen_types.ss helper);需考虑嵌套 Map / Map<K,Array<V>> 嵌套泛型 / Map<K,V?> nullable values / callee 类型分叉判定边界 | **选** — 接口层 trap 消除根因 + scope 可控 + D141/D142/D143/D144 同模式复用 + D052 + D143 双路径复用 |
| **C3** | **架构层 refactor** | 全编译器 bidirectional type checking — checker 改 expected/actual 双向类型检查,所有表达式从调用上下文反推类型 | 消除根因 + 消除其他 silent miscompile | 类型系统统一性最高;复用现有 generic 基础设施(已落 gen_generic_class.ss + gen_types.ss:711 resolveTypeParam,memory feedback_d026_d027_phantom_anchor) | scope 爆炸 LOC > 2000 + 多 sub-D + bootstrap 重写多个核心文件;F1 单 sub-D scope 远超(D145 不应承载架构层 refactor) | **不选** — scope 远超 D145 单 sub-D 范围;**D141 §Followup F5 + D142 §A.3 + D143 §A.3 + D144 §A.3 已锁此候选废**,留作未来 SS 类型系统 v2 评估 |

**决策行**:**选 C2 接口层 trap** 因 (a) 单点信息源回填 + callee 类型分叉判定,消除 OBJ_LITERAL inferType 在 D143 单一 className 路径的假设破裂入口;(b) D141/D142/D143/D144 G1 路径同模式复刻 — eval pre-eval 时序 + funcParamTypes SSoT + codegen 阶段反推 + 失败硬错粒度全沿用;(c) D052 ss_mapNew + ss_mapSet 路径复用 — 反推得 callee `Map<K,V>` 后 codegen emit 走原 D052 机制;(d) D143 OBJ_LITERAL className 反推路径并行不破;(e) workaround cleanup 落锚 Phase 4(临时变量绑定 + .set 链形态全删);(f) scope 可控 ~140 LOC delta < D144 ~150 LOC > D143 ~130 LOC ≈ D142 ~91 LOC < D141 ~267 LOC。**为何不选 C1**:数据层 zero-spread 不消除根因(`feedback_root_cause_no_cost.md` 红线,与 D141/D142/D143/D144 §A.1 C1 同形废)。**为何不选 C3**:scope 爆炸 — D141 §Followup F5 + D142 §A.3 + D143 §A.3 + D144 §A.3 已锁 C3 废留 SS 类型系统 v2,D145 单 sub-D 不承载架构层 refactor。

---

## A.1.1 C2 实施路径对比(Phase 0 落档,Phase 1 起首实测确认)

> Phase 0 起首查源:D052 已落 `Map<K,V>` 类型 annotation 解析 + ss_mapNew + ss_mapSet/ss_mapGet/ss_mapHas/ss_mapKeys/ss_mapDelete 运行时 + Map keys array 实现;funcParamTypes 已注册 Map<K,V> 字符串(普通函数 codegen.ss:110-112 / class method gen_registry.ss:56-57);D143 OBJ_LITERAL className 反推路径已落 — **D145 与 D143 共享 OBJ_LITERAL 节点 + check_exprs.ss case + gen_types.ss helper**(D141 必须先升级 lib/spring/(jdbc+data).ss 7 处 + parser 扩;D142 比 D141 更轻无 callee 升级 + 无 parser 扩前置;D143 callee `class X` 已结构化 + parser 已就绪 + D084 rewrite 路径已落;D144 callee `T?` 已 D067 落地;D145 callee `Map<K,V>` 已 D052 落地结构化 + parser 已就绪 + ss_mapNew/ss_mapSet 运行时已落 + D143 OBJ_LITERAL 路径并行复用 — **D145 比 D143 略重双类型反推 + callee 类型分叉判定**)。下分三路径定 D145 实施。

| 路径 | 描述 | 解决度 | LOC | 影响 | 决策 |
|------|------|--------|-----|------|------|
| **G1** | **D141/D142/D143/D144 G1 同模式复刻** — checker `check_exprs.ss:OBJ_LITERAL case` 加 callee 类型分叉判定(`Map<K,V>` 反推 K + V;`class<X>` 走 D143 既有 className 反推) + codegen 阶段反推回填 OBJ_LITERAL keyType + valueType slot + eval pre-eval 反推前移(三处 outer call site 通用 pre-eval `genVal(argId)` 之前)+ funcParamTypes 已结构化直接消费(无 callee 升级前置) + helper `isMapType` / `extractMapKVTypes` / `inferMapLiteralKVTypes`(对偶 D141 isFnType + D142 isArrayType + D143 isClassType + D144 isNullableType) + **D052 ss_mapNew + ss_mapSet 路径复用**(反推得 callee `Map<K,V>` 后 codegen emit ss_mapNew + ss_mapSet * N 链复用 D052) + **D143 OBJ_LITERAL className 反推路径并行不破** | 100% | check_exprs.ss callee 类型分叉判定 ~15 + gen_types.ss helper ~40 + gen_calls.ss + gen_methods.ss 反推 ~30 + eval/method_call.ss + eval/call.ss + eval/new_expr.ss pre-eval 反推 ~30 + check_types.ss isTypeCompatible 调整 ~10 + codegen Map literal emit 路径 ~15 ≈ **~140** | Phase 4 临时变量绑定 + .set 链 cleanup 仍可推进(callee 已结构化与 Map literal cleanup 独立)| **选** — D141/D142/D143/D144 G1 同模式复刻 + 比 D143 略重双类型反推 + callee 类型分叉判定 + 比 D141 更轻(无 parser 扩 + 无 callee 升级前置 + D052 ss_mapNew 复用 + D143 path 并行 — H11/H12 比 D141 弱 / 与 D142/D143/D144 同位)|
| G2 | callsite 双向反推 — 从 OBJ_LITERAL 第一字段类型反推 keyType + valueType;不依赖 callee `Map<K,V>` 形态 | 30% | gen_calls.ss + gen_methods.ss ≈80 | 漏 Map<string,V?> nullable values(null 字段 inferType 不出 V?)+ 漏 Map<K,Array<V>> 嵌套泛型(嵌套字段类型推断不准)+ 漏 fn binding 间接链 — **OBJ_LITERAL 字段反推 keyType/valueType 不可行**(K/V 是上下文反推关键,非字段自身 inferType — null 分支无法反推 V?)| 不选 — 不可行 + 偏离 TS / Java 主线(TS Record literal 反推靠 callee 形参类型,不靠字段自身 inferType)|
| G3 | 接受 gap,Phase 2 仅做 (a) 预备 — check_exprs.ss OBJ_LITERAL case 加 callee 类型分叉判定 stub,(b)(c) 反推机制因消费链路不接通实际不生效;主线 D142 §F5 / D143 §F2 / D144 §F1 cleanup 延期 | 0% | check_exprs.ss OBJ_LITERAL case 单点 ≈10 | 主线 cleanup 延期;反推机制空转;违反 `feedback_root_cause_no_cost.md` 红线 | 不选 — 反推机制空转无意义 |

**G1 决策(本 Phase 0 落档锁定,待用户对话确认)**:走 G1 — 根因 100% + D141/D142/D143/D144 G1 同模式复刻 + scope 可控 ~140 LOC + 比 D141 更轻(无 parser 扩 + 无 callee 升级前置 + D052 ss_mapNew 复用 + D143 path 并行 — H11/H12 比 D141 弱 / 与 D142/D143/D144 同位)。**为何不选 G2**:OBJ_LITERAL 字段反推 keyType/valueType 物理不可行(K/V 是上下文反推关键,非字段自身 inferType — null 字段无法反推 V?,嵌套字段无法反推嵌套泛型);且偏离 TS / Java contextual typing 主线。**为何不选 G3**:反推机制空转 0% 解决度,违反 `feedback_root_cause_no_cost.md` 红线。

---

## A.2 隐藏假设挑战(Plan 型 §④ 替换配套 — D141 §A.2 + D142 §A.2 + D143 §A.2 + D144 §A.2 同模式扩)

| # | 假设 | 风险 | 验证手段 | 失败回路 |
|---|---|---|---|---|
| H1 | funcParamTypes Map<K,V> / 结构化字符串在 codegen 阶段已 ready(D141/D142/D143/D144 H1 同模式 — checker 阶段用户函数为空,codegen registerAllDecls 后满载)| 实施层失败 — codegen 反推时 funcParamTypes 留空,反推查不到 callee 期望 keyType + valueType | Phase 1 探查 codegen.ss:110-112 + gen_registry.ss:56-57 register 时机;Phase 2 startup 阶段 dump funcParamTypes 验证含 `Map<K,V>` / `Map<string,Array<int>>` 等结构化形态;**D141/D142/D143/D144 H1 已实证 codegen 阶段已就绪**,D145 同模式假设大概率成立 | funcParamTypes 时机不就 → 调整 Phase 2 入口(改 lazy 反推 vs eager 反推)|
| H2 | OBJ_LITERAL Map literal K/V 类型与 callee `Map<K,V>` 一致性 widen | `{ "key": "value" }` 反推得 callee `Map<string,string>` 后 K/V 字段按 string widen;若字段类型与 callee 类型冲突(`{ "key": 1 }` 期望 `Map<string,string>`)→ widen 失败硬错 | Phase 3 测试 `tests/d145_map_literal_inference/k_v_widen.ss` + `mismatch_硬错.ss` | 类型不一致 silent fallback → 回 Phase 2 修硬错路径;参 D141 H4 + D142 H2 + D143 H4 + D144 H2 fallback 编译期硬错粒度 |
| H3 | 嵌套 Map `{ "k": { "inner_k": "inner_v" } }` 反推 capture 链 | 内层 OBJ_LITERAL 字段也是 OBJ_LITERAL,反推外层 callee = `Map<string,Map<string,string>>` 后,内层也需反推 callee = `Map<string,string>` — 递归回填 | Phase 3 测试 `tests/d145_map_literal_inference/nested.ss` | 嵌套反推失败 → 内层反推 fallback 单层 + 用户嵌套时仍需显式 new Map();参 D141 H3 + D142 H3 + D143 H3 + D144 H3 嵌套范式 |
| H4 | Map<K,Array<V>> 嵌套泛型反推 — 与 D142 ARRAY_LIT 反推合作 | `{ "k": [1, 2, 3] }` callee `Map<string,Array<int>>` 反推 K=string + V=`Array<int>` + 内层 ARRAY_LIT [1, 2, 3] 反推 elemType=int — D142 + D145 反推链合作 | Phase 1 grep + Phase 2 helper extractMapKVTypes 解析 V 后若 startsWith("Array<") 触发 D142 inferArrayLitElems 链路;Phase 3 测试 `tests/d145_map_literal_inference/map_array_value.ss` | 嵌套泛型反推断 → 回 Phase 2 修 helper extractMapKVTypes 递归解析 |
| H5 | Map<K,User> 类型化 value 反推 — 与 D143 OBJ_LITERAL 反推合作 + D025 vtable | `{ "k": new User("X", 18) }` callee `Map<string,User>` 反推 V=User + class 实例 value 走 D025 vtable | Phase 3 测试 `tests/d145_map_literal_inference/map_class_value.ss` | class 实例 value 反推断 → Phase 2 修 helper 递归 + Phase 3 vtable test;参 D141 H5 + D142 H5 + D143 H5b + D144 H5 同模式 |
| H6 | Map<K,V?> nullable values 反推 — 与 D067 / D144 nullable 合作 | `{ "k": null }` callee `Map<string,User?>` 反推 V=`User?` + null literal 类型化为 nullable User — D067 nullable + D144 ternary 同形 | Phase 1 grep D067 null literal + Phase 2 反推前移到 D067 调用前 + Phase 3 nullable values test | D067/D144 链路断 → 回 Phase 2 修反推前移路径,reuse D067 helper 不重写 |
| H7 | 显式注解优先级 > 推断 | 用户写 `let m = new Map<string,string>(); m.set("k","v"); takesFn(m)` 时,m 是 IDENT 不是 OBJ_LITERAL,反推 skip;D052 ss_mapNew + ss_mapSet 既有路径不破 | Phase 2 反推条件判断 `if (nGetKind(argId) == "OBJ_LITERAL")` 限定 + callee 类型分叉判定;Phase 3 测试 `tests/d145_map_literal_inference/explicit_override.ss` 显式 new Map() 仍走原路径;参 D141 H6 + D142 H6 + D143 H6 + D144 H6 显式优先粒度 | 显式优先级失败 → 回 Phase 2 修条件判断 |
| H8 | tests/ 284/4/288 baseline 不降 + D143 path 不回归 | 全项目现有 OBJ_LITERAL 测试都走 D143 className 反推 — Phase 2 callee 类型分叉判定不影响 D143 path(callee 仍是 class<X> 走原路径);Phase 4 cleanup 仅 Map literal 临时变量 + .set 链形态 | Phase 2 后跑 `bin/ss test tests/d143_object_literal_inference/` 6/0/6 + `bin/ss test tests/` 全跑 + baseline 比 | tests/ 红 / D143 path 回归 → 回 Phase 2 修 callee 类型分叉判定边界;参 D141 H7 + D142 H7 + D143 H7 + D144 H7 同范式 |
| H9 | reflection_health_linter GATE 不破 | checker / codegen / eval 三层改 — 是否破反射路径 14 指标(M1-M7b + N1-N5)| Phase 2 后跑 `bin/ss run tools/reflection_health_linter.ss` GATE PASS | GATE BLOCK → 走 §MNK §反射路径根因 gate B 路径(扩容申报 + 升 baseline + D 文档 §扩容申报段);参 D141 §扩容申报-Phase2-G1 + D142/D143/D144 §扩容申报-Phase2 范式 |
| H10 | OBJ_LITERAL eval pre-eval 时序(D143/D144 H10 同模式 + cross-D 反思继承)| 待 Phase 1 实测确认 evalObjLiteral 路径 + pre-eval 缓存与 codegen emit 之前的时序;**D143 H10 cross-D 教训 + D144 H10 PASS 实证**:不能仅 grep 字面 handler `evalObjLiteral`,outer call site 通用 pre-eval `genVal(argId)` 才是反推时序关键(memory `feedback_h10_cross_d_verify.md`)— 反推必须前移到 outer call site `eval/method_call.ss + eval/call.ss + eval/new_expr.ss` args 循环 | Phase 1 探查 outer call site 通用 pre-eval `genVal(argId)` 路径 + Phase 2 反推前移到三处 outer call site 识别 OBJ_LITERAL 子节点 + 查 funcParamTypes + 反推回填 | 修复链断 → 回 Phase 2 检查 nSetS?/nGetS? 命名一致 + outer call site args 循环识别 OBJ_LITERAL 完整路径 |
| H11 | callee PARAM `Map<K,V>` / 结构化字符串已就绪,无需 G1 callee 升级(比 D141 H11 弱,与 D142/D143/D144 H11 同位)| D141 G1 必须先升级 lib/spring/(jdbc+data).ss 7 处 `setter: fn`(parser.ss:803 parseTypeAnn 扩 fn 类型 annotation 解析);D142 callee `Array<T>` 已结构化无前置;D143 callee `class X` 已结构化无前置;D144 callee `T?` 已 D067 落地;D145 callee `Map<K,V>` 已 D052 落地结构化 | grep 实测 lib/ + tests/ 多处 callee PARAM `Map<K,V>` 已结构化;Phase 2 反推 helper `isMapType("Map<string,string>")` = true / `extractMapKVTypes("Map<K,V>")` = (K, V) 直接消费 | callee 升级路径破裂 → 反推失败 silent skip(非结构化 callee 走 H13 同形 skip 不破);参 D141 H13 + D142 H13 + D143 H13 + D144 H13 粒度 |
| H12 | parser 不需要扩(比 D141 H12 弱,与 D142/D143/D144 H12 同位都弱)| D141 H12 必须 parseTypeAnn IDENT "fn" + LPAREN 分支扩;D142 嵌套 generic Array<...> 已就绪;D143 class 名 IDENT 单 token 已就绪;D144 `T?` 后缀已 D067 落地解析;D145 `Map<K,V>` 嵌套泛型已 D052 落地解析 | Phase 1 grep 实测 + Phase 2 不动 parser | parser 未就绪(若实测发现某些边界形态未支持)→ 回 Phase 2 评估扩 parser 必要 — 大概率不需要 |
| H13 | 反推失败硬错粒度(D141/D142/D143/D144 H13 同模式)— 结构化 callee 硬错 / 非结构化 callee skip | **结构化 callee**(funcParamTypes 含 `Map<K,V>` / `class X` / `Array<T>` / `T?`):helper extractMapKVTypes 取不到 → `codegenError` 硬错;**非结构化 callee**(funcParamTypes 仍是 ""/单 IDENT 非 Map<K,V>)→ 反推 skip(不破现有调用方);**字段类型与 callee K/V 不一致 mismatch**:参 H2 决策(严格 vs widen)| Phase 2.2 实测 helper extractMapKVTypes + Phase 4 cleanup 删 typed 注解后,untyped Map literal 走结构化反推 | 硬错粒度过严 → tests/ break → 调整粒度为 silent skip + warn(参 D141 H13 + D142 H13 + D143 H13 + D144 H13 调整路径)|

---

## A.3 废案

- **C1 数据层 patch 全废**(零散 fallback,不消除根因 — 与 D141 §A.3 + D142 §A.3 + D143 §A.3 + D144 §A.3 同形)
- **C3 架构层 refactor 全废**(scope 爆炸,远超 D145 单 sub-D)— **D141 §Followup F5 + D142 §A.3 + D143 §A.3 + D144 §A.3 已锁此候选废留 SS 类型系统 v2 评估**
- **C4 编译期 lint 警告强制用户加 new Map() + .set 链**(被动 — 用户每写 Map literal 必先 new + .set,违反 CLAUDE.md §编译器吸收复杂度)
- **C5 全 OBJ_LITERAL 默认 Map 路径**(silent miscompile + 破 D143 className 反推 — class 实例 / 嵌套 / interface upcast 全场景错位)
- **G2 callsite 双向反推全废**(物理不可行 — null 字段反推不出 V?,嵌套字段反推不出嵌套泛型,K/V 是上下文反推关键 — §A.1.1 G2 行)
- **G3 接受 gap 全废**(反推机制空转 0% 解决度,违反 `feedback_root_cause_no_cost.md` 红线)

---

## Phase 收关锚

### Phase 0: D 文档落档 [✓] Done at commit `d2fb4e1` (2026-04-28)

- 本文档落档 + Status / 核心目标 / 核心原则 / Context / Tools / Orchestration / State / Evaluation / Constraints / §A.1 主候选 + §A.1.1 实施路径 + §A.2 隐藏假设 / §A.3 废案 / Phase 0-5 计划草案
- d_doc_index_linter F1 = 0 验证 PASS(D145 加入未破 referenced Ds — D025/D052/D067/D131/D141/D142/D143/D144 实存,F2 soft warn 含 D145 不阻 commit)
- next_prompt_ultrathink_linter PASS 3/3(本轮 .claude/next_prompt.md 含 ultrathink 关键字)
- VCM 六验(Plan 型):§① 跳过(diff=0 in bootstrap/lib/tools)+ §④ 替换为「替代方案对比 + 隐藏假设挑战」§A.1+§A.1.1+§A.2 ✓

### Phase 1: RED 复现 + 信息源探查 [✓] Done at commit `<placeholder>` (2026-04-28)

**Phase 1 收关锚 — 关键事实落档**:

**RED 铁证(IDENT key 形态 spike `/tmp/spike_map_lit_red.ss` 形态 1+2+7)**:
- `bin/ss build /tmp/spike_map_lit_red.ss` → `[genVal] unknown kind: OBJ_LITERAL` codegen 阶段 dispatcher 不识别(D143 反推后 rewrite NEW_EXPR 才有 emit;Map<K,V> callee 反推不到 className → kind 保留 OBJ_LITERAL → genVal 报 unknown);LLC error `integer constant must have integer type` → IR 现场 `%5 = call ptr @takesMap1(ptr 0)` 形态 1 silent miscompile 占位
- 形态 7 显式 baseline `let m = new Map<string,string>(); m.set(...); takesMap7(m)` 编译通过(D052 既有路径不破)— 反推 skip + IDENT 实参 baseline 验证

**§A.2 H1 funcParamTypes Map<K,V> 时序 PASS 实证**:
- `bootstrap/gen/codegen.ss:110-112` 普通函数 `funcParamTypes.set(\`${fname}:${pCount}\`, nGetS2(fpId))`(原始 SS 类型字符串包括 `Map<K,V>` / `Map<int,Array<int>>` 嵌套泛型)
- `bootstrap/gen/gen_registry.ss:56-57` class method 对称注册
- `bootstrap/gen/codegen.ss:326` `registerAllDecls(rootId)` 在 line 327 `emitGlobalsAndCode(rootId)` 之前
- 嵌套泛型实测(`takesMap2(m: Map<int,Array<int>>)` /tmp/dump_funcparamtypes.ss)build PASS,字符串原样注册

**§A.2 H10 cross-D 反思 eval pre-eval 时序 PASS**:
- `bootstrap/eval/call.ss:36-37`(D143 落锚)
- `bootstrap/eval/method_call.ss:64`(D143 落锚)
- `bootstrap/eval/new_expr.ss:24-25 + line 40`(D143 NAMED_ARG OBJ_LITERAL 嵌套反推已落)
- 三处 outer call site 已是 D143 反推前移点 — D145 Phase 2 加第 5 行 `inferMapLiteralKVTypes(argId, callee, idx)`

**OBJ_LITERAL 节点 slot 占用探查 PASS**:
- `bootstrap/parse/parse_exprs.ss:521-522` `newNode("OBJ_LITERAL") + nSetList(id, fields)` 仅 nList 占
- **D143 已用 nSetS2 存 className**(`bootstrap/gen/gen_types.ss:891-905` `inferObjLiteralFromType` 注释证实:三步原子 rewrite (1) `nSetS2(argId, className)` (2) `nKind.set(argId+"", "NEW_EXPR")` (3) `nSetS1(argId, className)`)
- s1/s3 + i1-i4 全空闲 — D145 Phase 2 选 **nSetS3 存 valueType**(D143 nSetS2 共用语义混淆,选独立 slot;K 复用 NAMED_ARG fields 字符串 IDENT 直接 inferType,不再加单独 keyType slot — Phase 2 决策 B 简化)

**OBJ_LITERAL kind dispatch site 全 grep — 11 文件 33 行**:
- `bootstrap/parse/parse_exprs.ss`(parser line 501-523)
- `bootstrap/checker/check_exprs.ss`(line 285 case)+ `check_stmts.ss` + `check_types.ss:72`(inferType case)
- `bootstrap/eval/call.ss:36` + `eval/method_call.ss:64` + `eval/new_expr.ss:24+40`(三处 pre-eval)
- `bootstrap/gen/gen_calls.ss` + `gen/gen_decls.ss` + `gen/gen_types.ss:565+891-917`(D143 反推 helper)+ `gen/class/class_method.ss`

**D052 实际入口名修正(Phase 0 文档错估)**:
- `bootstrap/gen/class/class.ss:251` `emitIR(\`  ${r} = call ptr @ss_mapNew()\`)` — D052 `new Map()` ctor 入口
- `bootstrap/gen/rt/gen_rt_map.ss:70` `define ptr @ss_mapNew()` 定义入口
- `bootstrap/gen/rt/gen_rt_map.ss:77` `define void @ss_mapSet(ptr %map, ptr %key, i64 %val)` — **第三参 i64 不是 ptr**(string ptr 需 ptrtoint cast,int 需 zext / sext,object ptr 需 ptrtoint)
- `bootstrap/gen/gen_builtins.ss:235-246` `m.set(k, v)` emit 路径含完整 i64 cast 逻辑 — D145 Phase 2 emit ss_mapSet 直接复用此 cast 模式

**§A.2 H12 parser 不需要扩 — Phase 0 错估,Phase 1 实测发现**:
- `bootstrap/parse/parse_exprs.ss:508` `pExpectIdent()` 强制 OBJ_LITERAL key 必须是 IDENT
- STRING key (`{ "key": "value" }`) 当前直接 parse error(line 46:43 `expected identifier, found STRING`)
- **影响**:D145 主战场 Map literal `{ "k1": "v1" }` 当前语法不支持 — 限定 IDENT key 时 Map<int,V> / Map<string-with-special-char,V>(`Content-Type`)写不出来
- **Phase 2 决策行**:
  - **决策 D**(选)**Phase 2 仅 IDENT key Map literal 反推 — 主战场 `Map<string,V>` IDENT key 形态先落地;STRING key + INT key 留 §Followup F7 sub-D**(parser 扩 + 多 dispatch site 同步)— 与 Phase 0 §核心原则 7 "callee `Map<K,V>` 已结构化无需 G1 callee 升级"一致,IDENT key Map<string,V> 已是大头业务覆盖
  - 决策 E(废)Phase 2 同时扩 parser STRING key — scope 扩张,违反 D145 单 sub-D 范围

**Phase 2 入口锁修正(Phase 1 探查后精确化)**:
- `bootstrap/checker/check_exprs.ss:285` 改加 callee 类型分叉判定(已是 D143 untyped 放行点)
- `bootstrap/checker/check_types.ss:72` OBJ_LITERAL inferType case 优先读 nGetS2 + nGetS3 fallback `Map<K,V>` 复合 string fallback "auto"
- `bootstrap/gen/gen_types.ss:565-572` codegen inferType OBJ_LITERAL 优先读 nGetS2 fallback "ptr" — Phase 2 加 Map<K,V> 路径
- `bootstrap/gen/gen_types.ss` 加 helper 3:`isMapType` / `extractMapKVTypes` / `inferMapLiteralKVTypes`(对偶 D143 line 880-917)
- `bootstrap/gen/gen_calls.ss:284`(D143 落点)+ `bootstrap/gen/methods/gen_methods.ss:206`(D143 落点)args 循环加 `inferMapLiteralKVTypes`(D141/D142/D143/D144 G1 4 落点同位扩)
- `bootstrap/eval/method_call.ss:64`+ `eval/call.ss:36` + `eval/new_expr.ss:24+40` 追加第 5 行 `inferMapLiteralKVTypes`
- **codegen Map literal emit 路径**(新增 — Phase 2 实施重点):反推得 callee `Map<K,V>` 后 OBJ_LITERAL kind rewrite 为 "MAP_LIT"(新 kind 节点)+ codegen genMapLit case emit `call ptr @ss_mapNew()` + `for field: call void @ss_mapSet(ptr %m, ptr %k, i64 %v)`(value i64 cast 复用 gen_builtins.ss:235-246)— 11 处 OBJ_LITERAL dispatch site 加 MAP_LIT 同步 case
- **不扩 parser**(STRING/INT key 留 §Followup)

**VCM 六验**(本轮 docs-only — Phase 1 主战场是 D 文档落档 + spike 文件 + commit hash 回填,§1 豁免成立):
- `git diff --stat HEAD -- bootstrap/ lib/ tools/` 空输出 → §1 豁免锚成立
- `bin/ss test tests/d144_ternary_inference/` baseline 不破
- `bin/ss test tests/d143_object_literal_inference/` baseline 不破
- `bin/ss test tests/d142_array_literal_inference/` baseline 不破
- `bin/ss test tests/d141_lambda_inference/` baseline 不破
- `bin/ss run tools/reflection_health_linter.ss` GATE PASS no regressions
- `bin/ss run tools/d_doc_index_linter.ss` PASS

### Phase 2: codegen 阶段反推实施 + G1 路径 [ ] 待 Phase 2 commit

### Phase 3: 测试覆盖 + 隐藏假设挑战 [ ] 待 Phase 3 commit

### Phase 4: workaround cleanup [ ] 待 Phase 4 commit

### Phase 5: 全 Phase 收关 [ ] 待 Phase 5 commit

---

## Followup

| # | 锚 | 描述 |
|---|---|---|
| F1 | Tuple literal contextual typing | tuple literal 在 fn 实参 `Tuple<int,string>` 反推 — D142 §Followup F6 + D143 §Followup F3 + D144 §Followup F2 同位 sub-D |
| F2 | NEW_EXPR ctor 实参子节点反推 | `new Profile({ user: {...}, addr: [...] }, (x > 0) ? null : 5, { "k": "v" })` ctor args 中 OBJ_LITERAL/ARRAY_LIT/TERNARY/Map literal 反推 — D142 §Followup F7 + D143 §Followup F4 + D144 §Followup F3 同根因合并 sub-D |
| F3 | partial fields + ctor 默认值 | object literal / Map literal 部分字段 + class ctor 漏字段默认值机制 — D143 §Followup F6 + D144 §Followup F4 同位 |
| F4 | spread `{...base, name: "X"}` 反推 | spread 子节点反推 + 字段覆盖 — array literal SPREAD + object literal SPREAD + Map literal SPREAD 同模式 sub-D(D143 §Followup F7 + D144 §Followup F5 同位)|
| F5 | 反推失败粒度细化 | 倒置类型 silent miscompile / 无 callee context unknown kind LLC error 等粒度细化 — D143 §Followup F8 + D144 §Followup F6 H4+H13 同形(本 D §A.2 H2 mismatch 同位风险)|
| F6 | bidirectional type checking 全局 | C3 候选废案,留作未来 SS 类型系统 v2(memory feedback_d026_d027_phantom_anchor,D141 §Followup F5 + D142 §A.3 + D143 §A.3 + D144 §Followup F7 同位)|

---

## Status 时间线

- 2026-04-28 Phase 0 D 文档落档(commit `d2fb4e1`)— D142 §Followup F5 + D143 §Followup F2 + D144 §Followup F1 Map literal contextual typing 候选入口落档(同位三合 sub-D 起首落档);C2 接口层 trap + G1 D141/D142/D143/D144 同模式复刻路径决策(待 Phase 1 用户对话锁定方向后启动实施);§A.1 三主候选 + §A.1.1 三实施路径 + §A.2 H1-H13 隐藏假设挑战(H10 cross-D 反思继承 D143/D144 教训)+ §A.3 废案 + Phase 0-5 计划草案 + Followup F1-F6(D141/D142/D143/D144 §Followup 合并队列重排);D135/D136/D137/D140/D141/D142/D143/D144 范式延续(每 Phase 独立 commit 大改档 + Status 收关 + commit hash 回填 + next_prompt 自闭环 — D144 Phase 0 commit `02415c9` 同模式)
- 2026-04-28 Phase 1 RED 复现 + 信息源探查(commit `<placeholder>`)— `/tmp/spike_map_lit_red.ss` 形态 1+2+7 RED 铁证(`[genVal] unknown kind: OBJ_LITERAL` + LLC error `integer constant must have integer type` + IR 现场 `%5 = call ptr @takesMap1(ptr 0)` silent miscompile;形态 7 显式 baseline GREEN)+ §A.2 H1 funcParamTypes Map<K,V> 时序 PASS(codegen.ss:110-112 + gen_registry.ss:56-57 + codegen.ss:326 嵌套泛型字符串原样注册)+ §A.2 H10 cross-D eval pre-eval PASS(eval/call.ss:36 + method_call.ss:64 + new_expr.ss:24+40 三处 D143 落锚 — D145 加第 5 行)+ OBJ_LITERAL 节点 slot 探查 PASS(D143 nSetS2 className 锁,D145 选 nSetS3 valueType 独立 slot 防语义混淆;K 复用 NAMED_ARG fields IDENT)+ 11 文件 33 行 OBJ_LITERAL dispatch site 全 grep + D052 入口名修正(ss_newMap → ss_mapNew,class.ss:251 + gen_rt_map.ss:70;ss_mapSet 第三参 i64 cast 复用 gen_builtins.ss:235-246)+ §A.2 H12 parser 不扩错估(parse_exprs.ss:508 pExpectIdent 限定 IDENT key,STRING key parse error)+ Phase 2 决策 D(IDENT key Map<string,V> 主战场先落地,STRING/INT key 留 §Followup)+ Phase 2 入口锁修正(MAP_LIT 新 kind rewrite + 11 dispatch site 加 case + ss_mapSet i64 cast 复用)— D135/D136/D137/D140/D141/D142/D143/D144 范式延续(D144 Phase 1 commit `17a1573` 同模式)
