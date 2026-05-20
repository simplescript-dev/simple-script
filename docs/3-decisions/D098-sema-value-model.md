# D098: SEMA Value Model — MaybeVal 编码 / InternPool / Type-as-Value 统一

**Status:** Proposed
**Depends on:** D088(Zig 路线) / D093(SEMA 单 dispatch,本文承接 §张力 1-3) / D094(comptime purity,§决策 §规则 1-3 保留有效)
**Date:** 2026-04-18
**Last Updated:** 2026-04-18

---

## 第一性需求

D093 §决策 evalExpr 单函数 dispatch 要求:任一 AST 节点走同一求值入口返回 `MaybeVal{known, val}`。**但 `val` 的编码语义未定 —— 三个互相耦合的子决策缺失**:

1. **MaybeVal 编码**(D093 §张力 1):SS 无 nullable,`{known:bool, val:int}` 的 `known=false` 时 `val` 语义(LLVM 寄存器引用占位 / 哨兵值 / 未设)
2. **InternPool 引入**(D093 §张力 2):相同常量是否共享 id(Zig `Value.eql` 是 O(1) index 比较)
3. **Type-as-Value 编码**(D093 §张力 3):当前 `ctVal(id) = id | 1073741824` 只有一个 tag 位,扩展到 int/string/Type/class instance 需重新设计 payload

三者必须集中决策 —— MaybeVal.val 编码选 tagged int vs pool index,InternPool 是否做,Type 句柄是否复用同一编码空间 —— 任一单独决定都会把剩两个锁死。D094 §Supersession §Supersession 关系 第 4 条已将此委托明文交给本 D 文档。

## 背景:Zig 原语对齐(不变量)

D093 §决策 §Zig 原理 已固化四条原语,本文以此为**不变量**,不创造 Zig 原理不支持的形态:

1. **`?Value` 二元返回**(D093 行 35):有值 → 编译期已知 → `genConst`;null → 发射 AIR runtime 指令。同一 `?Value` 语义覆盖 binop/call/member/index/cast/branch 全部表达式类型,没有任何 `if comptime then A else B` 分岔
2. **Value 是无类型的**(D093 行 36):`Value.zig` 里 Value 只存"这是什么值"(tag + payload),不存"这是什么类型"。类型信息独立通道
3. **Type 本身是一个 Value**(D093 行 37):`Value.Tag.ty` —— 类型是一等公民,和 int/string 共享同一 Value 容器
4. **InternPool 统一去重**(D093 行 38):相同值/类型共享 pool index,`Value.eql` = O(1) index 比较

本文三子决策各自对应 §张力 1-3 并保持这四条原语一致。

## 决策

### §决策 1 — MaybeVal 编码

**概念容器**:`MaybeVal { known: bool, val: int }` — 有无值 + 值句柄二元。**接口**恒定,**物理编码**随 Phase 演进。

**语义**(Phase 无关):
- `known=true`:`val` 是 **Value 句柄**(Phase A = `ctVal(id)` tagged int,Phase B = InternPool index)
- `known=false, val>=0`:`val` 是 **regTable 1-based 索引**(`regTable: Array<string>` 存 LLVM 寄存器字符串,`reg(mv) = regTable[val-1]`)
- `known=false, val=-1`:错误哨兵(`mvError()` 构造,调用方禁止 `reg()`)

**Phase A 物理编码:纯 int 符号位辨识**(2026-04-18 实测 bootstrap linter baseline 约束,**不是** class field)。

理由:
- SS 无 nullable;`{known:bool, val:int}` class 实现会引入 `TRUE_LIT/FALSE_LIT/MEMBER_ACCESS` 三个 bootstrap 其他文件**从未使用过**的 AST kind(bootstrap 风格是全局 Map + int 键,无裸 bool 字面量、无字段直读),触 linter N1 = +3 regression 违反 `CLAUDE.md §反射根因 gate`
- 而 D098 §决策 2 Phase A 已定"沿用 `ctVal(id) = id | 1073741824` tagged int 编码 value 句柄",MaybeVal 用**同一 int 空间**自然契合 — Zig `?Value` 的 optional discriminant 可由 int 符号位承载
- 不扩新 tag 位(避 §Rejected Alternatives C),用 int 正负符号作 known 区分

**编码方案**:
```
mv >= 0               → known=true,  val = mv             (Value 句柄,通常已是 ctVal tagged int)
mv <= -2              → known=false, regId = -mv - 1      (regTable 1-based 索引,可直接 reg 出字符串)
mv == -1              → error 哨兵,禁止 reg()
```

**构造入口**:

