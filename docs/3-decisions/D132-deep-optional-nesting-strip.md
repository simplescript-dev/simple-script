# D132: 类型解析 SHR/USHR 拆分时 maybeNullable 错位消耗 outer `?` —— 任意 N×M nullable + 嵌套递归同构剥皮根因修

> 上层规则:[D130 §SSoT 收敛](./D130-deserializer-ssot-converge.md) + [D131 谓词层 stripNullableCG inner](./D131-deserialize-predicate-strip-nullable-inner.md) + [D067 null safety 概念锚](../../bootstrap/checker/check_narrow.ss)(memory `project_null_safety_design.md` SSoT) + [CLAUDE.md §Root Cause 优先 §第一法则无例外](../../CLAUDE.md)
> 触发:I021-requestbody-nested-deep-optional Execute 第一步 emit-ir 实测部分破裂(commit 7e3407b — form 1+2 双 `?` 完全命中 + form 3-6 单 `?` + N=2 嵌套结构层位漂移)→ 谓词层 D131 + SSoT D130 之上**类型字符串规范形态**层根因暴露

## 1. 触发证据

I021-requestbody-nested-deep-optional Plan 起立(commit abc006d)子档 §假设链:`Array<Array<Tag>>?` 字段类型 → emitDeserializeForType 字段层 stripNullableCG outer `?` → nullable case opt_present 委托递归 emitDeserializeForType("Array<Array<Tag>>", ...) → D131 §4.1 谓词二级递归命中 isArrayDeserializable → emitArrayDeserializeInto outer + inner emitArrayDeserializeInto + 最内层 @Tag_deserialize 三层链 — D130 SSoT + D131 谓词层联动**理论上**笛卡尔积真零 codegen 自动 cover。

**Execute 阶段第一步实测验证(D130 SSoT + D131 谓词层第三次自动 cover 假设破裂检测)**:

实测命令(`/tmp/t_deep_optional.ss` 6 fixture × N=2 双层笛卡尔积 emit-ir 触发):

```bash
bin/ss build /tmp/t_deep_optional.ss --emit-ir > /tmp/t.ll       # exit 0,/tmp/t.ll 13288 行
grep -cE '@jnIsNullOrMissing' /tmp/t.ll                          # = 9 (1 lib def + 8 call sites)
grep -cE 'opt_present|opt_done' /tmp/t.ll                        # = 32 (label + IR 文本嵌入)
grep -cE 'jnArrayLen|jnObjectKeys' /tmp/t.ll                     # = 15 (12 call site + IR 嵌入)
grep -cE '@Tag_deserialize' /tmp/t.ll                            # = 7 (1 def + 6 fixture × call site)
```

**4 条 grep 阈值数量 PASS** 但**抽 IR body 看结构发现 grep 计数是 lower bound 数量判据,无法区分"双 `?` 双 nullable case 链"vs"单 `?` 层位下沉到 inner element"** —— 6 fixture 实际分两类:

| # | Fixture | 字段类型 | outer null guard | inner null guard | 结构 |
|---|---|---|---|---|---|
| 1 | OrderTagsArrDeepOpt | `Array<Tag?>?` (双 `?`) | ✓ jnIsNullOrMissing(`/tmp/t.ll:12846` opt_present.751) | ✓ inner element "Tag?" 走 nullable case opt_present.756 | **完全命中** |
| 2 | OrderTagsMapDeepOpt | `Map<string, Tag?>?` (双 `?`) | ✓ opt_present.790 | ✓ inner value opt_present.795 | **完全命中** |
| 3 | OrderMatrixOpt | `Array<Array<Tag>>?` (单 `?` + N=2 嵌套) | ❌ 直 jnArrayLen(`:13066`)无 outer null guard | ❌ inner element type `Array<Tag>` 非 nullable 但误触发 jnIsNullOrMissing(`:13081` opt_present.777) | **结构层位漂移** |
| 4 | OrderGroupsOpt | `Map<string, Map<string, Tag>>?` (单 `?` + N=2 Map 嵌套) | ❌ 直 ss_mapNew(`:12908`)无 outer null guard | ❌ inner value type `Map<string, Tag>` 误触发 opt_present.761 | **结构层位漂移** |
| 5 | OrderArrMapOpt | `Array<Map<string, Tag>>?` (单 `?` + 混合) | ❌ 直 jnArrayLen(`:13143`) | ❌ inner element type `Map<string, Tag>` 误触发 opt_present.785 | **结构层位漂移** |
| 6 | OrderMapArrOpt | `Map<string, Array<Tag>>?` (单 `?` + 混合) | ❌ 直 ss_mapNew(`:12988`) | ❌ inner value type `Array<Tag>` 误触发 opt_present.769 | **结构层位漂移** |

**双重症状归一**:
- (a) **outer null guard 缺失**:`Array<Array<Tag>>?` 字段层 emitDeserializeForType 入口本应 stripNullableCG 剥末尾 `?` 触发 nullable case,实测**未触发**
- (b) **inner element 误 wrap**:emitArrayDeserializeInto/emitMapDeserializeInto 内部递归 emitDeserializeForType(elemType, elemNode) 时,elemType 本应非 nullable(form 3 inner `Array<Tag>` / form 4 inner `Map<string,Tag>`),实测**走 nullable case wrap**

(a) + (b) **同源根因**:同一 type string 被错位解析或错位拼接,outer `?` 标记**层位下沉**到 inner element 层。

## 2. 根因定位

### 2.1 token 流分析

lexer 合并规则:
- `>>` → SHR 单 token
- `>>>` → USHR 单 token
- `>?>` 等含 QUESTION 切断序列保持 GT/QUESTION 独立 token

parser 类型上下文 SHR/USHR 拆分协议(`bootstrap/parse/parser.ss:201-229 expectGtTypeCtx + pendingGtTokens`):

```ss
let pendingGtTokens = 0

function expectGtTypeCtx() {
    if (pendingGtTokens > 0) {
        pendingGtTokens = pendingGtTokens - 1
        return                          // 不动 token,递减虚拟拆分余量
    }
    const k = curKind()
    if (k == "GT") { pAdvance(); return }
    if (k == "SHR") { pendingGtTokens = 1; pAdvance(); return }     // SHR=2 GT,消 1 留 1
    if (k == "USHR") { pendingGtTokens = 2; pAdvance(); return }   // USHR=3 GT,消 1 留 2
    ...
}
```

nullable suffix 检测点(`bootstrap/parse/parser.ss:789-796 maybeNullable`):

```ss
function maybeNullable(baseType: string): string {
    if (curKind() == "QUESTION") {
        pAdvance()
        return baseType + "?"
    }
    return baseType
}
```

parseTypeAnn IDENT generic 路径(`:824-839`):

```ss
if (k == "IDENT") {
    let name = curValue()
    pAdvance()
    if (curKind() == "LT") {
        pAdvance()
        let typeArgs = parseTypeAnn()
        while (curKind() == "COMMA") {
            pAdvance()
            typeArgs = listAppendStr(typeArgs, parseTypeAnn())
        }
        expectGtTypeCtx()                               // outer 闭合(可能消 SHR/USHR 设 pendingGtTokens)
        return maybeNullable(name + "<" + typeArgs + ">")   // 紧接检 QUESTION
    }
    return maybeNullable(name)
}
```

### 2.2 调用栈反向追踪 form 3 `Array<Array<Tag>>?`