```ss
function mvKnown(valId: int): int { return valId }           // valId 必 >= 0(Phase A: ctVal tagged int 本就非负)
function mvRuntime(regId: int): int { return 0 - regId - 1 } // regId 1-based → mv <= -2
function mvError(): int { return 0 - 1 }                      // -1 哨兵
```

**访问器**(命名与构造器错开避 SS 函数重载 int 同名 dispatch 缺口,见 §新张力 6):

```ss
function mvKnownOf(mv: int): int { if (mv >= 0) { return 1 } return 0 }
function mvValOf(mv: int): int {
    if (mv >= 0) { return mv }              // known=true:Value 句柄
    if (mv == 0 - 1) { return 0 - 1 }       // error:返回 -1 哨兵
    return 0 - mv - 1                        // runtime:decode regId
}
```

**注**:`mvKnownOf` 返回 `int`(1/0)而非 `bool`,避 bootstrap 外引入 bool 字面量风格(与 bootstrap `if (xxx == 1)` 规约一致)。`- n` 裸负号未用,改为 `0 - n` 形式(probe 显示 bootstrap 裸负号使用有限,保守写法避 UNARY 节点膨胀,但 bootstrap 既有 UNARY kind,此项为样式对齐,不是硬约束)。

**接入 evalExpr**(D093 §SS 本质一样骨架 行 52-59 直译):

```ss
function evalExpr(astId: int): int {
    // 每 kind:
    //   递归 evalExpr 所有子节点 → 得到子 mv 列表
    //   全部 mvKnownOf(sub)==1 → 调对应 interp* 常量计算 → mvKnown(valId)
    //   否则 → emitRuntimeSubExprs(先 emit 未 known 子表达式) → mvRuntime(regId)
    //   错误路径 → mvError()
    // 无 "if comptimeDepth > 0" 分岔
}

function genExpr(astId: int): string {
    const mv = evalExpr(astId)
    if (mvKnownOf(mv) == 1) { return emitConstFromVal(mvValOf(mv)) }
    if (comptimeMustBeKnown == 1) { return comptimeError("comptime block contains runtime-only expression", astId) }
    return regTable[mvValOf(mv) - 1]
}
```

**Phase B 物理编码**(InternPool 引入期):
- `mv` 空间拆分保持 Phase A 符号位约定:`mv >= 0` 直接作 pool index,`mv <= -2` 仍作 regTable 索引,`mv == -1` error
- 即 Phase A → B **接口完全不变**,内部把 "mv 是 ctVal tagged int" 改为 "mv 是 pool index" — evalExpr 代码透明
- 由访问器 `valOf(valId)` / `valType(valId)` 承担 "pool 查表 vs tagged int 解码" 的内部差异,调用方不感知

**保留的 class 视图**(仅作文档 / 测试):2026-04-18 probe `/tmp/maybeval_probe.ss` 已验证 `class MaybeVal { known: bool; val: int }` 可跑通,为未来若取消 linter N1 约束时的后备形态。Phase A **实现用纯 int**,class 视图本 D 文档不落地到 bootstrap。

**SS 语言约束**(探 probe 结论):
- class 带字段 → SS 自动按字段顺序生成构造器,`new Cls()` 无参非法(本 Phase A 不用 class,此约束仅记录)
- 函数重载按参数类型 dispatch 对 int vs ptr 同名失效(见 §新张力 6),命名错开 `mvKnown/mvKnownOf` 等即可

**valOf / valType 访问器**(Value payload 提取):
```ss
function valOf(valId: int): int { ... }        // Phase A: payload(valId);Phase B: pool.load(valId).payload
function valType(valId: int): string { ... }   // Phase A: interpType(valId);Phase B: pool.load(valId).tag
```

### §决策 2 — InternPool 模型(渐进 Phase A → Phase B → (可选) Phase C)

**不一次全做。evalExpr 骨架先跑通,InternPool 后引入。**

**Phase A(evalExpr 首批 1a~中批 3 合并期)** — 不引 InternPool:
- 沿用 `ctVal(id) = id | 1073741824` tagged int,MaybeVal.val 直接是 tagged int
- `Value.eql` 退化为深比较(走 `interpAsInt` / `interpAsStr` / `interpCompoundOp` 等值函数)
- 收益:evalExpr 骨架 + 首批 kind 合并 LOC 最小,不做 hash/equal 定制

**Phase B(后批合并期,Meta 对象 / 反射迁移后)** — 引入 InternPool:
- `internPool: Map<string, int>`,key = `tag + "|" + payload_serialization`(如 `INT|42` / `STR|<sha256(s)>` / `TY|<className>`)
- `ctVal` 构造改走 `internPoolGetOrInsert(key)` 返回稳定 int
- MaybeVal.val 类型不变(`int`),**语义从 tagged int 变为 pool index** —— 对 evalExpr 代码 transparent
- `interp*` 家族调用点需要过 `valOf(valId)` 访问器屏蔽差异(Phase A 就应引入访问器作为接口边界,免 Phase B 大改)
- 收益:`Value.eql` = O(1) index 比较,支持 Zig 路线最终形态

**Phase C(可选,evalExpr 全合并后评估)**:
- 把 `interp*` 家族(codegen.ss L277-500 约 30 函数)内部的 value 表示也迁到 InternPool,彻底消除 tagged int 空间
- 前提:Phase B 后 hash 冲突率可控 + 深比较已成瓶颈
- 否则停在 Phase B(InternPool 只管相等性,不管 value 存储)

**Map hash/equal 定制**:
- Phase A **不需要**(MaybeVal.val 就是 tagged int,相等是原生 int ==)
- Phase B:key 字符串序列化已是 SS Map 原生能力,无需定制 hash;值相等由 pool index 保证
- Phase C:若走结构化比较而非序列化 key,需定制 Map,**本 D 文档不预判**

### §决策 3 — Type-as-Value 语义

**目标**:Type 句柄和 int/string/class instance 共享 MaybeVal.val 编码空间(Zig `Value.Tag.ty` 语义)。

**当前事实**:D088 Phase 4 "类型作为 comptime 值" 已落地(`bootstrap/codegen.ss:83` `comptimeTypeAliases` + `bootstrap/codegen.ss:305` `interpNewType(className): int`),实现用独立 Map + tagged int 返回,**是独立通道**(type alias 查表单独走 `comptimeTypeAliases`,不和普通 ctVars 统一)。

**决策**:

**Phase A(evalExpr 骨架期)** 保留现状 + 消除独立通道:**[x] Done at D112 §步骤 1(2026-04-20)**
- `interpNewType(className)` 继续发 tagged int,Type 是 ctVal 空间里的一个 tag(由 `interpType(id) == "type"` 识别)
- **消除 `comptimeTypeAliases` 作为独立查表机制**:`const T = comptime{...}` 产生的 Type alias 改走普通 `ctVars` 路径 —— ctVars 里存的 MaybeVal.val = `interpNewType(actualClassName)`。`gen_exprs.ss:158-163` 的 "genVal IDENT comptime 查 interpClasses + comptimeTypeAliases" 归并为"查 ctVars(已含 type alias MaybeVal)"
- `bootstrap/codegen.ss:83` `comptimeTypeAliases` 全局 Map 删除,`gen_decls.ss:235` `genGlobalVar 识别 type 写 comptimeTypeAliases` 改为"写 ctVars"
- 保留 `gen_exprs.ss:160` `isKnownClass(ctIdName) == 1 → return ctVal(interpNewType(ctIdName))`(class 名当作匿名 type literal,不依赖 alias)
- **落地事实**:`grep -rn comptimeTypeAliases bootstrap/` 0 命中(D112 前 6 命中);`resolveCtTypeAlias` 与 `evalIdent` 全局 fallback 复用 `ctLookupTypeVal(name: string): int` 单点 dual-scope 查询,GATE M4/M7b 零回归

**Phase B(InternPool 引入后)**:
- Type 句柄的 id 来自 InternPool(`TY|<className>` key 去重)
- Zig `Value.Tag.ty` 语义到位 —— Type 是 Value 的一个 tag,和 int/string/class instance 共享 Value 容器
- 现有 `interpType` 等访问器语义不变,内部查 pool tag

**tag 位扩展决策**:

当前 `ctVal(id) = id | 1073741824`(bit 30 作 tag),单 tag。
- Phase A **保持单 tag**(bit 30 = "ct 已知 vs runtime reg" 区分,Type 由 `interpType` 识别不占新 tag 位)
- Phase B InternPool 引入后 tag 位可选去除(pool index 本身是唯一标识,不需要 tag 区分 ct/reg —— regTable 索引改由 MaybeVal.known=false 承载)
- **不现在就做多 tag 位**:bit 30 附近空间小,扩展 = 接口大改影响 100+ 调用点,在 Phase A 范围外且 Phase B 后反而可去除,**现在做就是负资产**

## Rejected Alternatives