**Token 流**:`Array IDENT, LT, Array IDENT, LT, Tag IDENT, SHR, QUESTION`

| Step | 调用栈 | cursor | pendingGtTokens | 行为 |
|---|---|---|---|---|
| 1 | parseTypeAnn outer (Array) | Array IDENT | 0 | pAdvance → LT,pAdvance(LT)→ Array IDENT |
| 2 | parseTypeAnn inner (Array) | Array IDENT | 0 | pAdvance → LT,pAdvance(LT)→ Tag IDENT |
| 3 | parseTypeAnn leaf (Tag) | Tag IDENT | 0 | pAdvance → SHR;不进 LT 分支;调 maybeNullable("Tag") |
| 3a | maybeNullable("Tag") | SHR | 0 | curKind=SHR ≠ QUESTION → return "Tag" ✓ |
| 4 | inner expectGtTypeCtx | SHR | 0 → 1 | SHR 消 1 留 1,pAdvance → **QUESTION** |
| 5 | inner maybeNullable("Array<Tag>") | **QUESTION** | 1 | curKind=QUESTION → **pAdvance 消耗 outer 的 `?`!** + return **"Array<Tag>?"** ❌ |
| 6 | outer expectGtTypeCtx | (QUESTION 后) | 1 → 0 | pendingGtTokens=1 → 递减不动 token |
| 7 | outer maybeNullable("Array<Array<Tag>?>") | (QUESTION 后) | 0 | curKind ≠ QUESTION → return **"Array<Array<Tag>?>"** ❌ outer `?` 丢失 |

**parser 输出**:`"Array<Array<Tag>?>"`(`?` 错位下沉到 inner)而非规范 `"Array<Array<Tag>>?"`。

### 2.3 下游 codegen 链跟踪(承 §2.2 错位输出)

字段类型 `paramType("matrix") = "Array<Array<Tag>?>"` (`bootstrap/parse/parser.ss:125 nGetS2`):

`bootstrap/gen/class/class_register.ss:99-112` 字段注册:
- `fType = "Array<Array<Tag>?>"`
- `strippedType = stripNullableCG(fType)` = `"Array<Array<Tag>?>"` (末尾 `>` 不是 `?` → 不剥)
- `fType == strippedType` → **classFieldNullable 不 set** ❌ 字段不被识别为 nullable
- `classFieldTypes.set("OrderMatrixOpt.matrix", "Array<Array<Tag>?>")`

`bootstrap/gen/gen_deserialize.ss:316-329` 字段循环:
- `ft = "Array<Array<Tag>?>"`
- `classFieldNullable.has` = 0 → ft 不加 `?`
- `emitDeserializeForType("Array<Array<Tag>?>", childNodeR)`

emitDeserializeForType 入口(`:100-124`):
- `stripped = stripNullableCG("Array<Array<Tag>?>")` = `"Array<Array<Tag>?>"` (末尾 `>` → 不剥)
- `stripped == ssType` → **不走 nullable case** ❌ outer null guard 不 emit (与 IR 实测 line 13066 jnGetField 后直接 jnArrayLen 一致)
- `isArrayDeserializable("Array<Array<Tag>?>") = 1` (D131 §4.1 谓词:et = extractContainerElemType = `"Array<Tag>?"`,etStripped = stripNullableCG = `"Array<Tag>"`,isArrayDeserializable("Array<Tag>")=1 三级递归)→ 走 emitArrayDeserializeInto outer ✓
- emitArrayDeserializeInto outer:`elemType = extractContainerElemType("Array<Array<Tag>?>") = "Array<Tag>?"` ❌ inner element 类型**带 `?`**
- 内层 emitDeserializeForType("Array<Tag>?", elemNode):
  - `stripped = "Array<Tag>"` (剥末尾 `?`) → stripped != ssType → **触发 nullable case** ❌ inner element 误 wrap (与 IR 实测 line 13081 opt_present.777 一致)

**双重症状 (a) + (b) 完美由 §2.2 parser 错位输出 + §2.3 下游 codegen 透传一致解释。**

### 2.4 根因物理位置

**`bootstrap/parse/parser.ss:790-796 maybeNullable` 缺 pendingGtTokens guard**:

```ss
function maybeNullable(baseType: string): string {
    // ❌ 缺 guard:SHR/USHR 拆分中间状态(pendingGtTokens > 0)cursor 上 QUESTION 属 outer
    if (curKind() == "QUESTION") {
        pAdvance()                  // ❌ 错位消耗 outer 的 `?`
        return baseType + "?"
    }
    return baseType
}
```

`pendingGtTokens > 0` 表 outer 容器还未闭合(SHR/USHR 拆分中间状态),此时 cursor 上的 QUESTION token 必须留给 outer maybeNullable 在 outer expectGtTypeCtx 完成后消耗,不能被 inner maybeNullable 错位消耗。

## 3. 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **parser maybeNullable + pendingGtTokens guard** —— `bootstrap/parse/parser.ss:790-796` 加 1 行 guard:`if (pendingGtTokens > 0) { return baseType }` 优先于 QUESTION 检测,SHR/USHR 拆分中间状态 inner maybeNullable 不消耗 cursor 上的 QUESTION,留给 outer maybeNullable 在 outer expectGtTypeCtx pendingGtTokens 递减归零后正确消耗。**任意 N×M nullable + 嵌套递归同构剥皮全形态自动 cover** —— form 1-2 双 `?`(不触发 SHR/USHR pendingGtTokens=0 路径不变)+ form 3-6 单 `?` + N=2 嵌套(SHR/USHR 拆分时 guard 触发,outer `?` 正确归 outer)+ N=3+ 任意嵌套(`Array<Array<Array<Tag>>>?` USHR pendingGtTokens=2 同源 cover)+ 中层 `?` + 外层 `?`(`Array<Array<Tag>?>?` 不触发 SHR 路径不变)| **根因方案** ✅ — Root Cause 物理位置(parser.ss 类型解析层) + 第一法则无例外 + 物理 +1 LOC 单点修;codegen / inferType / 谓词 / 字段循环 / extractContainerElemType / classFieldTypes / classFieldNullable 全自动 cover(parser 输出规范形态后下游既有正确 — D130 SSoT + D131 谓词层 + D067 概念锚联动设计意图全维度兑现);RC 契约不变(parser 修不动 codegen RC 路径) ✅ |
| B | codegen 同构剥皮 normalize —— emitDeserializeForType / 谓词层 / extractContainerElemType / 字段循环多处加 normalize 函数 normalize(t: string) 拆类型字符串后重组规范形态 | **症状 patch** ❌ — 违反 [CLAUDE.md §Root Cause 优先 §第一法则无例外];multi-site normalize 易漏(每处 reader 都需调 normalize 一致,SSoT 破裂);parser 输出已错位但 codegen 反向修复 = 在错误基础上叠加修补;新增类型字符串 reader 又会漏调 normalize 引入下游 regression;**违反 D131 选 A 同源原则**(谓词层 D131 选 A 也是单点最早入口修而非多处 patch) |
| C | classFieldTypes 注册阶段 normalize + classFieldNullable 多 bit flag —— `bootstrap/gen/class/class_register.ss:99-112` 字段注册时拿到 fType 后做规范化(递归同构剥皮),classFieldNullable Map 重设计为 multi-bit 或 string 表每层 nullable 位置 | **范围错位** ❌ — 注册阶段 normalize 仅 cover 字段层,**inferType / 局部变量类型 / 表达式类型 / 函数返回类型** 等其他类型字符串 reader 不 cover,分布式破裂;classFieldNullable 数据结构变更影响 D131 已落地多处 reader(`bootstrap/gen/gen_deserialize.ss:323` 字段恢复 `?` + 其他若干 caller),需大规模联动改 codegen 引入 regression 风险;且根因仍未解决(parser 错位输出未修),仅在某一层补 patch |
| D | parser 根因修 + codegen 容错 normalize 双修 —— A + B 双重防御 | **双轨制违反 SSoT** ❌ — 根因修(A)已物理消除问题,容错 normalize(B)成冗余且引入维护成本;若 A 修后又改 codegen 又会因 normalize 多余造成误诊断;违反 [memory `feedback_root_cause_no_cost.md`] "选根因不选次优" + "成本不是选次优的理由" |