- **A:MaybeVal 用两字段 `{ctVal: int, regRef: int}` 不带 known 标记** —— 接口膨胀,evalExpr 返回三元组(ct/reg/which),比 `{known, val}` 单统一 int 域多一字段且不能 transparent 传递
- **B:InternPool 一次全做**(Phase A 就引入) —— 需先定制 SS Map hash/equal + 全 `interp*` 家族值表示迁移,LOC 估 500+ 且在 evalExpr 骨架未就绪前做 = 装修未铺地的房。先跑通骨架(Phase A)再优化(Phase B)
- **C:Type-as-Value 新开 tag 位**(`ctVal(id) = id | 2147483648` 双 tag) —— 立刻把 tagged int 编码改二层,所有 `ctVal` 调用点(100+)需同步,Phase A 范围外。Phase B InternPool 引入后 tag 位反而可去除,C 方案做了就是负资产
- **D:抄 Nim 编译期 VM 的 NimNode tagged union**(`NimNodeKind` 15 种 + payload 联合) —— 独立 VM,违反 D093 §Rejected Alternatives §B "独立 VM 本身就是双轨",脱离 Zig 路线
- **E:MaybeVal.val 用 string(序列化所有值)** —— 频繁 parse/serialize,性能 + 类型安全双输。int + `interp*` 反查是现成机制
- **F:不做 Type-as-Value 合并,`comptimeTypeAliases` 作为独立通道永存** —— 违反 D093 §Zig 原理 第 3 条 "Type 本身是一个 Value,与 int/string 共享 Value 容器";独立通道就是双轨变体

## 新张力(D098 引出)

1. **`known=false` 时 `val` 复用 regTable 索引 vs 哨兵值 `-1`** — 本文选前者(regTable 索引),要求所有"返回 known=false" 路径都已先 emit runtime 指令并 push 到 regTable。若某 kind 分支在**尚未 emit 就要返回 unknown**(如错误短路、提前退出),需要哨兵值 -1 区分。**解决**:`mvError()` 构造器返回 `{known:false, val:-1}`,任何 `val = -1` 都不合法调 `reg()`。evalExpr 内部保证 val=-1 只出现在错误短路路径。

2. **Phase A → Phase B 迁移的接口稳定性** — MaybeVal.val 从"tagged int"变为"pool index",类型不变(int)但语义变。对 evalExpr 代码 transparent,但对 `interp*` 家族调用点不透明(需要区分"从 pool 取 value"vs"直接 tagged int 解码")。**解决**:Phase A 就引入 `valOf(mvVal): payload` / `valType(mvVal): string` 访问器作为接口边界,`interp*` 家族改调访问器不直读 val。Phase B 启动时只换访问器内部实现。

3. **Type 作为 MaybeVal 值时的 `interpType` 识别** — Phase A `interpType(id)` 对 tagged int 返回 "int"/"str"/"type"/"fn"/"array"/"map" 等,复用现状。Phase B pool index 时 `interpType` 走 pool 查 tag 返回字符串 tag name。接口语义一致,实现换层(Phase A 位运算解码,Phase B pool 查表)。**解决**:同 §张力 2,`valType(valId): string` 访问器封装 Phase 差异。

4. **Phase B `hash(payload)` 对大字符串/大 array 的性能** — `INT|42` 直接字符串拼接 key OK,但 `STR|<huge_string>` 或 `ARR|[1,2,...,100000]` 序列化成本高。**[x] Resolved at D111 §决策 3**:5 标量入口(int/string/bool/null/type)本轮范围内 key 短、拼接直接;Array/Map/Double 留 Phase C,sha256 预 hash 延后至 Phase C 若大 string/Array payload 出现再评估。实测 bootstrap 全测 pool 规模稳定(D111 §实测),未触发性能热点。

5. **`interp*` 家族(codegen.ss L277-500 约 30 函数)的去留节奏** — D093 §差距清单 第 5 条目标是消除独立求值器,但 Phase A / B 都保留 `interp*` 作为 Value 运算库(由 evalExpr 调用)。**张力**:`interp*` 是"双轨状态"还是"Value 运算库"? 本文立场:**运算库**(evalExpr 调用它们做常量计算,就像 Zig `Value.zig` 内有各种常量运算方法)。消除的是"独立求值入口 / 独立 state 机",不消除"常量运算函数"。Phase C 若走则把 `interp*` 重写为无 state 的纯函数(接收 valId 返回 valId),当前 `interp*` 多带隐式 state(如 `ctScopeStack` / `ctVars`),Phase C 前需提纯。