选 **A** —— Root Cause 物理位置(parser.ss 类型解析层 maybeNullable 协议) + 物理 +1 LOC 单点 surgical 修 + 任意 N×M 嵌套形态自动 cover + 下游 codegen 全自动正确 + 与 D131 谓词层选 A 同源(单点最早入口修)。

## 4. 决策

### 4.1 maybeNullable pendingGtTokens guard

```ss
// bootstrap/parse/parser.ss:789-796
function maybeNullable(baseType: string): string {
+   // D132: SHR/USHR 拆分中间状态(pendingGtTokens > 0)outer 容器尚未闭合,
+   // cursor 上的 QUESTION 属 outer 不属当前 baseType。inner 必须留给 outer
+   // maybeNullable 在 outer expectGtTypeCtx pendingGtTokens 递减归零后消耗。
+   if (pendingGtTokens > 0) { return baseType }
    if (curKind() == "QUESTION") {
        pAdvance()
        return baseType + "?"
    }
    return baseType
}
```

**+1 行 guard 物理修**(注释 +3 行,不算 codegen LOC)。

### 4.2 任意 N×M nullable + 嵌套递归同构剥皮覆盖证明

| 形态 | Token 流末段 | inner pendingGtTokens 状态 | outer maybeNullable 行为 | parser 输出 |
|---|---|---|---|---|
| `Tag?` 平凡 | Tag, QUESTION | n/a | 直接 maybeNullable QUESTION pAdvance | `"Tag?"` ✓ |
| `Array<Tag>?` 单容器 + outer | Tag, GT, QUESTION | 0(GT 单 token,pendingGtTokens 不动) | 通过 guard,QUESTION pAdvance | `"Array<Tag>?"` ✓ |
| `Array<Tag?>` 单容器 + inner | Tag, QUESTION, GT | 0 | inner Tag maybeNullable 消 QUESTION + outer GT 闭合 + outer maybeNullable curKind ≠ QUESTION | `"Array<Tag?>"` ✓ |
| `Array<Tag?>?` 双 `?`(form 1) | Tag, QUESTION, GT, QUESTION | 0(全程 pendingGtTokens=0) | inner Tag 消第一 QUESTION + outer GT 闭合 + outer 消第二 QUESTION | `"Array<Tag?>?"` ✓ form 1 既有正确不影响 |
| `Array<Array<Tag>>?` 单 `?` + N=2(form 3) | Tag, SHR, QUESTION | inner expectGtTypeCtx 消 SHR 设 pendingGtTokens=1 → cursor=QUESTION | inner maybeNullable **guard 触发不消 QUESTION** + outer expectGtTypeCtx 消 pendingGtTokens 递减 + outer maybeNullable curKind=QUESTION pAdvance | **`"Array<Array<Tag>>?"`** ✓ **修后 form 3 正确** |
| `Map<string, Map<string, Tag>>?` 单 `?` + N=2 Map(form 4) | Tag, SHR, QUESTION | 同 form 3 | 同 form 3 | **`"Map<string,Map<string,Tag>>?"`** ✓ |
| `Array<Map<string, Tag>>?` / `Map<string, Array<Tag>>?` 混合(form 5/6) | Tag, SHR, QUESTION | 同 form 3 | 同 form 3 | **混合形态规范** ✓ |
| `Array<Array<Tag?>>?` 单 outer + 单 inner element nullable + N=2 | Tag, QUESTION, SHR, QUESTION | inner Tag 先消第一 QUESTION + middle expectGtTypeCtx 消 SHR 设 pendingGtTokens=1 + middle maybeNullable guard 触发不消第二 QUESTION + outer expectGtTypeCtx 递减 + outer 消第二 QUESTION | `"Array<Array<Tag?>>?"` ✓ |
| `Array<Array<Array<Tag>>>?` N=3 + outer(USHR) | Tag, USHR, QUESTION | innermost expectGtTypeCtx 消 USHR 设 pendingGtTokens=2 → cursor=QUESTION + 中层 expectGtTypeCtx 递减到 1 + 中层 maybeNullable guard 触发 + outer expectGtTypeCtx 递减到 0 + outer maybeNullable 消 QUESTION | `"Array<Array<Array<Tag>>>?"` ✓ N=3 任意层数自动 cover |
| `Array<Array<Tag?>?>?` N=2 + 三层 `?`(中层 + 内层 + 外层) | Tag, QUESTION, GT, QUESTION, GT, QUESTION | 各层 pendingGtTokens=0(全 GT 单 token,无 SHR/USHR 合并)→ 各层 maybeNullable 各自消一 QUESTION | `"Array<Array<Tag?>?>?"` ✓ 任意 M 层 nullable 同源 |
| `Map<string, Tag?>?` 双 `?` Map(form 2) | Tag, QUESTION, GT, QUESTION | 0 | inner Tag 消第一 QUESTION + outer GT + outer 消第二 QUESTION | `"Map<string,Tag?>?"` ✓ form 2 既有正确不影响 |

**N×M 全形态归纳**:
- N 维度(嵌套层数):1/2/3/...任意层 — pendingGtTokens 协议拆分 SHR(2 层)/USHR(3 层),guard 在中间状态生效保留 outer `?`,outer 闭合后正确消 outer `?`,**任意 N 自动 cover**
- M 维度(每层 nullable 位置):某层有 `?` 通过 GT 单 token 闭合(不触发 SHR/USHR 合并)maybeNullable 直接消;每层 `?` 独立位置;**任意 M 位置组合自动 cover**
- 笛卡尔积 N × M:全形态自动 cover 物理证明(上表 10 形态全样本 + 推广)

### 4.3 codegen / 谓词层 / SSoT 入口不动

parser 修后输出规范形态字符串 → 下游全链路自动正确:
- `bootstrap/gen/class/class_register.ss:99-112` 字段注册 stripNullableCG 顶层剥皮 + classFieldNullable flag — **既有正确** ✓
- `bootstrap/gen/gen_deserialize.ss:100-124 emitDeserializeForType` 字段层入口 stripNullableCG + nullable case — **既有正确** ✓
- `bootstrap/gen/gen_deserialize.ss:14-23 isArrayDeserializable` / `:32-41 isMapDeserializable` D131 §4.1+4.2 谓词层 stripNullableCG inner — **既有正确** ✓
- `bootstrap/gen/gen_rc.ss:220-232 extractContainerElemType` Array `<X>` 截取 / Map `<K,V>` value 提取 — **既有正确** ✓
- `bootstrap/gen/gen_deserialize.ss:48-83 emitPendingDeserializers` BFS transitive closure D131 §4.4 多层 stripNullableCG — **既有正确** ✓
- `bootstrap/gen/gen_types.ss:417 inferType .get` D131 §4.5 stripNullableCG Map.get — **既有正确** ✓

### 4.4 D131 / D130 / D067 不变量保留

- D131 谓词层 stripNullableCG inner(`isArrayDeserializable` / `isMapDeserializable`)不动 — 修后输入字符串规范,谓词原既有 stripNullableCG 等价工作
- D130 emitDeserializeForType SSoT 单点解码不动 — 修后字段层 nullable case 正确触发,SSoT 设计意图第三次自动 cover 兑现(笛卡尔积真零 codegen 场景对照 -inner 首次部分命中 + -container 首次完全命中)
- D067 null safety T? 概念锚不动 — checker 路径(`bootstrap/checker/check_narrow.ss:12-26`)未触及 SHR/USHR 类型上下文(checker 在 parser 之后接收规范形态字符串)
- D018 ObjectLayout / D022 clone / D088 编译期反射禁 / D023 mimalloc 集成 — 所有内存 / 类型 / 反射不变量不动

## 5. RC 契约保留(根因修不动 RC 语义)

| 类型 T | RC 契约(D132 修前) | RC 契约(D132 修后) |
|---|---|---|
| `Array<Array<Tag>>?` 字段 (form 3) | parser 错位输出 `"Array<Array<Tag>?>"` → emitDeserializeForType 字段层不触发 nullable case → emit 直接 jnArrayLen + ss_arrayPush + 内层 `Array<Tag>?` 误触发 nullable case wrap @Tag_deserialize / store ptr null(IR 数据语义错乱:JSON `null` outer 走 jnArrayLen segfault) | parser 规范输出 `"Array<Array<Tag>>?"` → emitDeserializeForType 字段层 nullable case opt_present + 委托递归 `"Array<Array<Tag>>"` → emitArrayDeserializeInto outer + 内层 `"Array<Tag>"` 不带 `?` 直接走 isArrayDeserializable case → 内层 emitArrayDeserializeInto inner + 最内 @Tag_deserialize transfer ✓ |
| `Map<string, Map<string, Tag>>?` 字段 (form 4) | parser 错位输出 `"Map<string,Map<string,Tag>?>"` → 同 form 3 IR 错乱 | parser 规范输出 + 字段层 nullable case + outer/inner emitMapDeserializeInto 双层 + 最内 @Tag_deserialize transfer ✓ |
| `Array<Map<string, Tag>>?` / `Map<string, Array<Tag>>?` 混合 (form 5/6) | parser 错位输出 → IR 错乱 | parser 规范输出 + 跨族 emit 嵌套 ✓ |
| outer null + inner null 笛卡尔积 | n/a (form 3-6 IR 错乱不可达) | outer null → 字段 store ptr null(ss_release isnull guard 自带覆盖,D018 + D023 + 父档 commit 29c3148 §风险 1 实测同源) + inner null 路径在 D131 §5 RC 契约表既有覆盖 ✓ |
| `Array<Tag?>?` (form 1) / `Map<string, Tag?>?` (form 2) 双 `?` | 双 `?` 完全命中 ✓ (D131 §5 RC 契约表既有覆盖) | 修不影响 ✓ |

双 RC 系统(D018 + D022)/ Map drop 链(ss_rc_destroy_map → ss_release ptr null 自动 isnull guard)/ TypeInfo vtable / class transfer / array push 不 retain 等所有 RC 语义不变。

## 6. 验证

### RED 命令(D132 修前 form 3-6 全 = 错位)

- `bin/ss build /tmp/t_deep_optional.ss --emit-ir > /tmp/t.ll && grep -nA 30 'OrderMatrixOpt_deserialize' /tmp/t.ll | grep -c 'jnArrayLen.*nodeId.arg'` ≥ 1(outer 直 jnArrayLen 字段层无 outer null guard)
- `grep -nA 30 'OrderGroupsOpt_deserialize' /tmp/t.ll | grep -c '@ss_mapNew'` 在字段 `%6` 后 `%7 = jnGetField` 后 ≥ 2 处 ss_mapNew(outer + inner 双 emit 但 outer 无 null guard)
- form 3-6 字段 `%7 = call i32 @jnGetField` 之后**直接** `jnArrayLen` / `ss_mapNew`,**无 jnIsNullOrMissing 介入**(IR 实测确认)

### GREEN 验收(D132 修后 全形态正确)

- `bin/ss build /tmp/t_deep_optional.ss --emit-ir > /tmp/t.ll && grep -cE '@jnIsNullOrMissing' /tmp/t.ll` ≥ 13(1 lib def + 6 fixture × outer 字段层 + 6 fixture × inner 双 `?` 形态 form 1+2 二级 + form 3-6 三级递归内层只在真 nullable 处嵌入)
- form 3 OrderMatrixOpt:`grep -nA 50 'OrderMatrixOpt_deserialize' /tmp/t.ll` 字段 `%7 = jnGetField` 之后**先** alloca i64 slot + jnIsNullOrMissing + opt_present/opt_done labels(outer null guard) + opt_present 内 emitArrayDeserializeInto outer + inner emitArrayDeserializeInto + 最内 @Tag_deserialize transfer 三层链
- form 4 OrderGroupsOpt:同 form 3 同源 IR + emitMapDeserializeInto 双层 + outer null guard
- form 5/6 OrderArrMapOpt / OrderMapArrOpt:跨族 emitArrayDeserializeInto+emitMapDeserializeInto 嵌套 + outer null guard
- inner element 类型不再误触发 nullable case wrap:`grep -nA 50 'OrderMatrixOpt_deserialize' /tmp/t.ll | grep -c 'opt_present'` 仅 1 处(outer 字段层)而非 2 处(outer + inner 误)
- bootstrap 三阶段固定点 PASS(stage2 == stage3)
- reflection_health_linter GATE PASS no regressions
- `bin/ss test tests/phase5/i021_requestbody_nested_deep_optional.ss` 8-10 case 全 PASS(本 D 文档 GREEN 后 Execute 阶段同轮新建)
- 全套 phase4/5 无 regression(对比 commit 7e3407b baseline)
- spring-parity hello fixture 6 endpoint × 4 场景(present / outer null / outer missing / inner null)curl POST byte-identical Java oracle

### Execute 阶段第一步实测分流命令(根因 H1 物理验证)

```bash
# 在 bootstrap/parse/parser.ss:789-796 maybeNullable 加 1 LOC guard 后
./build.sh bootstrap                                     # 三阶段固定点验证
bin/ss build /tmp/t_deep_optional.ss --emit-ir > /tmp/t.ll
grep -nA 30 'OrderMatrixOpt_deserialize' /tmp/t.ll | head -40

# 期望 IR 形态(承 §6 GREEN 验收):
# %7 = call i32 @jnGetField(...)
# %8 = alloca i64, align 8                          ← outer null guard alloca
# store i64 0, ptr %8, align 8
# %9 = call i32 @jnIsNullOrMissing(i32 %7)          ← outer null guard 检测
# %10 = icmp eq i32 %9, 0
# br i1 %10, label %opt_present.X, label %opt_done.Y
# opt_present.X:
#   %11 = call i32 @jnArrayLen(i32 %7)              ← outer arr loop
#   ...
#   arr_loop.body.Z:
#     %14 = call i32 @jnArrayGet(i32 %7, i32 %15)
#     %16 = call i32 @jnArrayLen(i32 %14)            ← inner arr loop 直接(无 nullable case wrap)
#     ...
#       %18 = call ptr @Tag_deserialize(i32 %X)     ← 最内层 @Tag_deserialize transfer

# 若 IR 仍现 form 3-6 错位症状(outer 直 jnArrayLen 无 null guard / inner 误 wrap nullable case)
# → H1 物理为假 → 退路 H2 codegen 同构剥皮 normalize(候选 B 升根独立 D 文档子决策)
```