6. **SS 函数重载 int vs ptr 同名 dispatch 不生效**(2026-04-18 probe `/tmp/maybeval_overload.ss` 发现) — 声明 `f(x:int):A` + `f(mv:MaybeVal):B` 两个同名函数,调 `f(42)` 时走"最后声明"签名产生 LLVM 类型错误。原因未定位(parser / checker / codegen 哪层 mangling 失效 TBD)。**解决**:§决策 1 访问器命名从 `mvKnown/mvVal` 错到 `mvKnownOf/mvValOf`(本文已应用),与构造器 `mvKnown/mvRuntime/mvError` 区分。**衍生后续**:SS 函数重载语义待单独澄清(Java 风格严格类型 dispatch vs JS 风格"最后声明"),与本 D 文档独立,记入 §下一步 开放项。

## 下一步(Plan 型,不触发代码改动)

- **[x] Done(2026-04-18)** 验证 SS 语言能力承载 `class MaybeVal { known: bool, val: int }`:class 带 bool + int 字段 ✓ / class 作函数返回值 ✓ / 字段读写 ✓ / 自动按字段顺序构造器(`new MaybeVal(true, 42)`,无参非法,已纳入 §决策 1 构造形式)。probe `/tmp/maybeval_probe.ss` 跑通 `probe OK`
- **[ ] Planned** SS 函数重载语义澄清(int vs ptr 同名 dispatch 缺失,见 §新张力 6),不作 Phase A 阻塞项,Phase A 先用 `mvKnownOf/mvValOf` 错名访问器
- **[ ] In Progress(2026-05-20 D169 Phase 1.5a-d 接续)** 写 evalExpr Phase A 首批 1a 合并 Plan(5 个 kind:BINARY/UNARY/TERNARY/SHORT_CIRCUIT/COMPTIME_EXPR),对应上轮候选表 §C "首批 1a",引用本 D098 §决策 1 的 MaybeVal 接口 + D094 §决策 §规则 2 的 pure subset 白名单。**承接路径**:D169 §子拆解 修订版 — Phase 1.5a 落 4 helper 显式定义(mvKnownOf/mvValOf/mvRuntime/mvError)+ comptimeMustBeKnown flag;Phase 1.5b 即本条 BINARY/UNARY/TERNARY/SHORT_CIRCUIT/COMPTIME_EXPR 5 kind 入口双轨消除(callsite 走 4 helper);Phase 1.5d evalExpr 入口双轨彻底消除
- **[x] Done(2026-04-20)** Phase A 末尾 `comptimeTypeAliases` → `ctVars` 合并 Plan(§决策 3 Phase A 收尾项)—— D112 §步骤 1 Execute 完成,独立通道消除
- **[ ] Planned** Phase B 启动前单独决策:Map hash 策略 / `STR` key 预 hash / `interp*` 访问器改造范围
- **[x] Done at D117 Execute 5(2026-04-21)** — **Meta 对象 InternPool 承载**(§决策 2 §Phase B L123-128):ClassMeta / FieldMeta / MethodMeta / AnnotationMeta 五类 Meta 对象走 `internPoolGetOrInsert` name-based dedup,key schema `CLS|<cls>` / `FLD|<cls>.<fld>` / `MTH|<cls>.<mth>` / `ANN|{CLS|FLD|MTH}|<...>`,**O(1) eql** 兑现。`interpCollectFields` / `interpCtFieldsArray` 字符串拼接 + 字符串数组双轨路径消除,反射路径单入口经 `interpBuildTypeInfo` + `interpGetField(meta, field)` Meta 对象 MEMBER_ACCESS。详情见 D117 §下一步 Execute 5 Done 条目

**本 D 文档不触发任何 `.ss` 代码改动,不跑 bootstrap。** 代码改动从 evalExpr Phase A 首批 1a Plan 被批准后的 Execute 轮开始。

## 参考

- D088 §第一性需求 / §Zig 路线 §借鉴来源
- D093 §决策 §Zig 原理 / §SS 本质一样骨架 / §张力 1-3 / §下一步
- D094 §决策 §规则 1-3(继承,Phase A 仍有效)/ §Supersession §Supersession 关系(本文承接 §张力 1-3)
- Zig `src/Sema.zig` / `src/Value.zig` / `src/InternPool.zig`(原理以 D093 §Zig 原理 固化文本为权威,不做外部 fetch)
- D088 Phase 4 "类型作为 comptime 值" 实现点(§决策 3 Phase A 收尾目标):`bootstrap/codegen.ss:83`(`comptimeTypeAliases` 待删) / `gen_exprs.ss:158-163`(genVal IDENT 查表待合并)/ `gen_decls.ss:235`(`genGlobalVar` 识别 type 待改走 ctVars)