## 7. 影响

### 代码改动范围

| 文件 | 改动类型 | 行数估计 |
|---|---|---|
| `docs/3-decisions/D132-deep-optional-nesting-strip.md` | 新增(本 D 文档)| ~250 行 |
| `bootstrap/parse/parser.ss:789-796 maybeNullable` | +1 行 guard + 3 行注释(留 Execute 落地) | +1 LOC + 3 注释 |
| `tests/phase5/i021_requestbody_nested_deep_optional.ss` | 新增 8-10 case(留 Execute 落地)| ~180-220 行 |
| `examples/spring-parity/hello/ss/HelloController.ss` | 加 6 fixture DTO + @PostMapping(留 Execute 落地)| +30 行 |
| `examples/spring-parity/hello/java/.../HelloController.java` | Java oracle 对称(留 Execute 落地)| +30 行 |
| `docs/4-issues/I021-requestbody-nested-deep-optional.md` | §status / §备注 同步指向 D132 锁定 | ~5 行 Edit |

### 后续 issue 自动 cover

- **I021-requestbody-nested-deep-optional v0**(本 D132 GREEN 后 Execute 阶段 ship)— form 1+2 双 `?` 命中 + form 3-6 单 `?` + N=2 嵌套修后命中 — 笛卡尔积**真零 codegen 场景**(承 commit d968504 -container 首次完全命中模式)+ 8-10 case + spring-parity + RC stress 50 次循环
- **任意 N=3+ 嵌套 + outer `?`**(`Array<Array<Array<Tag>>>?` / N≥3 USHR 拆分形态)— D132 修后任意 N 自动 cover(§4.2 形态 9 推广)— 不需独立子档,Execute 阶段加 1-2 case 测试自动验证
- **任意 N=2+ 嵌套 + 任意 M 层 nullable 笛卡尔积**(`Array<Array<Tag?>?>?` / `Array<Map<string, Tag?>>?` / `Map<string, Array<Tag?>?>?` 等)— D132 修后任意 M 自动 cover(§4.2 形态 8 推广)— 不需独立子档,Execute 阶段加 2-3 case 测试自动验证
- **后续 enum / Optional / Tuple / Set 加 emitDeserializeForType case** — parser 类型解析层 maybeNullable + pendingGtTokens guard 修法**对所有泛型类型字符串规范形态有效**(不仅 Array/Map),后续容器类型扩展自动 cover

### Phase 4 §247 第二支柱嵌套深化第十一轮

承接 commit 7e3407b(I021-requestbody-nested-deep-optional Execute 第一步实测部分破裂 confirmed)→ 本 D132 D 文档锁定根因 + 修法 + 风险锚 + Execute 落地路径(本轮纯文档单 Layer)→ 下下轮 Execute 阶段 parser.ss +1 LOC 修 + 测试 + spring-parity 同 commit。

### D130 SSoT + D131 谓词层 + D067 概念锚 三联动设计意图全维度兑现

- D130 SSoT(per-class deserializer 单点 emitDeserializeForType inner 委托)— c52e9b5 / 95eb282 / b18850e / 74ddc48(D131 升根)/ d968504(完全命中真零 codegen)五轮自动 cover 验证 + 本 D132 GREEN 后 form 3-6 笛卡尔积**真零 codegen 场景兑现**(承 commit d968504 模式)
- D131 谓词层 stripNullableCG inner(`isArrayDeserializable` / `isMapDeserializable`)— commit 74ddc48 落地 + 本 D132 修后字段层 nullable case 正确触发,**D131 谓词层无需扩**(D131 §4 边界扩 vs D132 独立新档 取舍 — 选 D132 独立新档,理由:议题尺度跨 parser/codegen 类型层规范化,远超 D131 谓词层 inner stripNullableCG)
- D067 null safety T? 概念锚 — `bootstrap/checker/check_narrow.ss:12-26` 不动,checker 在 parser 之后接收规范形态字符串

## 8. 反向 / 备选

(见 §3 候选路径 — B/C/D 否决)

**H1 不命中回退路径**:若 Execute 阶段第一步实测(`§6 Execute 阶段第一步实测分流命令`)发现 parser maybeNullable + pendingGtTokens guard 修后 IR 仍现 form 3-6 错位症状(outer 直 jnArrayLen 无 null guard / inner 误 wrap nullable case),则 H1 物理为假,根因物理位置在 codegen / classFieldTypes / extractContainerElemType 嵌套维度 outer `?` 层位耦合,需升根 D132' 独立 D 文档子决策走候选 B(codegen 同构剥皮 normalize) — 但 §2.2 token 流跟踪推证 + §2.3 下游 codegen 链跟踪 + IR 双重症状(a)+(b)归一解释链已物理证明 H1 物理为真(form 3 IR 实测 line 13066 jnGetField 后直接 jnArrayLen + line 13081 opt_present.777 inner 误 wrap),H1 实测命中预期 ≥ 99%。

## 9. 备注

- **触发事件**:2026-04-26 I021-requestbody-nested-deep-optional Execute 阶段第一步 emit-ir 实测(commit 7e3407b — 子档 §候选 A §假设破裂回退路径 line 211-214 + §风险 1+5 升根触发);本 D132 D 文档 + 子档 §status 同步同轮起立(Decision 单 Layer — 本轮纯文档,Execute 留下下轮)
- **D131 §4 边界扩 vs D132 独立新档**:选 D132 独立新档。理由(三条)
  1. 议题尺度:D131 是谓词层 inner type 识别 stripNullableCG bug 修(`isArrayDeserializable` / `isMapDeserializable` 谓词内 et/vt + stripNullableCG)— D132 是**类型字符串规范形态**层根因(parser maybeNullable + pendingGtTokens 协议) — 跨层级议题不应扩 D131 §4 子节
  2. 修法物理位置:D131 修法在 `bootstrap/gen/gen_deserialize.ss` 谓词函数 — D132 修法在 `bootstrap/parse/parser.ss` 类型解析函数 — 跨文件物理位置不应扩 D131 §4 子节
  3. D 文档治理:D131 已 Decided + Done at commit 74ddc48,扩 D131 §4 会污染 D131 history;独立 D132 ADR 结构清晰
- **Layer 跨越**:D132 D 文档 = Decision 层,本轮单 Layer 写 D 文档 + Edit I021 子档 §status 同步 + Write next_prompt + 不主动改 codegen / 测试(避免单轮 Layer 混 — feedback `feedback_interactive_one_doc.md` + MNK §字段 8)
- **本 D 文档 status**:Plan 起立(2026-04-26)+ Decided(根因 H1 锁定 + 候选 A 修法选定 + +1 LOC 物理修)+ **Done at `bootstrap/parse/parser.ss:790-800 maybeNullable + pendingGtTokens guard`(本轮 Execute 落地)**;I021 子档测试 + spring-parity 同 commit ship(详见 §备注 §status reconciliation 锚)
- **不变量保留**:D018 ObjectLayout(RC@0 + TypeInfo@1) + D022 clone 语义 + D088 编译期展开消除运行时反射 + D130 emitDeserializeForType SSoT 单点解码 + D131 谓词层 stripNullableCG inner + D067 null safety T? 概念锚(memory `project_null_safety_design.md`) + commit 29c3148 emitDeserializeForType nullable case alloca slot + jnIsNullOrMissing + opt_present/opt_done labels 主路径
- **回头观察点**(Execute 阶段验证 — 详 §10 实测验证 Plan):
  - 修后 N=3+ 形态自动 cover 验证(`Array<Array<Array<Tag>>>?` / `Map<string, Map<string, Map<string, Tag>>>?` USHR 拆分 + outer `?`) — 预期同源 cover(§4.2 形态 9 + §10.2 轴 A 推证 + §10.6 RED 命令)
  - 修后任意 M 层 nullable 笛卡尔积自动 cover 验证(`Array<Array<Tag?>?>?` / `Array<Map<string, Tag?>>?` 等)— 预期同源 cover(§4.2 形态 8 + §10.2 轴 B 推证 + §10.6 RED 命令)
  - parser SHR/USHR + nullable 联动是否影响 generic class / generic method / generic function 类型参数解析(parseTypeAnn 复用)— 预期不影响(maybeNullable 仅在类型参数末尾调,泛型 class/method 类型参数列表内层调用同 pendingGtTokens 协议)— Execute 阶段 phase4 全套测试无 regression 验证(详 §10.2 轴 C 推证 + §10.6 RED 命令)
  - I021-requestbody-nested-deep-optional Execute 落地后 form 1+2 ship 切分 vs 一并 ship 决策 — 已选一并 ship(本 D 文档 §status Done at commit e75b6ea — 同 commit 6 fixture 笛卡尔积全形态)
- **依赖关系**:本 D132 不依赖 D131 文本演进(D131 选 A 谓词层 stripNullableCG inner 修保留有效);D132 修后 D131 谓词层无需扩,D131 §4 边界扩不立(本 D 文档 §备注 D131 §4 边界扩 vs D132 独立新档 取舍 line 锚)
- **风险锚 ≥ 3**:
  - **R1 H1 实测假风险**:§8 反向 / 备选 §H1 不命中回退路径锚 — 退路 H2 codegen 同构剥皮 normalize(候选 B 升根 D132' 独立 D 文档),实测命中预期 ≥ 99%
  - **R2 parser SHR/USHR 表达式上下文副作用**:`bootstrap/parse/parse_exprs.ss:135` SHR/USHR 算子路径走 parseExpr 不经 expectGtTypeCtx,pendingGtTokens 仅类型上下文 isolated(parser.ss:202-206 注释明锚 + maybeNullable 仅 parseTypeAnn 调用,表达式不调) — 副作用 0
  - **R3 generic class / method 类型参数 副作用**:parseTypeAnn 复用于 generic class `class Box<T>` / generic function `function f<T>(x: T)` 类型参数解析,maybeNullable 同 pendingGtTokens 协议 — 修后行为对所有 generic 类型参数同源正确,Execute 阶段 phase4 测试无 regression 验证(预期 ≥ 99% 不影响)
  - **R4 D131 / D130 / D067 联动 RC 契约风险**:D132 修不动 codegen / RC 路径,RC 契约 §5 表既有保留;Execute 阶段 RC stress 50 次循环 + Valgrind / mimalloc no-leak 验证
  - **R5 BFS transitive closure emitPendingDeserializers 在 N=3+ 自动 cover 风险**:D131 §4.4 BFS while 循环既有多层 stripNullableCG,parser 修后输入字符串规范,BFS 多层 stripNullableCG 等价工作 — 验证 N=3+ 形态 BFS 入队正确(`grep "@Tag_deserialize" /tmp/t.ll` ≥ 1)
  - **R6 form 1+2 ship 切分 vs 一并 ship 决策风险**:Execute 阶段下下轮 commit 切分(form 1+2 已 ship-ready 不需 D132 修法 → 单独先 ship vs 与 form 3-6 一并 ship 等 D132 落地)— 预期一并 ship(同 commit 6 fixture 笛卡尔积全形态测试一致性 + commit history 干净 + D132 commit message 一次锚定 — 切分会造成 form 1+2 重复 commit 噪声)
- **后续 issue 自动 cover 路径**:任意 N×M nullable + 嵌套递归同构剥皮全形态在 D132 修后自动 cover,**Phase 4 §247 第二支柱嵌套深化收关候选**(待 §10 三轴实测验证命中后封顶;若三轴破裂分流升根 D133 则收关推迟。后续若有 enum / Optional<T> / Tuple<X, Y> / Set<X> 等容器类型扩展,maybeNullable + pendingGtTokens 修法对所有泛型类型字符串规范形态有效,不需独立子档)

## 10. Execute 阶段实测验证 Plan(下下轮 — 三轴自动 cover 验证)

> 锚明 §备注 §回头观察点 line 334-338 三轴(N=3+ USHR / N=2 任意 M 层 nullable / generic 类型参数副作用)的 RED 命令 + 风险锚 + 假设链 + Execute 落地分流路径,让下下轮 Execute 直接按 Plan 实施不依赖跨轮记忆推断假设链。承本 D 文档 §status Done at commit e75b6ea(parser.ss:790-800 +1 LOC + 9 case + 6 fixture spring-parity ship)。

### 10.1 三轴 RED 命令 scope

**轴 A — N=3+ USHR 拆分 + outer `?`**:`Array<Array<Array<Tag>>>?` / `Map<string, Map<string, Map<string, Tag>>>?` 等 USHR(`>>>`)拆分 pendingGtTokens=2 + outer `?` 形态(D132 §4.2 形态 9 推证范围)。

**轴 B — N=2 任意 M 层 nullable 笛卡尔积**:`Array<Array<Tag?>?>?` 三 `?`(中层 + 内层 + 外层) / `Array<Map<string, Tag?>>?` / `Map<string, Array<Tag?>?>?` 等任意 M 层 `?` 位置组合(D132 §4.2 形态 8 推证范围)。

**轴 C — generic class / method 类型参数副作用**:parseTypeAnn 复用于 generic class `class Box<T>` / generic function `function f<T>(x: T)` 类型参数解析,maybeNullable + pendingGtTokens guard 协议同源应用 — 验证修后无 regression。

### 10.2 假设链推证(三轴自动 cover 物理证明)

**轴 A 推证**(D132 §4.2 形态 9 / `Array<Array<Array<Tag>>>?` Token 流末段:`Tag, USHR, QUESTION`):

| Step | 调用栈 | cursor | pendingGtTokens | 行为 |
|---|---|---|---|---|
| 1 | innermost expectGtTypeCtx | USHR | 0 → 2 | USHR=3 GT,消 1 留 2,pAdvance → QUESTION |
| 2 | innermost maybeNullable("Tag") | QUESTION | 2 | **D132 guard 触发**(pendingGtTokens > 0)→ return "Tag" 不消 QUESTION ✓ |
| 3 | middle expectGtTypeCtx | QUESTION | 2 → 1 | pendingGtTokens > 0 递减,不动 token |
| 4 | middle maybeNullable("Array<Tag>") | QUESTION | 1 | **D132 guard 触发** → return "Array<Tag>" 不消 QUESTION ✓ |
| 5 | outer expectGtTypeCtx | QUESTION | 1 → 0 | pendingGtTokens > 0 递减归零,不动 token |
| 6 | outer maybeNullable("Array<Array<Tag>>") | QUESTION | 0 | curKind=QUESTION ≠ guard → pAdvance + return "Array<Array<Tag>>?" ✓ |

→ parser 输出规范形态 `"Array<Array<Array<Tag>>>?"` ✓ N=3 USHR + outer 自动 cover。**N≥4 形态**(假设有 `>>>>` SHR+USHR 双合并)不存在(lexer 仅合并 SHR / USHR 两档,N=4 走 USHR + 单 GT 拆 = pendingGtTokens=2 + 1 GT 闭合, Token 流不变形)— 任意 N 层自动 cover。

**轴 B 推证**(D132 §4.2 形态 8 / `Array<Array<Tag?>?>?` 三 `?` Token 流:`Tag, QUESTION, GT, QUESTION, GT, QUESTION`):

| Step | 调用栈 | cursor | pendingGtTokens | 行为 |
|---|---|---|---|---|
| 1 | innermost maybeNullable("Tag") | QUESTION | 0 | curKind=QUESTION ≠ guard → pAdvance + return "Tag?" ✓ |
| 2 | middle expectGtTypeCtx | GT | 0 | GT 单 token,pAdvance → QUESTION,pendingGtTokens 不动 |
| 3 | middle maybeNullable("Array<Tag?>") | QUESTION | 0 | curKind=QUESTION → pAdvance + return "Array<Tag?>?" ✓ |
| 4 | outer expectGtTypeCtx | GT | 0 | GT 单 token,pAdvance → QUESTION |
| 5 | outer maybeNullable("Array<Array<Tag?>?>") | QUESTION | 0 | curKind=QUESTION → pAdvance + return "Array<Array<Tag?>?>?" ✓ |

→ parser 输出规范形态 `"Array<Array<Tag?>?>?"` ✓ 三 `?`(中层 + 内层 + 外层)各层 GT 单 token + maybeNullable 各自消一 QUESTION 自动 cover。**任意 M 层 `?` 位置组合**:每层 `?` 由该层 maybeNullable 在 GT 闭合后消;若某层有 SHR/USHR 合并(轴 A+B 交叉),则按 D132 guard 推迟到 outer 闭合后正确归 outer — N×M 全形态(轴 A+B 笛卡尔积)自动 cover。

**轴 C 推证**(generic class/method 类型参数解析复用 parseTypeAnn):

1. **物理位置共享**:`class Box<T>` / `function f<T>(x: T)` 类型参数列表解析复用 parseTypeAnn 入口(`bootstrap/parse/parser.ss:824 IDENT generic 路径` + parseTypeParams / parseGenericParamList)
2. **maybeNullable + pendingGtTokens 协议同源**:类型参数末端 `>` / `>>` / `>>>` 闭合走相同 expectGtTypeCtx;若类型参数本身含 `?`(如 `Box<T?>`)则同 D132 guard 协议
3. **本轮 commit e75b6ea baseline 验证**:phase4/27 + phase5/192 已验 PASS(无 generic 测试 regression),修后 D132 guard 不影响 phase4 generic 测试既有
4. **下下轮 Execute 验证**:phase4 全套(含 generic class/function 测试)+ phase5 全套(含 D132 9 case + 现有所有 nullable 测试)再跑一遍,exit 0 即 cover

### 10.3 风险锚 ≥ 6

- **R1 N=3+ USHR pendingGtTokens=2 拆分 + 中层 maybeNullable guard 触发同源 cover**:轴 A §10.2 推证 6 步 — 若实测发现 N=3+ USHR 错位(如 cursor 上 QUESTION 被 middle / innermost 错位消)→ 升根独立 D 文档 D133-N3-USHR-strip(暂名),Execute 轮停手不动 codegen,改写 next_prompt 转 D 文档单 Layer。**实测命中预期 ≥ 99%**(token 流推证 + lexer USHR 单 token 合并规则物理一致性)。
- **R2 任意 M 层 nullable 笛卡尔积 cover**:轴 B §10.2 推证 5 步 — 若 `Array<Array<Tag?>?>?` 三 `?` 实测错位(中层 / 内层 `?` 被错位归 outer 或 outer 被错位下沉)→ 升根 D133-M-layer-nullable-strip(暂名)。**实测命中预期 ≥ 99%**(各层 GT 单 token 不触 SHR 合并,maybeNullable 各自独立消 QUESTION)。
- **R3 generic class/method 类型参数副作用**:轴 C §10.2 推证 — phase4 全套测试 baseline PASS(本轮 commit e75b6ea 27/27 验证) → 下下轮 Execute 第一步重跑 phase4 全套验证修后等价。若 phase4 generic 测试 regression(如 `class Box<T>` / `function f<T>` 类型参数解析失效)→ 升根 maybeNullable guard scope 缩窄(从所有 parseTypeAnn 缩到字段类型 only)— **实测 regression 概率 < 1%**(maybeNullable 仅 type-position 调用,与表达式上下文 SHR/USHR 物理隔离 — D132 §备注 R2 已锚)。
- **R4 D131 谓词层多层递归 stripNullableCG**(`isArrayDeserializable` / `isMapDeserializable` 在 N=3+ 形态)— D131 §4.1+4.2 既有谓词 stripNullableCG inner 单层递归,N=3+ 形态需谓词三级递归(Array<Array<Array<Tag>>> → et=Array<Array<Tag>> → etStripped=Array<Array<Tag>> → isArrayDeserializable("Array<Array<Tag>>")=1 二级递归 → et=Array<Tag> → etStripped=Array<Tag> → isArrayDeserializable("Array<Tag>")=1 三级递归 → et=Tag → isUserClass("Tag")=1 → 返 1)— 既有谓词函数递归调用支持任意深度。**风险**:若实测 N=3+ 谓词递归断点 → 升根 D131 §4 边界扩(独立 D 文档子决策)。
- **R5 BFS emitPendingDeserializers 多层 stripNullableCG**(N=3+ transitive closure):D131 §4.4 既有 BFS while 循环 + ftStripped = stripNullableCG(ft) 单层 strip + extractContainerElemType 多层递归剥;N=3+ 形态 BFS 入队需 transitive 多层剥皮(`Array<Array<Array<Tag>>>?` → ftStripped="Array<Array<Array<Tag>>>" → BFS extract et="Array<Array<Tag>>" → 入队继续 BFS extract et="Array<Tag>" → 入队 → extract et="Tag" → @Tag_deserialize 入 transitive closure)— 既有 BFS 多层递归 cover。验证锚:`grep "@Tag_deserialize" /tmp/t.ll` ≥ 1 表 transitive closure 入队正确。**风险**:若 BFS 在 N=3+ 形态某层 stripNullableCG 漏调(如只在第一层 strip 而内层 extract 后未再 strip)→ Tag 不入队 → @Tag_deserialize undefined symbol → 升根 D131 §4.4 BFS 多层 stripNullableCG 边界扩。
- **R6 决策预审 — Phase 4 §247 第二支柱嵌套深化封顶 vs 留观察后续容器类型扩展**:三轴全 cover → §10.5 选 A(§247 第二支柱嵌套深化收关 + 后续 enum/Optional<T>/Tuple<X,Y>/Set<X> 等容器扩展不需独立 D 文档子档,留独立 issue 观察 maybeNullable + pendingGtTokens 修法对所有泛型类型字符串规范形态有效);三轴破裂某轴 → §10.5 选 B(§247 收关推迟到 D133 子决策落地后)。

### 10.4 Execute 落地分流锚

**命中分流(预期 ≥ 99%)**:
- 三轴全 cover:5 fixture 测试加挂 `tests/phase5/i021_requestbody_nested_deep_optional.ss`(在现有 9 case 上扩 ~3-5 case 覆盖 N=3+ + N=2 任意 M nullable 形态;`OrderCubeOpt` / `OrderTriCubeOpt` / `OrderTagsArrTripleOpt` / `OrderArrMapTripleOpt` / `OrderMapArrTripleOpt`)
- I021-requestbody-nested-deep-optional 子档 §status reconciliation:加"§10 N=3+ USHR + N=2 任意 M nullable + generic 类型参数副作用三轴自动 cover ship at <test 文件 line>"
- D132 §status:加"§10 三轴自动 cover 实测验证 Done at <test 文件 + emit-ir 锚>"
- D123 §247 章节加锚:"第十二轮 D132 §10 三轴自动 cover 验证 — Phase 4 §第二支柱嵌套深化收关"
- commit 一并 ship:`feat(I021-requestbody-nested-deep-optional-N3,D132,D131,D130,D067,D123,D129): D132 修法 generality 实测验证 — N=3+ USHR + N=2 任意 M 层 nullable + generic 类型参数副作用三轴自动 cover ship — 第四次自动 cover 真零 codegen 场景 — Phase 4 §247 第二支柱嵌套深化第十二轮收关轮`

**不命中分流**:
- 任一轴破裂 → 升根独立 D 文档子决策(暂名 D133-N3-USHR-strip / D133-M-layer-nullable-strip / D133-generic-typearg-side-effect 按破裂轴命名)
- Execute 轮停手不动 codegen / 测试 / I021 子档,改写 next_prompt 转 D 文档子决策起立单 Layer
- 待 D 文档锁定后再回 Execute 落地

### 10.5 决策预审 — Phase 4 §247 第二支柱嵌套深化封顶 vs 留观察

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **三轴全 cover → §247 第二支柱嵌套深化收关** | D132 修法物理位置在 parser 类型解析层 maybeNullable + pendingGtTokens guard 协议,**对所有泛型类型字符串规范形态有效**(不仅 Array/Map);后续 enum / Optional<T> / Tuple<X,Y> / Set<X> 等容器扩展加 emitDeserializeForType case 时,parser 输出已规范,谓词 + 委托递归既有正确 — 自动 cover 不需独立 D 文档子档,留独立 issue 观察。**§247 第二支柱嵌套深化第十二轮收关** ✓ |
| B | 留观察后续容器类型扩展 → §247 不收关待容器扩展时回观 | 保守选项 — 适用于三轴破裂某轴需 D133 升根场景(D132 修法 scope 未完全证明,留 D133 落地后再回判) |

**选 A 条件**:三轴全 cover(轴 A N=3+ USHR + 轴 B 任意 M nullable + 轴 C generic 类型参数副作用)— 若三轴全 PASS 则 D123 §247 章节加 "第十二轮 D132 §10 三轴自动 cover 验证 — 第二支柱嵌套深化收关" 锚。
**选 B 条件**:任一轴破裂 — D133 升根独立 D 文档子决策 落地后再回判收关候选。

### 10.6 RED 命令完整版(下下轮 Execute 第一步实测)

```bash
# 1. 新建 /tmp/t_n3_optional.ss 5-7 fixture(N=3 USHR + N=2 任意 M nullable)
cat > /tmp/t_n3_optional.ss <<'EOF'
class Tag { name: string }

# 轴 A:N=3 USHR + outer `?`
class OrderCubeOpt { customer: string; cube: Array<Array<Array<Tag>>>? }
class OrderTriCubeOpt { customer: string; cube: Map<string, Map<string, Map<string, Tag>>>? }

# 轴 B:N=2 + 三 `?`(中层 + 内层 + 外层)
class OrderTagsArrTripleOpt { customer: string; tags: Array<Array<Tag?>?>? }
class OrderArrMapTripleOpt { customer: string; entries: Array<Map<string, Tag?>>? }
class OrderMapArrTripleOpt { customer: string; lists: Map<string, Array<Tag?>?>? }

# 轴 C:generic class/method 类型参数副作用 — 由 phase4 全套测试 regression 兜底
function main() {
    let o = new OrderCubeOpt(); o.customer = "alice"
    print(o.customer)
}
EOF

# 2. emit-ir 验证 IR 结构
bin/ss build /tmp/t_n3_optional.ss --emit-ir > /tmp/t.ll
grep -cE '@jnIsNullOrMissing' /tmp/t.ll                # ≥ 12(5 fixture × 多层 nullable case 链)
grep -cE 'opt_present|opt_done' /tmp/t.ll              # ≥ 多层(三层 nullable 形态各自消)
grep -cE 'jnArrayLen|jnObjectKeys' /tmp/t.ll           # ≥ N=3 多层链
grep -cE '@Tag_deserialize' /tmp/t.ll                  # ≥ 5(每 fixture × 1 transitive closure)

# 3. 抽 IR body 看 N=3 结构
sed -n "$(grep -n 'define ptr @OrderCubeOpt_deserialize' /tmp/t.ll | head -1 | cut -d: -f1),+90p" /tmp/t.ll
# 期望 N=3:字段 jnGetField → alloca i64 slot + jnIsNullOrMissing + opt_present 内 outer arr_loop +
#   middle arr_loop + inner arr_loop + 最内 @Tag_deserialize 四层链;outer `?` 字段层归 outer

# 4. 抽 IR body 看 N=2 三 `?` 结构
sed -n "$(grep -n 'define ptr @OrderTagsArrTripleOpt_deserialize' /tmp/t.ll | head -1 | cut -d: -f1),+70p" /tmp/t.ll
# 期望:字段层 outer `?` null guard + 中层 `?` element nullable case + 内层 `?` 元素 nullable case 三层

# 5. 轴 C 验证 — bootstrap 固定点 + phase4 全套测试无 regression
./build.sh bootstrap                                   # PASS Stage 2 == Stage 3
bin/ss test tests/phase4/                              # 27/27 PASS(承本轮 commit e75b6ea baseline)
bin/ss test tests/phase5/                              # baseline 4 failure 与 D132 无关 confirmed
bin/ss run tools/reflection_health_linter.ss          # GATE PASS no regressions
```

### 10.7 不变量保留

D018 ObjectLayout(RC@0 + TypeInfo@1) + D022 clone 语义 + D088 编译期展开消除运行时反射 + D130 emitDeserializeForType SSoT 单点解码 + D131 谓词层 stripNullableCG inner + D067 null safety T? 概念锚(memory `project_null_safety_design.md`)+ D132 maybeNullable + pendingGtTokens guard 全形态自动 cover + 本轮 commit e75b6ea 9 case + 6 fixture spring-parity ship。

### 10.8 Layer 跨越 / Plan vs Execute

- 本节(D132 §10)= **Plan 型 Decision sub-section 增量** — 写下下轮 Execute 实测验证 Plan,本轮不动 codegen / 测试 / I021 子档 §status,Execute 留下下轮
- 下下轮 = **Execute 型 Implementation 层** — 按 §10.6 RED 命令实测 → §10.4 命中加测试 ship 收关 / 不命中升根 D133 起立(分流锚)
- 单 Layer 不混(MNK §字段 8 — Decision sub-section 增量与 Execute Implementation 跨 Layer 拆轮)
